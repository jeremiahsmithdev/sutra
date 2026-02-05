# remote.sh — Remote execution via SSH+tmux.
#
# Syncs ralph to the remote server, checks for conflicts,
# and starts ralph in a tmux session the user can detach from.

# ── sync_ralph ────────────────────────────────────────────────────────────
#
# Install or update ralph on the remote server by rsyncing the local
# script directory to ~/.ralph/. Fast for repeat runs (unchanged files
# are skipped). Excludes .git and local state.

sync_ralph() {
    log "Syncing ralph to $REMOTE_HOST:~/.ralph/..."
    rsync -az --delete \
        "$SCRIPT_DIR/" \
        "$REMOTE_HOST:~/.ralph/" \
        --exclude '.git' \
        --exclude '.ralph_state'
}

# ── run_remote ────────────────────────────────────────────────────────────
#
# Entry point for --remote mode. Three distinct steps:
#   1. Install/update ralph on the remote server
#   2. Check if ralph is already running (refuse if so)
#   3. Start ralph in a new tmux session and attach

run_remote() {
    if [[ -z "$REMOTE_HOST" ]]; then
        log "ERROR: No remote host. Use --remote HOST or set REMOTE_HOST in config."
        exit 1
    fi

    # Step 1: Install/update ralph on the remote
    sync_ralph

    # Step 2: Refuse if ralph is already running
    if ssh "$REMOTE_HOST" "tmux has-session -t ralph 2>/dev/null"; then
        log "ERROR: Ralph is already running on $REMOTE_HOST"
        log "  Attach:  ssh $REMOTE_HOST -t \"tmux attach -t ralph\""
        log "  Kill:    ssh $REMOTE_HOST \"tmux kill-session -t ralph\""
        exit 1
    fi

    # Build args to forward (exclude --remote)
    local -a args=(
        --max-tasks "$MAX_TASKS"
        --max-loops "$MAX_LOOPS"
        --timeout "$TIMEOUT_MINUTES"
    )
    [[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)
    [[ -n "$SCOPE" ]] && args+=(--scope "$SCOPE")
    [[ "$SANDBOX_MODE" == "true" ]] && args+=(--sandbox)

    local ralph_cmd="~/.ralph/ralph ${args[*]}"
    local cd_cmd=""
    if [[ -n "$REMOTE_DIR" ]]; then
        cd_cmd="cd $REMOTE_DIR && "
    fi

    # Step 3: Start ralph in a new tmux session and attach
    log "Starting ralph on $REMOTE_HOST..."
    ssh -t "$REMOTE_HOST" "\
        tmux new-session -d -s ralph && \
        tmux send-keys -t ralph '${cd_cmd}${ralph_cmd}' Enter && \
        tmux attach -t ralph"
}
