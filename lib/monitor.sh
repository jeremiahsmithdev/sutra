# monitor.sh — Live dashboard that runs alongside a ralph session.
#
# Polls .ralph_state and beads every second, renders a colored
# status display. Launched via `ralph --monitor` in a separate terminal.
#
# Uses double-buffered rendering: the entire frame is built into a
# variable, then flushed to stdout in a single printf. Combined with
# cursor-home (no screen clear), this eliminates visible flicker.

run_remote_monitor() {
    # shellcheck source=/dev/null
    source .ralph_remote

    if [[ -z "$REMOTE_HOST" || -z "$REMOTE_DIR" ]]; then
        log "ERROR: Invalid .ralph_remote file"
        return 1
    fi

    # Ensure remote has latest ralph (fast rsync, no-op if unchanged)
    sync_ralph

    log "Monitoring remote ralph on ${C_BOLD_CYAN}${REMOTE_HOST}:${REMOTE_DIR}${C_RESET}"
    ssh -t "$REMOTE_HOST" "cd '$REMOTE_DIR' && ~/.ralph/ralph --monitor"
}

run_monitor() {
    # Check for remote ralph session
    if [[ -f ".ralph_remote" ]]; then
        run_remote_monitor
        return $?
    fi

    if [[ ! -d ".beads" ]]; then
        log "ERROR: No .beads/ in $(pwd). Run from a beads-enabled project."
        exit 1
    fi

    # Initial clear + hide cursor
    printf '\033[2J\033[H\033[?25h'
    printf '\033[?25l'
    trap 'printf "\033[?25h\033[J"; exit 0' INT   # restore cursor + clear below on exit

    while true; do
        render_dashboard
        sleep 1
    done
}

render_dashboard() {
    local state_file="${STATE_FILE:-.ralph_state}"
    local buf=""
    local W=56   # inner width of the box

    # ── Read state ──────────────────────────────────────────────────────
    local circuit="—" loops="0" max="—" tasks="0" cur="" start="" mdl="—" status

    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file"
        loops="${total_loops:-0}"
        tasks="${total_tasks_completed:-0}"
        max="${max_loops:-—}"
        cur="${current_task:-}"
        start="${session_start:-}"
        mdl="${model:-haiku}"
    fi

    # Is ralph running?
    if pgrep -f "ralph.*--dangerously-skip-permissions" &>/dev/null || \
       pgrep -f "^bash.*ralph$" &>/dev/null; then
        status="${C_BOLD_GREEN}RUNNING${C_RESET}"
    elif [[ -f "$state_file" ]]; then
        status="${C_DIM}STOPPED${C_RESET}"
    else
        status="${C_DIM}NO SESSION${C_RESET}"
    fi

    # ── Current task details ────────────────────────────────────────────
    local cur_title="—" cur_branch="—"
    if [[ -n "$cur" ]]; then
        cur_title=$(br show "$cur" --json 2>/dev/null \
            | jq -r '.[0].title // "—"' 2>/dev/null) || cur_title="—"
        cur_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || cur_branch="—"
    fi

    # ── Completed tasks this session ────────────────────────────────────
    local completed_json="[]"
    if [[ -n "$start" ]]; then
        completed_json=$(br list --status=closed --all --json 2>/dev/null \
            | jq --arg s "$start" '[.issues[] | select(.closed_at >= $s)]' 2>/dev/null) || completed_json="[]"
    fi
    local completed_count
    completed_count=$(echo "$completed_json" | jq 'length' 2>/dev/null) || completed_count=0

    # ── Queue stats ─────────────────────────────────────────────────────
    local ready_count blocked_count
    ready_count=$(br ready --limit 999 --json 2>/dev/null | jq 'length' 2>/dev/null) || ready_count=0
    blocked_count=$(br blocked --limit 999 --json 2>/dev/null | jq 'length' 2>/dev/null) || blocked_count=0

    # ── Circuit breaker color ───────────────────────────────────────────
    local cb_display
    case "${circuit:-CLOSED}" in
        CLOSED)    cb_display="${C_GREEN}CLOSED${C_RESET}" ;;
        HALF_OPEN) cb_display="${C_YELLOW}HALF_OPEN${C_RESET}" ;;
        OPEN)      cb_display="${C_BOLD_RED}OPEN${C_RESET}" ;;
        *)         cb_display="${C_DIM}${circuit}${C_RESET}" ;;
    esac

    # ── Build frame into buffer ─────────────────────────────────────────
    # Each line is appended to $buf. The entire frame is flushed at once.

    buf+=$(printf '%s╔══ RALPH MONITOR ═══════════════════════════════════════╗%s' "$C_BOLD_CYAN" "$C_RESET")
    buf+=$'\n'
    buf+=$(printf '%s║%s  Status:     %-43b%s║%s' "$C_CYAN" "$C_RESET" "$status" "$C_CYAN" "$C_RESET")
    buf+=$'\n'
    buf+=$(printf '%s║%s  Model:      %s%-35s%s   %s║%s' "$C_CYAN" "$C_RESET" "$C_BOLD" "$mdl" "$C_RESET" "$C_CYAN" "$C_RESET")
    buf+=$'\n'
    buf+=$(printf '%s║%s  Circuit:    %-43b%s║%s' "$C_CYAN" "$C_RESET" "$cb_display" "$C_CYAN" "$C_RESET")
    buf+=$'\n'
    buf+=$(printf '%s║%s  Progress:   %s%-3s%s/%s loops · %s%s%s tasks completed        %s║%s' \
        "$C_CYAN" "$C_RESET" "$C_BOLD" "$loops" "$C_RESET" "$max" "$C_BOLD_GREEN" "$tasks" "$C_RESET" "$C_CYAN" "$C_RESET")
    buf+=$'\n'
    buf+=$(printf '%s╠════════════════════════════════════════════════════════╣%s' "$C_CYAN" "$C_RESET")
    buf+=$'\n'

    if [[ -n "$cur" ]]; then
        buf+=$(printf '%s║%s  Current:    %s%-35s%s   %s║%s' "$C_CYAN" "$C_RESET" "$C_BOLD_CYAN" "$cur" "$C_RESET" "$C_CYAN" "$C_RESET")
        buf+=$'\n'
        buf+=$(printf '%s║%s  Title:      %-39s%s║%s' "$C_CYAN" "$C_RESET" "$cur_title" "$C_CYAN" "$C_RESET")
        buf+=$'\n'
        buf+=$(printf '%s║%s  Branch:     %s%-35s%s   %s║%s' "$C_CYAN" "$C_RESET" "$C_DIM" "$cur_branch" "$C_RESET" "$C_CYAN" "$C_RESET")
        buf+=$'\n'
    else
        buf+=$(printf '%s║%s  Current:    %s%-39s%s%s║%s' "$C_CYAN" "$C_RESET" "$C_DIM" "(idle)" "$C_RESET" "$C_CYAN" "$C_RESET")
        buf+=$'\n'
    fi

    buf+=$(printf '%s╠════════════════════════════════════════════════════════╣%s' "$C_CYAN" "$C_RESET")
    buf+=$'\n'
    buf+=$(printf '%s║%s  Completed this session: %-28s %s║%s' "$C_CYAN" "$C_RESET" "" "$C_CYAN" "$C_RESET")
    buf+=$'\n'

    local completed_lines
    completed_lines=$(echo "$completed_json" | jq -r '.[] | "  \(.id)  \(.title)"' 2>/dev/null | head -10) || completed_lines=""

    if [[ -n "$completed_lines" ]]; then
        while IFS= read -r line; do
            buf+=$(printf '%s║%s    %s✓%s %-47s %s║%s' "$C_CYAN" "$C_RESET" "$C_GREEN" "$C_RESET" "$line" "$C_CYAN" "$C_RESET")
            buf+=$'\n'
        done <<< "$completed_lines"
    else
        buf+=$(printf '%s║%s    %s%-47s%s  %s║%s' "$C_CYAN" "$C_RESET" "$C_DIM" "(none yet)" "$C_RESET" "$C_CYAN" "$C_RESET")
        buf+=$'\n'
    fi

    buf+=$(printf '%s╠════════════════════════════════════════════════════════╣%s' "$C_CYAN" "$C_RESET")
    buf+=$'\n'
    buf+=$(printf '%s║%s  Queue:  %s%s%s ready · %s%s%s blocked                      %s║%s' \
        "$C_CYAN" "$C_RESET" "$C_BOLD" "$ready_count" "$C_RESET" "$C_YELLOW" "$blocked_count" "$C_RESET" "$C_CYAN" "$C_RESET")
    buf+=$'\n'
    buf+=$(printf '%s╚════════════════════════════════════════════════════════╝%s' "$C_CYAN" "$C_RESET")
    buf+=$'\n'
    buf+=$(printf '  %sRefreshing every 1s · Ctrl+C to exit%s' "$C_DIM" "$C_RESET")

    # ── Atomic flush ────────────────────────────────────────────────────
    # Cursor home (no clear) + write buffer + clear remnants.
    # \033[K on each line clears to end-of-line (fixes ANSI padding artifacts).
    # \033[J after the frame clears any leftover lines from a taller previous render.
    printf '\033[H%s\033[J' "${buf//$'\n'/$'\033[K\n'}"
}
