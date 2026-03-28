# args.sh — Command-line argument parsing and early-exit handlers.
#
# Defines parse_args() which processes CLI flags into global config variables.
# Handles --help, --status, and --reset directly (these exit immediately).

parse_args() {
    # ACTION tracks whether the user requested help/status/reset
    # instead of running the loop.
    ACTION=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --max-tasks)
                MAX_TASKS="$2"
                shift 2
                ;;
            --max-loops)
                MAX_LOOPS="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT_MINUTES="$2"
                shift 2
                ;;
            --scope)
                SCOPE="$2"
                shift 2
                ;;
            --sandbox)
                SANDBOX_MODE=true
                shift
                ;;
            --model)
                MODEL="$2"
                shift 2
                ;;
            --monitor)
                MONITOR_MODE=true
                shift
                ;;
            --remote|-r)
                REMOTE_MODE=true
                if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                    REMOTE_HOST="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --tmux|-t)
                TMUX_MODE=true
                shift
                ;;
            --status)
                ACTION="status"
                shift
                ;;
            --reset)
                ACTION="reset"
                shift
                ;;
            -h|--help)
                ACTION="help"
                shift
                ;;
            *)
                log "ERROR: Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # ── Early exits ─────────────────────────────────────────────────────────
    # These actions print output and exit before the main loop starts.

    if [[ "$ACTION" == "help" ]]; then
        cat <<'USAGE'
ralph — Autonomous task executor. Loops Claude Code over beads issues.

Usage: ralph [OPTIONS]
  --dry-run            Show next task without executing
  --max-tasks N        Stop after N tasks completed (default: unlimited)
  --max-loops N        Stop after N Claude invocations (default: 50)
  --timeout N          Minutes per Claude invocation (default: 10)
  --scope PATTERN      Only work issues matching regex pattern
  --sandbox            Wrap Claude in bubblewrap sandbox (Linux only)
  --model MODEL        Claude model to use (default: config.sh)
  --monitor            Live dashboard in a separate terminal
  --tmux, -t           Wrap execution in a detachable tmux session
  --remote [HOST], -r  Run on remote server via SSH+tmux
  --status             Print current state and exit
  --reset              Clear circuit breaker and loop state
  -h, --help           Show this help
USAGE
        exit 0
    fi

    if [[ "$ACTION" == "status" ]]; then
        if [[ -f "$STATE_FILE" ]]; then
            log "Current state:"
            cat "$STATE_FILE"
        else
            log "No state file. Ralph has not run here."
        fi
        exit 0
    fi

    if [[ "$ACTION" == "reset" ]]; then
        circuit="CLOSED"
        no_progress_count=0
        total_tasks_completed=0
        total_loops=0
        current_task=""
        save_state
        rm -f .ralph_remote
        log "State reset."
        exit 0
    fi

    if [[ "$MONITOR_MODE" == "true" ]]; then
        run_monitor
        exit $?
    fi
}
