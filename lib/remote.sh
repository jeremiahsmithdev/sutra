# remote.sh — Remote execution and tmux session management.
#
# Two entry points:
#   ralph --remote HOST  → push, sync tool, SSH once to run ralph --tmux
#   ralph --tmux         → ensure repo, wrap execution in tmux session
#
# The --remote flow passes CLONE_URL, REMOTE_DIR, WORKING_BRANCH as
# env vars to the remote, avoiding the chicken-and-egg problem of
# needing .sutra/config before the repo is cloned.

# ── sync_ralph ────────────────────────────────────────────────────────────
#
# Install or update ralph on the remote server by rsyncing the local
# script directory to ~/.sutra/. Fast for repeat runs (unchanged files
# are skipped). Excludes .git and local state.

sync_ralph() {
    log "Syncing ralph to $REMOTE_HOST:~/.sutra/..."
    rsync -az --delete \
        "$SCRIPT_DIR/" \
        "$REMOTE_HOST:~/.sutra/" \
        --exclude '.git' \
        --exclude '.sutra/state'
}

# ── build_forward_args ────────────────────────────────────────────────────
#
# Reconstruct CLI args from parsed globals. Used by run_remote() and
# run_tmux() to forward flags without --remote or --tmux.

build_forward_args() {
    FORWARD_ARGS=()
    FORWARD_ARGS+=(--max-tasks "$MAX_TASKS")
    FORWARD_ARGS+=(--max-loops "$MAX_LOOPS")
    FORWARD_ARGS+=(--timeout "$TIMEOUT_MINUTES")
    FORWARD_ARGS+=(--model "$MODEL")
    [[ "$DRY_RUN" == "true" ]] && FORWARD_ARGS+=(--dry-run)
    [[ -n "$SCOPE" ]] && FORWARD_ARGS+=(--scope "$SCOPE")
    [[ "$SANDBOX_MODE" == "true" ]] && FORWARD_ARGS+=(--sandbox)
}

# ── run_remote ────────────────────────────────────────────────────────────
#
# Entry point for --remote mode:
#   1. Push current branch to origin
#   2. Sync ralph tool to remote server
#   3. Single SSH call with env vars to run ralph --tmux

run_remote() {
    if [[ -z "$REMOTE_HOST" ]]; then
        log "ERROR: No remote host. Use --remote HOST or set REMOTE_HOST in config."
        exit 1
    fi

    # --remote is incompatible with linked git worktrees: the worktree's
    # `.git` is a file pointing to an absolute path inside the main repo
    # on this machine. Rsyncing it to the remote produces a checkout
    # whose git metadata references a non-existent path, breaking every
    # subsequent git command.
    local git_dir common_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null)
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    if [[ -n "$git_dir" && -n "$common_dir" ]]; then
        git_dir=$(cd "$git_dir" 2>/dev/null && pwd)
        common_dir=$(cd "$common_dir" 2>/dev/null && pwd)
        if [[ "$git_dir" != "$common_dir" ]]; then
            log "ERROR: --remote cannot be used from a git worktree."
            log "       The worktree's .git file references an absolute path on this"
            log "       machine that does not exist on the remote. Run --remote from"
            log "       the main clone, or push the branch and clone it on the remote."
            exit 1
        fi
    fi

    # Remote targets are Linux — always enable bubblewrap sandbox
    SANDBOX_MODE=true

    # Step 1: Push to origin so the remote can fetch latest
    local clone_url current_branch
    clone_url=$(git remote get-url origin 2>/dev/null) || {
        log "ERROR: No git remote 'origin' configured. Cannot push to remote."
        exit 1
    }
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    log "Pushing ${C_BOLD_CYAN}$current_branch${C_RESET} to origin..."
    git push origin "$current_branch" || {
        log "ERROR: git push failed"
        exit 1
    }

    # Step 2: Sync ralph tool to remote
    sync_ralph

    # Step 3: Build args and SSH once
    build_forward_args
    local -a args=(--tmux "${FORWARD_ARGS[@]}")

    # Compute REMOTE_DIR from repo name if not set
    if [[ -z "$REMOTE_DIR" ]]; then
        REMOTE_DIR="~/$(basename -s .git "$clone_url")"
    fi

    # Save remote config locally so --monitor can find it
    printf 'REMOTE_HOST=%s\nREMOTE_DIR=%s\n' "$REMOTE_HOST" "$REMOTE_DIR" > .sutra_remote

    local ralph_cmd="~/.sutra/ralph ${args[*]}"
    local working_branch="${WORKING_BRANCH:-$current_branch}"

    log "Starting ralph on ${C_BOLD_CYAN}$REMOTE_HOST${C_RESET}..."
    ssh -t "$REMOTE_HOST" "\
        export CLONE_URL='$clone_url' \
               REMOTE_DIR='$REMOTE_DIR' \
               WORKING_BRANCH='$working_branch'; \
        $ralph_cmd"
}

# ── ensure_remote_repo ────────────────────────────────────────────────────
#
# Clone the project repo if it doesn't exist at REMOTE_DIR, or
# fetch + checkout if it does. Called by run_tmux() when CLONE_URL
# is set (i.e. triggered by --remote, not manual use).

ensure_remote_repo() {
    local expanded_dir="${REMOTE_DIR/#\~/$HOME}"

    if [[ ! -d "$expanded_dir/.git" ]]; then
        log "Cloning to ${C_BOLD_CYAN}$expanded_dir${C_RESET}..."
        git clone "$CLONE_URL" "$expanded_dir"
    else
        log "Fetching updates in ${C_BOLD_CYAN}$expanded_dir${C_RESET}..."
        git -C "$expanded_dir" fetch --quiet
    fi

    # Checkout the target branch
    local branch="${WORKING_BRANCH:-$(git -C "$expanded_dir" rev-parse --abbrev-ref HEAD)}"
    git -C "$expanded_dir" checkout "$branch" 2>/dev/null || {
        log "WARNING: Could not checkout $branch, staying on current branch"
    }

    # Fast-forward to latest
    git -C "$expanded_dir" pull --ff-only 2>/dev/null || true

    log "Repository ready at ${C_BOLD_CYAN}$expanded_dir${C_RESET}"
}

# ── run_tmux ──────────────────────────────────────────────────────────────
#
# Entry point for --tmux mode. Two use cases:
#   1. Triggered by --remote: CLONE_URL is set → clone/fetch repo first
#   2. Manual SSH: user is already in project dir → skip repo setup
#
# Creates a tmux session named "ralph" and runs the loop inside it.

run_tmux() {
    if ! command -v tmux &>/dev/null; then
        log "ERROR: tmux required for --tmux mode"
        exit 1
    fi

    # If CLONE_URL is set, we were triggered by --remote — set up the repo
    if [[ -n "${CLONE_URL:-}" ]]; then
        ensure_remote_repo
    fi

    # Check for existing tmux session
    if tmux has-session -t ralph 2>/dev/null; then
        log "ERROR: Ralph is already running in tmux session 'ralph'"
        log "  Attach:  tmux attach -t ralph"
        log "  Kill:    tmux kill-session -t ralph"
        exit 1
    fi

    # Build the inner ralph command (without --tmux or --remote)
    build_forward_args
    local ralph_path="$SCRIPT_DIR/ralph"
    local ralph_cmd="'$ralph_path' ${FORWARD_ARGS[*]}"

    # cd to REMOTE_DIR if set (remote case), otherwise stay in CWD
    local cd_cmd=""
    if [[ -n "${REMOTE_DIR:-}" ]]; then
        local expanded_dir="${REMOTE_DIR/#\~/$HOME}"
        cd_cmd="cd '$expanded_dir' && "
    fi

    log "Creating tmux session ${C_BOLD_CYAN}ralph${C_RESET}..."
    tmux new-session -d -s ralph
    tmux send-keys -t ralph "${cd_cmd}${ralph_cmd}" Enter

    log "Attaching — detach with ${C_BOLD}Ctrl+B, D${C_RESET}"
    tmux attach -t ralph
}
