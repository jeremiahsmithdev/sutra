# invoke_quota.sh — Usage limit handling for Claude API.
#
# After an invocation fails, checks if it's due to hitting the usage limit using claude-usage.
# If so, waits until the 5-hour usage window resets before retrying.
# Handles no-data case (no active sessions) by proceeding anyway.

# ── wait_for_quota ─────────────────────────────────────────────────────────────
#
# After a failure, check if usage limit is hit (100% used). If so, wait for reset.
# Uses claude-usage to check availability and get reset time.
# Returns 0 immediately if usage is available or no data is available.

wait_for_quota() {
    while true; do
        # Check if usage is exhausted (100% used)
        local used_percent
        used_percent=$(claude-usage --5-hour 2>/dev/null | jq -r '.used_percent // 0')

        # If usage is not exhausted, proceed
        if [[ "$used_percent" != "100" ]]; then
            return 0
        fi

        # Usage is exhausted - get reset info
        local reset_at reset_minutes
        reset_at=$(claude-usage --5-hour 2>/dev/null | jq -r '.resets_at // empty')
        reset_minutes=$(claude-usage --5-hour 2>/dev/null | jq -r '.resets_in_minutes // empty')

        # If we can't get usage info (no active sessions), proceed anyway
        # Better to try and fail than hang indefinitely
        if [[ -z "$reset_minutes" ]]; then
            log "WARNING: Could not query usage status via claude-usage (no active sessions), proceeding anyway"
            return 0
        fi

        local wait_seconds=$((reset_minutes * 60))
        local wait_mins=$((reset_minutes))
        local reset_time_human
        reset_time_human=$(format_reset_time "$reset_at")

        # Display prominent usage limit wait message
        printf '%s\n' "${C_BOLD_YELLOW}════════════════════════════════════════════════════════${C_RESET}"
        printf '%s %s%s%s\n' "${C_BOLD_YELLOW}" "⚠️" "  USAGE LIMIT HIT - WAITING FOR 5-HOUR WINDOW RESET" "${C_RESET}"
        printf '%s\n' "${C_BOLD_YELLOW}════════════════════════════════════════════════════════${C_RESET}"
        printf '%s\n' "  Reset time: ${C_BOLD_CYAN}${reset_time_human}${C_RESET}"
        printf '%s\n' "  Wait duration: ${C_BOLD_CYAN}${wait_mins} minutes${C_RESET}"
        printf '%s\n' "${C_DIM}  Sleeping... will resume automatically when usage window resets${C_RESET}"
        printf '%s\n\n' "${C_BOLD_YELLOW}════════════════════════════════════════════════════════${C_RESET}"

        # Wait until reset time, showing progress every 10 minutes for long waits
        local elapsed=0
        local progress_interval=600  # 10 minutes
        while [[ $elapsed -lt $wait_seconds ]]; do
            local sleep_time=$((wait_seconds - elapsed))
            if [[ $sleep_time -gt $progress_interval ]]; then
                sleep $progress_interval
                elapsed=$((elapsed + progress_interval))
                local remaining_mins=$(((wait_seconds - elapsed) / 60))
                printf '%s %s %s %s\n' "${C_DIM}[ralph $(date +%H:%M:%S)]" "${C_YELLOW}" "Still waiting... ${remaining_mins} minutes until usage window resets" "${C_RESET}"
            else
                sleep $sleep_time
                elapsed=$wait_seconds
            fi
        done
    done
}

# ── format_reset_time ─────────────────────────────────────────────────────────
#
# Convert ISO 8601 timestamp to human-readable local time (e.g., "5:45am").
# Returns formatted time string or "unknown" if parsing fails.

format_reset_time() {
    local iso_time="$1"
    [[ -z "$iso_time" ]] && echo "unknown" && return

    # Parse ISO timestamp and convert to local time
    # Handle different date commands (GNU vs BSD/macOS)
    local formatted
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        formatted=$(date -d "$iso_time" +"%-l:%M%P" 2>/dev/null)
    else
        # BSD date (macOS) - manually construct time with am/pm
        local hour minute ampm
        hour=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${iso_time:0:19}" +"%-I" 2>/dev/null)
        minute=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${iso_time:0:19}" +"%M" 2>/dev/null)
        ampm=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${iso_time:0:19}" +"%p" 2>/dev/null | tr '[:upper:]' '[:lower:]')

        # Strip leading zero from hour if present, but keep minutes zero-padded
        hour="${hour#0}"
        formatted="${hour}:${minute}${ampm}"
    fi

    echo "${formatted:-unknown}"
}
