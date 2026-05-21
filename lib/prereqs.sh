# prereqs.sh — Prerequisite checks before the loop can start.
#
# Verifies that all required CLI tools are installed and that the
# current directory is a beads-enabled project. Exits with a clear
# error message if anything is missing.

check_prereqs() {
    local missing=0

    # Check for required CLI tools
    for cmd in jq br claude; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR: Required: $cmd"
            missing=1
        fi
    done

    # GNU timeout is needed to kill hung Claude invocations.
    # On macOS it's installed as gtimeout via `brew install coreutils`.
    TIMEOUT_CMD=$(command -v gtimeout 2>/dev/null || command -v timeout 2>/dev/null || true)
    if [[ -z "$TIMEOUT_CMD" ]]; then
        log "ERROR: gtimeout or timeout required (brew install coreutils)"
        missing=1
    fi

    # Ralph only works inside a beads-tracked project
    if [[ ! -d ".beads" ]]; then
        log "ERROR: No .beads/ in $(pwd)"
        missing=1
    fi

    # Bubblewrap is only available on Linux.
    if [[ "$SANDBOX_MODE" == "true" ]]; then
        if [[ "$(uname -s)" != "Linux" ]]; then
            log "WARNING: --sandbox requires Linux (bwrap unavailable on $(uname -s)), disabling"
            SANDBOX_MODE=false
        elif ! command -v bwrap &>/dev/null; then
            log "ERROR: --sandbox requires bwrap (apt install bubblewrap)"
            missing=1
        fi
    fi

    if [[ $missing -eq 1 ]]; then
        exit 1
    fi

    # Ensure "event" issue type is configured for br.
    # Only log when we actually need to add it (not every startup).
    if ! br config get types.custom 2>/dev/null | grep -q "event"; then
        br config set types.custom "event" 2>/dev/null || true
    fi

    detect_worktree
}

# ── detect_worktree ───────────────────────────────────────────────────────
#
# If ralph was started inside a linked git worktree (not the main clone),
# announce it loudly and warn about per-worktree state isolation. Sets
# IS_WORKTREE=true and WORKTREE_NAME globals for downstream consumers
# (e.g. playlist_branch.sh suffixing default branch names).

detect_worktree() {
    IS_WORKTREE=false
    WORKTREE_NAME=""

    local git_dir common_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || return
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return

    # Resolve to absolute paths so the comparison survives ./ prefixes.
    git_dir=$(cd "$git_dir" 2>/dev/null && pwd) || return
    common_dir=$(cd "$common_dir" 2>/dev/null && pwd) || return

    [[ "$git_dir" == "$common_dir" ]] && return  # main clone, not a worktree

    IS_WORKTREE=true
    local worktree_path main_path
    worktree_path=$(git rev-parse --show-toplevel 2>/dev/null)
    main_path=$(dirname "$common_dir")
    WORKTREE_NAME=$(basename "$worktree_path")

    log "Worktree mode: ${C_BOLD_CYAN}$worktree_path${C_RESET}"
    log "Main repo:     ${C_DIM}$main_path${C_RESET}"
    log "Note: ${C_BOLD_YELLOW}.beads/ and .sutra/ are per-worktree${C_RESET} — bead state will not sync to other worktrees until \`.beads/issues.jsonl\` is committed and pulled."
}

# ── ensure_ralph_branch ───────────────────────────────────────────────────
#
# Ensure the dedicated "ralph" working branch exists and is checked out.
# Creates it from WORKING_BRANCH (set in .sutra/config) or the current branch.

ensure_correct_branch() {
    if [[ -n "$PLAYLIST_BRANCH" ]]; then
        ensure_playlist_branch
    else
        ensure_ralph_branch
    fi
}

ensure_ralph_branch() {
    checkout_or_create_branch "ralph"
}

ensure_playlist_branch() {
    checkout_or_create_branch "$PLAYLIST_BRANCH"
}

checkout_or_create_branch() {
    local branch="$1"

    # Skip the checkout entirely if we're already on the target branch.
    # Avoids a redundant "fatal: already checked out" error when ralph
    # is started inside a worktree whose HEAD already matches.
    local current
    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$current" == "$branch" ]]; then
        log "On branch: ${C_BOLD_CYAN}$branch${C_RESET}"
        return
    fi

    if git rev-parse --verify "$branch" &>/dev/null; then
        # If the branch is checked out in another worktree, git refuses
        # the checkout. Detect this up front and produce a useful error.
        local other_worktree
        other_worktree=$(branch_checked_out_elsewhere "$branch")
        if [[ -n "$other_worktree" ]]; then
            log "ERROR: branch ${C_BOLD_CYAN}$branch${C_RESET} is already checked out at ${C_BOLD_YELLOW}$other_worktree${C_RESET}"
            log "       Run ralph from that worktree, or pass --playlist-branch to choose a different branch."
            exit 1
        fi
        git checkout "$branch" 2>/dev/null || {
            log "ERROR: Could not switch to $branch branch"
            exit 1
        }
        log "On branch: ${C_BOLD_CYAN}$branch${C_RESET}"
    else
        local base="${WORKING_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
        log "Creating branch ${C_BOLD_CYAN}$branch${C_RESET} from ${C_CYAN}$base${C_RESET}..."
        git checkout -b "$branch" "$base" 2>/dev/null || {
            log "ERROR: Could not create $branch branch from $base"
            exit 1
        }
    fi
}

# ── branch_checked_out_elsewhere ──────────────────────────────────────────
#
# If $1 is checked out in any other worktree, echo that worktree's path.
# Otherwise echo nothing. Uses `git worktree list --porcelain` so it
# works even when ralph is itself running inside a worktree.

branch_checked_out_elsewhere() {
    local branch="$1"
    local self
    self=$(git rev-parse --show-toplevel 2>/dev/null)
    git worktree list --porcelain 2>/dev/null | awk -v target="refs/heads/$branch" -v self="$self" '
        /^worktree / { wt = substr($0, 10); next }
        /^branch /   { if ($2 == target && wt != self) { print wt; exit } }
    '
}
