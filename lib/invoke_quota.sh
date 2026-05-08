# invoke_quota.sh — Usage limit handling for Claude API.
#
# After an invocation fails, checks if it's due to hitting the usage limit using claude-usage.
# If so, waits until the 5-hour usage window resets before retrying.
# Handles no-data case (no active sessions) by proceeding anyway.
#
# Detects two distinct quota dimensions Anthropic exposes:
#   * five_hour.utilization  — percentage 0-100, resets every 5h.
#   * extra_usage            — paid overflow tier; utilization is a *fraction* 0-1
#                              (different unit from five_hour). Exhausting this
#                              also blocks invocation and surfaces as "You're
#                              out of extra usage" with a five-hour reset time.
# Either dimension being capped triggers the same wait on five_hour.resets_at,
# since that is the next moment anything usable returns.

# ── wait_for_quota ─────────────────────────────────────────────────────────────
#
# After a failure, check if usage limit is hit. If so, wait for the 5-hour
# window reset. Returns 0 immediately if usage is available or no data is
# available (better to try and fail than hang).

wait_for_quota() {
    while true; do
        local raw
        raw=$(claude-usage --raw 2>/dev/null)
        if [[ -z "$raw" ]]; then
            log "WARNING: Could not query usage status via claude-usage, proceeding anyway"
            return 0
        fi

        local five_hour_pct extra_enabled extra_util
        five_hour_pct=$(printf '%s' "$raw" | jq -r '.five_hour.utilization // 0')
        extra_enabled=$(printf '%s' "$raw" | jq -r '.extra_usage.is_enabled // false')
        extra_util=$(printf '%s' "$raw" | jq -r '.extra_usage.utilization // 0')

        local capped
        capped=$(awk \
            -v fh="$five_hour_pct" \
            -v ee="$extra_enabled" \
            -v eu="$extra_util" \
            'BEGIN { print (fh >= 100 || (ee == "true" && eu >= 1)) ? "1" : "0" }')

        if [[ "$capped" != "1" ]]; then
            return 0
        fi

        # Cap hit — wait for the 5-hour reset (extra_usage has no separate reset).
        # Pull reset_at + resets_in_minutes from --5-hour because that variant
        # already computes the elapsed-minutes value cross-platform.
        local five_hour_block reset_at reset_minutes
        five_hour_block=$(claude-usage --5-hour 2>/dev/null)
        reset_at=$(printf '%s' "$five_hour_block" | jq -r '.resets_at // empty')
        reset_minutes=$(printf '%s' "$five_hour_block" | jq -r '.resets_in_minutes // empty')

        if [[ -z "$reset_minutes" ]]; then
            log "WARNING: Could not compute reset time, proceeding anyway"
            return 0
        fi

        if [[ "$extra_enabled" == "true" ]] \
            && awk -v eu="$extra_util" 'BEGIN { exit (eu >= 1) ? 0 : 1 }'; then
            log "Quota cap: extra_usage exhausted (utilization=${extra_util})"
        else
            log "Quota cap: 5-hour usage at ${five_hour_pct}%"
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
        # BSD date (macOS) - interpret input as UTC and convert to local time
        local hour minute ampm epoch
        # Parse ISO time as UTC to get correct epoch
        epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${iso_time:0:19}" +"%s" 2>/dev/null)
        # Convert epoch to local time with am/pm
        hour=$(date -r "$epoch" +"%-I" 2>/dev/null)
        minute=$(date -r "$epoch" +"%M" 2>/dev/null)
        ampm=$(date -r "$epoch" +"%p" 2>/dev/null | tr '[:upper:]' '[:lower:]')

        # Strip leading zero from hour if present, but keep minutes zero-padded
        hour="${hour#0}"
        formatted="${hour}:${minute}${ampm}"
    fi

    echo "${formatted:-unknown}"
}
