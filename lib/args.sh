# args.sh — Command-line argument parsing and early-exit dispatch.
#
# parse_args() sets globals from CLI flags, validates playlist options,
# and dispatches early-exit actions (help, init, status, reset, monitor).

parse_args() {
    ACTION=""
    local commit_explicit=false
    ORIGINAL_ARGS=("$@")
    parse_arg_flags "$@"
    validate_model_args
    validate_playlist_args "$commit_explicit"
    [[ "$ACTION" == "queue" ]] && build_forwarded_queue_args
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
            --queue)
                ACTION="queue"
                if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                    QUEUE_FILE="$2"; shift 2
                else
                    QUEUE_FILE=".ralph/queue"; shift
                fi
                ;;
            --no-commit)   AUTO_COMMIT=false; commit_explicit=true; shift ;;
            --commit)      AUTO_COMMIT=true; commit_explicit=true; shift ;;
            --sandbox)     SANDBOX_MODE=true; shift ;;
            --model)       MODEL="$2"; shift 2 ;;
            --context-files) CONTEXT_FILES="$2"; shift 2 ;;
            --max-cost)    MAX_COST_USD="$2"; shift 2 ;;
            --playlist-branch) PLAYLIST_BRANCH_CLI="$2"; shift 2 ;;
            --yes|-y)      YES=true; PLAYLIST_AUTO_CONTINUE=true; shift ;;
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
            playlist)
                case "${2:-}" in
                    init)
                        if [[ -n "${3:-}" ]]; then
                            ACTION="playlist_init"
                            PLAYLIST="$3"
                            shift 3
                        else
                            log "ERROR: Usage: ralph playlist init <file>"
                            exit 1
                        fi
                        ;;
                    create)
                        ACTION="playlist_create"
                        shift 2
                        parse_playlist_create_args "$@"
                        return
                        ;;
                    *)
                        log "ERROR: Usage: ralph playlist {init|create}"
                        exit 1
                        ;;
                esac
                ;;
            *)
                log "ERROR: Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# ── parse_playlist_create_args ─────────────────────────────────────────────
#
# Parse arguments for "ralph playlist create <ids...> --epic <epic-id> -o <file>".
# Sets globals: PLAYLIST_CREATE_BEADS[], PLAYLIST_CREATE_EPICS[], OUTPUT_FILE

parse_playlist_create_args() {
    PLAYLIST_CREATE_BEADS=()
    PLAYLIST_CREATE_EPICS=()
    OUTPUT_FILE=""

    local collecting_ids=true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --epic)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR: --epic requires an argument"
                    exit 1
                fi
                collecting_ids=false
                PLAYLIST_CREATE_EPICS+=("$2")
                shift 2
                ;;
            -o)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR: -o requires an output file"
                    exit 1
                fi
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -*)
                log "ERROR: Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ "$collecting_ids" == true ]]; then
                    PLAYLIST_CREATE_BEADS+=("$1")
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$OUTPUT_FILE" ]]; then
        log "ERROR: -o <output-file> is required"
        exit 1
    fi

    if [[ ${#PLAYLIST_CREATE_BEADS[@]} -eq 0 && ${#PLAYLIST_CREATE_EPICS[@]} -eq 0 ]]; then
        log "ERROR: Provide either bead IDs or --epic flags"
        exit 1
    fi
}

# ── validate_model_args ──────────────────────────────────────────────────────
#
# Validate model argument. If it's a GLM model, extract and validate
# the version number. Stores the result in GLOBAL_GLM_VERSION for use
# during initialization.

GLOBAL_GLM_VERSION=""

validate_model_args() {
    [[ -z "$MODEL" ]] && return

    if detect_invalid_glm_pattern "$MODEL"; then
        log "ERROR: Invalid GLM model format: $MODEL"
        log "  Expected format: glm-X or glm-X.Y (e.g., glm-4.7, glm-5)"
        exit 1
    fi

    if is_glm_model "$MODEL"; then
        GLOBAL_GLM_VERSION=$(extract_glm_version "$MODEL")
    fi
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
        help)           show_help; exit 0 ;;
        init)           init_project; exit 0 ;;
        status)         show_status; exit 0 ;;
        reset)          reset_state; exit 0 ;;
        playlist_init)  init_for_early_claude; run_playlist_init; exit $? ;;
        playlist_create) init_for_early_claude; run_playlist_create; exit $? ;;
        queue)          run_queue; exit $? ;;
    esac

    if [[ "$MONITOR_MODE" == "true" ]]; then
        run_monitor
        exit $?
    fi
}

# ── build_forwarded_queue_args ─────────────────────────────────────────────
#
# Build FORWARDED_QUEUE_ARGS by stripping --queue (and its optional
# value) from the parent's argv. Everything else (--max-cost, --model,
# --remote, …) propagates to each child ralph invocation.

build_forwarded_queue_args() {
    FORWARDED_QUEUE_ARGS=()
    local i=0 arg nxt
    while (( i < ${#ORIGINAL_ARGS[@]} )); do
        arg="${ORIGINAL_ARGS[$i]}"
        if [[ "$arg" == "--queue" ]]; then
            nxt="${ORIGINAL_ARGS[$((i + 1))]:-}"
            if [[ -n "$nxt" && ! "$nxt" =~ ^- ]]; then
                i=$((i + 2))
            else
                i=$((i + 1))
            fi
            continue
        fi
        FORWARDED_QUEUE_ARGS+=("$arg")
        i=$((i + 1))
    done
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
