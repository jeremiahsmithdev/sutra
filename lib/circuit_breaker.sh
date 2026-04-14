# circuit_breaker.sh — Three-state circuit breaker to halt stuck loops.
#
#   CLOSED    → normal operation
#   HALF_OPEN → warning: 2 consecutive no-progress loops
#   OPEN      → halted: 3 consecutive no-progress loops (ralph stops)
#
# Progress = bead status changed (closed or open). No progress = still in_progress.

# Stop conditions: max tasks, max loops, or circuit breaker OPEN.
# Returns 0 to continue, 1 to stop.
check_exit_conditions() {
    if [[ "$MAX_TASKS" -gt 0 && "$total_tasks_completed" -ge "$MAX_TASKS" ]]; then
        EXIT_REASON="Max tasks reached ($MAX_TASKS)"
        return 1
    fi

    if [[ "$total_loops" -ge "$MAX_LOOPS" ]]; then
        EXIT_REASON="Max loops reached ($MAX_LOOPS)"
        return 1
    fi

    if [[ "$circuit" == "OPEN" ]]; then
        EXIT_REASON="Circuit breaker OPEN ($no_progress_count no-progress loops)"
        log "ERROR: $EXIT_REASON"
        return 1
    fi

    if cost_limit_exceeded; then
        EXIT_REASON="Cost limit reached (\$${total_cost_usd} >= \$${MAX_COST_USD})"
        log "ERROR: $EXIT_REASON"
        return 1
    fi

    return 0
}

# Update circuit breaker based on bead status after Claude ran.
# "in_progress" means Claude didn't close or release — no progress.
cost_limit_exceeded() {
    [[ "$MAX_COST_USD" == "0" ]] && return 1
    awk "BEGIN {exit (${total_cost_usd:-0} >= $MAX_COST_USD) ? 0 : 1}"
}

update_circuit_breaker() {

    if [[ "$bead_status" == "in_progress" ]]; then
        # No progress — bead unchanged
        no_progress_count=$((no_progress_count + 1))

        if [[ "$circuit" == "CLOSED" && "$no_progress_count" -ge 2 ]]; then
            circuit="HALF_OPEN"
            log "WARNING: Circuit → HALF_OPEN (no progress: $no_progress_count)"
        fi

        if [[ "$circuit" == "HALF_OPEN" && "$no_progress_count" -ge 3 ]]; then
            circuit="OPEN"
            log "WARNING: Circuit → OPEN (no progress: $no_progress_count)"
        fi

    else
        record_progress
    fi
}

# ── record_progress ──────────────────────────────────────────────────────
#
# Reset no-progress counter and recover circuit breaker if needed.
# Called from update_circuit_breaker (bead closed/released) and
# playlist_execute_prompt (prompts always count as progress).

record_progress() {
    no_progress_count=0
    if [[ "$circuit" == "HALF_OPEN" ]]; then
        circuit="CLOSED"
        log "Circuit recovered → CLOSED"
    fi
}
