# cleanup.sh — Exit trap that prints a session summary and removes temp files.
#
# Registered via `trap cleanup EXIT` in the main ralph script.
# Runs on any exit — normal completion, errors, or Ctrl-C.

cleanup() {
    local tasks="${total_tasks_completed:-0}"
    local loops="${total_loops:-0}"
    local cb="${circuit:-CLOSED}"

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
    printf '%s└───────────────────────────────────────────────────────┘%s\n' "$C_DIM" "$C_RESET"
    printf '%s\n' "${C_DIM}Run \`bnr\` to review completed work.${C_RESET}"
}
