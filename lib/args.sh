# args.sh — Command-line argument parsing and early-exit dispatch.
#
# parse_args() sets globals from CLI flags, validates playlist options,
# and dispatches early-exit actions (help, init, status, reset, monitor).

parse_args() {
    ACTION=""
    local commit_explicit=false
    parse_arg_flags "$@"
    validate_playlist_args "$commit_explicit"
    dispatch_early_exit_action
}

# ── parse_arg_flags ────────────────────────────────────────────────────────
#
# Walk the argv and set global config vars. Single-use variable
# commit_explicit is set in the enclosing scope so validate_playlist_args
# can see whether --commit/--no-commit was passed.

parse_arg_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)     DRY_RUN=true; shift ;;
            --max-tasks)   MAX_TASKS="$2"; shift 2 ;;
            --max-loops)   MAX_LOOPS="$2"; shift 2 ;;
            --timeout)     TIMEOUT_MINUTES="$2"; shift 2 ;;
            --scope)       SCOPE="$2"; shift 2 ;;
            --playlist)    PLAYLIST="$2"; shift 2 ;;
            --no-commit)   AUTO_COMMIT=false; commit_explicit=true; shift ;;
            --commit)      AUTO_COMMIT=true; commit_explicit=true; shift ;;
            --sandbox)     SANDBOX_MODE=true; shift ;;
            --model)       MODEL="$2"; shift 2 ;;
            --context-files) CONTEXT_FILES="$2"; shift 2 ;;
            --playlist-branch) PLAYLIST_BRANCH_CLI="$2"; shift 2 ;;
            --monitor)     MONITOR_MODE=true; shift ;;
            --tmux|-t)     TMUX_MODE=true; shift ;;
            --init)        ACTION="init"; shift ;;
            --status)      ACTION="status"; shift ;;
            --reset)       ACTION="reset"; shift ;;
            -h|--help)     ACTION="help"; shift ;;
            --remote|-r)
                REMOTE_MODE=true
                if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                    REMOTE_HOST="$2"; shift 2
                else
                    shift
                fi
                ;;
            *)
                log "ERROR: Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# ── validate_playlist_args ─────────────────────────────────────────────────
#
# Check --playlist file exists, reject --playlist + --scope combo, and
# default to no per-task commits in playlist mode unless explicitly overridden.

validate_playlist_args() {
    local commit_explicit="$1"
    [[ -z "$PLAYLIST" ]] && return

    if [[ ! -f "$PLAYLIST" ]]; then
        log "ERROR: Playlist file not found: $PLAYLIST"
        exit 1
    fi
    if [[ -n "$SCOPE" ]]; then
        log "ERROR: Cannot use --playlist with --scope"
        exit 1
    fi
    if [[ "$commit_explicit" == false ]]; then
        AUTO_COMMIT=false
    fi
    if [[ -n "$PLAYLIST_BRANCH_CLI" && -z "$PLAYLIST" ]]; then
        log "ERROR: --playlist-branch requires --playlist"
        exit 1
    fi
}

# ── dispatch_early_exit_action ─────────────────────────────────────────────
#
# Route the ACTION set by parse_arg_flags to its handler, then exit.
# Each handler prints output and terminates without entering the main loop.

dispatch_early_exit_action() {
    case "$ACTION" in
        help)   show_help; exit 0 ;;
        init)   init_project; exit 0 ;;
        status) show_status; exit 0 ;;
        reset)  reset_state; exit 0 ;;
    esac

    if [[ "$MONITOR_MODE" == "true" ]]; then
        run_monitor
        exit $?
    fi
}

# ── show_help ──────────────────────────────────────────────────────────────

show_help() {
    cat "$TEMPLATES_DIR/usage.txt"
}

# ── show_status ────────────────────────────────────────────────────────────

show_status() {
    if [[ -f "$STATE_FILE" ]]; then
        log "Current state:"
        cat "$STATE_FILE"
    else
        log "No state file. Ralph has not run here."
    fi
}

# ── reset_state ────────────────────────────────────────────────────────────

reset_state() {
    circuit="CLOSED"
    no_progress_count=0
    total_tasks_completed=0
    total_loops=0
    current_task=""
    save_state
    rm -f .ralph_remote
    log "State reset."
}
