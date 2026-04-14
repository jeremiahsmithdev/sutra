# lifecycle.sh — Session lifecycle: initialisation and exit summary.
#
# initialize() sets up the environment after argument parsing.
# cleanup() is registered via `trap cleanup EXIT` and runs on any exit.

# ── init_for_early_claude ─────────────────────────────────────────────
#
# Minimal bootstrap for early-exit commands that invoke Claude
# (playlist init, playlist create). These dispatch before the full
# initialize() runs, so they need prereqs, state, and invoke setup.

init_for_early_claude() {
    check_prereqs
    load_state
    # Clear task-execution state — early-exit commands don't run the main loop,
    # so stale current_task from a previous interrupted run must not persist.
    current_task=""
    init_invoke
}

init_project() {
    if [[ -f ".ralph/config" ]]; then
        log "WARNING: .ralph/config already exists. Skipping."
        exit 0
    fi
    mkdir -p .ralph
    cat "$TEMPLATES_DIR/config.template" > .ralph/config
    log "Created .ralph/config"
}

initialize() {
    parse_args "$@"
    show_splash
    if [[ "$REMOTE_MODE" == "true" ]]; then run_remote; exit $?; fi
    if [[ "$TMUX_MODE" == "true" ]]; then run_tmux; exit $?; fi
    check_prereqs
    # Setup GLM environment if using GLM model
    if [[ -n "$GLOBAL_GLM_VERSION" ]]; then
        setup_glm_env "$GLOBAL_GLM_VERSION"
    fi
    if [[ "$DRY_RUN" != "true" ]]; then
        migrate_state_file
        commit_beads_if_dirty
    fi
    if [[ -n "$PLAYLIST" ]]; then playlist_resolve_branch; fi
    if [[ "$DRY_RUN" != "true" ]]; then
        ensure_correct_branch
    fi
    trap handle_interrupt INT
    trap cleanup EXIT
    load_state
    init_sandbox
    init_invoke
    if [[ "$DRY_RUN" != "true" ]]; then ensure_project_summary; fi
    if [[ -n "$PLAYLIST" ]]; then playlist_init; fi
}

# ── handle_interrupt ───────────────────────────────────────────────────────
#
# SIGINT handler. Kills any live Claude child and exits with 130.

handle_interrupt() {
    EXIT_REASON="Interrupted (Ctrl+C)"
    [[ -n "${CLAUDE_PID:-}" ]] && kill -KILL "$CLAUDE_PID" 2>/dev/null
    exit 130
}

cleanup() {
    local tasks="${total_tasks_completed:-0}"
    local loops="${total_loops:-0}"
    local cb="${circuit:-CLOSED}"

    if [[ -n "${PLAYLIST:-}" && "$tasks" -gt 0 && "$DRY_RUN" != "true" ]]; then
        generate_playlist_report
    fi

    log "=== Session Complete ==="
    render_session_summary "$tasks" "$loops" "$cb"

    # Teardown GLM environment after all cleanup is complete
    teardown_glm_env
}

# ── render_session_summary ─────────────────────────────────────────────────
#
# Print the boxed end-of-session summary. Takes the values as args so the
# function is testable and doesn't reach into cleanup()'s locals.

render_session_summary() {
    local tasks="$1" loops="$2" cb="$3"
    local cb_color
    cb_color=$(circuit_color "$cb")

    printf '%s\n' "${C_DIM}┌─── Summary ───────────────────────────────────────────┐${C_RESET}"
    printf '%s│%s  Tasks completed:  %s%-4s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD_GREEN" "$tasks" "$C_RESET"
    printf '%s│%s  Total loops:      %s%-4s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD" "$loops" "$C_RESET"
    printf '%s│%s  Total cost:       %s$%s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD" "${total_cost_usd:-0.00}" "$C_RESET"
    printf '%s│%s  Circuit breaker:  %s%s%s\n' "$C_DIM" "$C_RESET" "$cb_color" "$cb" "$C_RESET"
    printf '%s│%s  Exit reason:      %s\n' "$C_DIM" "$C_RESET" "$EXIT_REASON"
    printf '%s│%s  Session log:      %s%s%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "${SESSION_LOG:-unknown}" "$C_RESET"
    printf '%s└───────────────────────────────────────────────────────┘%s\n' "$C_DIM" "$C_RESET"
    printf '%s\n' "${C_DIM}Run \`bnr\` to review completed work.${C_RESET}"
}

# Map a circuit breaker state to its display color.
circuit_color() {
    case "$1" in
        OPEN)      echo "$C_BOLD_RED" ;;
        HALF_OPEN) echo "$C_BOLD_YELLOW" ;;
        *)         echo "$C_GREEN" ;;
    esac
}

# ── generate_playlist_report ──────────────────────────────────────────────
#
# Invoke Claude one final time to write a structured markdown report.
# Called from cleanup() when playlist mode had at least 1 task processed.

generate_playlist_report() {
    local report_dir=".ralph/reports"
    local playlist_basename
    playlist_basename=$(basename "$PLAYLIST" | sed 's/\.[^.]*$//')
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local report_file="$report_dir/${playlist_basename}-${timestamp}.md"

    log "Generating playlist completion report..."

    local playlist_data git_log
    playlist_data=$(playlist_report_data 2>/dev/null) || playlist_data="(unable to gather playlist data)"
    git_log=$(git log --oneline --since="${session_start:-1 hour ago}" 2>/dev/null) || git_log="(no commits)"

    build_report_prompt "$report_dir" "$report_file" "$playlist_data" "$git_log"
    invoke_claude || {
        log "WARNING: Report generation failed. Continuing cleanup."
        return
    }

    log "Report written to ${C_BOLD}$report_file${C_RESET}"
}
