# lifecycle.sh — Session lifecycle: initialisation and exit summary.
#
# initialize() sets up the environment after argument parsing.
# cleanup() is registered via `trap cleanup EXIT` and runs on any exit.

initialize() {
    parse_args "$@"
    show_splash
    if [[ "$REMOTE_MODE" == "true" ]]; then run_remote; exit $?; fi
    if [[ "$TMUX_MODE" == "true" ]]; then run_tmux; exit $?; fi
    check_prereqs
    commit_beads_if_dirty
    ensure_ralph_branch
    trap 'EXIT_REASON="Interrupted (Ctrl+C)"; [[ -n "${CLAUDE_PID:-}" ]] && kill -KILL "$CLAUDE_PID" 2>/dev/null; exit 130' INT
    trap cleanup EXIT
    load_state
    init_sandbox
    init_invoke
    if [[ -n "$PLAYLIST" ]]; then playlist_init; fi
}

cleanup() {
    local tasks="${total_tasks_completed:-0}"
    local loops="${total_loops:-0}"
    local cb="${circuit:-CLOSED}"

    # Generate playlist completion report if in playlist mode with work done
    if [[ -n "${PLAYLIST:-}" && "$tasks" -gt 0 && "$DRY_RUN" != "true" ]]; then
        generate_playlist_report
    fi

    log "=== Session Complete ==="
    printf '%s\n' "${C_DIM}┌─── Summary ───────────────────────────────────────────┐${C_RESET}"
    printf '%s│%s  Tasks completed:  %s%-4s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD_GREEN" "$tasks" "$C_RESET"
    printf '%s│%s  Total loops:      %s%-4s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD" "$loops" "$C_RESET"

    if [[ "$cb" == "OPEN" ]]; then
        printf '%s│%s  Circuit breaker:  %s%s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD_RED" "$cb" "$C_RESET"
    elif [[ "$cb" == "HALF_OPEN" ]]; then
        printf '%s│%s  Circuit breaker:  %s%s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD_YELLOW" "$cb" "$C_RESET"
    else
        printf '%s│%s  Circuit breaker:  %s%s%s\n' "$C_DIM" "$C_RESET" "$C_GREEN" "$cb" "$C_RESET"
    fi

    printf '%s│%s  Exit reason:      %s\n' "$C_DIM" "$C_RESET" "$EXIT_REASON"
    printf '%s│%s  Session log:      %s%s%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "${SESSION_LOG:-unknown}" "$C_RESET"
    printf '%s└───────────────────────────────────────────────────────┘%s\n' "$C_DIM" "$C_RESET"
    printf '%s\n' "${C_DIM}Run \`bnr\` to review completed work.${C_RESET}"
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
