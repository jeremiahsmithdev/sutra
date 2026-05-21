# monitor_render.sh — Dashboard frame rendering.
#
# render_dashboard() is the entry point. It gathers state, builds each
# section, and flushes the whole frame atomically. Section functions
# print newline-terminated lines to stdout; the orchestrator concatenates
# them with explicit $'\n' separators (command substitution strips the
# trailing newline from each $(...)).
#
# State is held in module-scoped globals set by read_dashboard_state()
# and fetch_dashboard_data() — simpler than passing 12 args to every
# render function.

render_dashboard() {
    read_dashboard_state
    fetch_dashboard_data

    local buf
    buf="$(render_header_section)"$'\n'
    buf+="$(render_current_task_section)"$'\n'
    buf+="$(render_completed_section)"$'\n'
    buf+="$(render_queue_section)"

    flush_dashboard "$buf"
}

# ── read_dashboard_state ──────────────────────────────────────────────────
#
# Source .sutra/state and detect whether sutra is currently running.
# Sets module-scoped globals consumed by the render_*_section functions.

read_dashboard_state() {
    local state_file="${STATE_FILE:-.sutra/state}"
    DB_circuit="—"; DB_loops="0"; DB_max="—"; DB_tasks="0"
    DB_cur=""; DB_start=""; DB_mdl="—"

    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file"
        DB_circuit="${circuit:-CLOSED}"
        DB_loops="${total_loops:-0}"
        DB_tasks="${total_tasks_completed:-0}"
        DB_max="${max_loops:-—}"
        DB_cur="${current_task:-}"
        DB_start="${session_start:-}"
        DB_mdl="${model:-haiku}"
    fi

    DB_pl_file="${playlist_file:-}"
    DB_pl_line="${playlist_line:-0}"
    DB_status=$(detect_sutra_status "$state_file")
}

# Determine whether sutra is running, stopped, or has no session.
detect_sutra_status() {
    local state_file="$1"
    if pgrep -f "sutra.*--dangerously-skip-permissions" &>/dev/null \
        || pgrep -f "^bash.*sutra$" &>/dev/null; then
        echo "${C_BOLD_GREEN}RUNNING${C_RESET}"
    elif [[ -f "$state_file" ]]; then
        echo "${C_DIM}STOPPED${C_RESET}"
    else
        echo "${C_DIM}NO SESSION${C_RESET}"
    fi
}

# ── fetch_dashboard_data ──────────────────────────────────────────────────
#
# Query beads + git for the current task, completed tasks, and queue stats.

fetch_dashboard_data() {
    DB_cur_title="—"; DB_cur_branch="—"
    if [[ -n "$DB_cur" ]]; then
        DB_cur_title=$(get_bead_field "$DB_cur" title)
        [[ -z "$DB_cur_title" ]] && DB_cur_title="—"
        DB_cur_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || DB_cur_branch="—"
    fi

    DB_completed_json="[]"
    if [[ -n "$DB_start" ]]; then
        DB_completed_json=$(get_closed_tasks_since "$DB_start") || DB_completed_json="[]"
    fi

    DB_ready=$(br ready --limit 999 --json 2>/dev/null | jq 'length' 2>/dev/null) || DB_ready=0
    DB_blocked=$(br blocked --limit 999 --json 2>/dev/null | jq 'length' 2>/dev/null) || DB_blocked=0
}

# ── render_header_section ─────────────────────────────────────────────────
#
# Top box line, status, optional playlist line, model, circuit, progress.

render_header_section() {
    local cb_display
    cb_display=$(format_circuit_breaker_display "$DB_circuit")

    printf '%s╔══ SUTRA MONITOR ═══════════════════════════════════════╗%s\n' "$C_BOLD_CYAN" "$C_RESET"
    printf '%s║%s  Status:     %-43b%s║%s\n' "$C_CYAN" "$C_RESET" "$DB_status" "$C_CYAN" "$C_RESET"
    if [[ -n "$DB_pl_file" ]]; then
        local pl_basename="${DB_pl_file##*/}"
        printf '%s║%s  Playlist:   %s%-27s%s [line %s]  %s║%s\n' \
            "$C_CYAN" "$C_RESET" "$C_BOLD_MAGENTA" "$pl_basename" "$C_RESET" "$DB_pl_line" "$C_CYAN" "$C_RESET"
    fi
    printf '%s║%s  Model:      %s%-35s%s   %s║%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "$DB_mdl" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf '%s║%s  Circuit:    %-43b%s║%s\n' "$C_CYAN" "$C_RESET" "$cb_display" "$C_CYAN" "$C_RESET"
    printf '%s║%s  Progress:   %s%-3s%s/%s loops · %s%s%s tasks completed        %s║%s' \
        "$C_CYAN" "$C_RESET" "$C_BOLD" "$DB_loops" "$C_RESET" "$DB_max" "$C_BOLD_GREEN" "$DB_tasks" "$C_RESET" "$C_CYAN" "$C_RESET"
}

# Map circuit breaker state to its colored display string.
format_circuit_breaker_display() {
    case "$1" in
        CLOSED)    echo "${C_GREEN}CLOSED${C_RESET}" ;;
        HALF_OPEN) echo "${C_YELLOW}HALF_OPEN${C_RESET}" ;;
        OPEN)      echo "${C_BOLD_RED}OPEN${C_RESET}" ;;
        *)         echo "${C_DIM}$1${C_RESET}" ;;
    esac
}

# ── render_current_task_section ───────────────────────────────────────────
#
# Divider + current task ID/title/branch, or an (idle) line when nothing
# is in progress.

render_current_task_section() {
    printf '%s╠════════════════════════════════════════════════════════╣%s\n' "$C_CYAN" "$C_RESET"
    if [[ -n "$DB_cur" ]]; then
        printf '%s║%s  Current:    %s%-35s%s   %s║%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD_CYAN" "$DB_cur" "$C_RESET" "$C_CYAN" "$C_RESET"
        printf '%s║%s  Title:      %-39s%s║%s\n' "$C_CYAN" "$C_RESET" "$DB_cur_title" "$C_CYAN" "$C_RESET"
        printf '%s║%s  Branch:     %s%-35s%s   %s║%s' "$C_CYAN" "$C_RESET" "$C_DIM" "$DB_cur_branch" "$C_RESET" "$C_CYAN" "$C_RESET"
    else
        printf '%s║%s  Current:    %s%-39s%s%s║%s' "$C_CYAN" "$C_RESET" "$C_DIM" "(idle)" "$C_RESET" "$C_CYAN" "$C_RESET"
    fi
}

# ── render_completed_section ──────────────────────────────────────────────
#
# Divider + "Completed this session" header + up to 10 completed task lines.

render_completed_section() {
    printf '%s╠════════════════════════════════════════════════════════╣%s\n' "$C_CYAN" "$C_RESET"
    printf '%s║%s  Completed this session: %-28s %s║%s\n' "$C_CYAN" "$C_RESET" "" "$C_CYAN" "$C_RESET"

    local lines
    lines=$(echo "$DB_completed_json" | jq -r '.[] | "  \(.id)  \(.title)"' 2>/dev/null | head -10)

    if [[ -n "$lines" ]]; then
        local line first=true
        while IFS= read -r line; do
            [[ "$first" == false ]] && printf '\n'
            printf '%s║%s    %s✓%s %-47s %s║%s' "$C_CYAN" "$C_RESET" "$C_GREEN" "$C_RESET" "$line" "$C_CYAN" "$C_RESET"
            first=false
        done <<< "$lines"
    else
        printf '%s║%s    %s%-47s%s  %s║%s' "$C_CYAN" "$C_RESET" "$C_DIM" "(none yet)" "$C_RESET" "$C_CYAN" "$C_RESET"
    fi
}

# ── render_queue_section ──────────────────────────────────────────────────
#
# Divider + queue stats + bottom box line + refresh hint.

render_queue_section() {
    printf '%s╠════════════════════════════════════════════════════════╣%s\n' "$C_CYAN" "$C_RESET"
    printf '%s║%s  Queue:  %s%s%s ready · %s%s%s blocked                      %s║%s\n' \
        "$C_CYAN" "$C_RESET" "$C_BOLD" "$DB_ready" "$C_RESET" "$C_YELLOW" "$DB_blocked" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf '%s╚════════════════════════════════════════════════════════╝%s\n' "$C_CYAN" "$C_RESET"
    printf '  %sRefreshing every 1s · Ctrl+C to exit%s' "$C_DIM" "$C_RESET"
}

# ── flush_dashboard ───────────────────────────────────────────────────────
#
# Atomic frame flush: cursor-home (no clear) + write buffer + clear below.
# \033[K on each line clears to end-of-line (fixes ANSI padding artifacts).
# \033[J after the frame clears any leftover lines from a taller prior render.

flush_dashboard() {
    printf '\033[H%s\033[J' "${1//$'\n'/$'\033[K\n'}"
}
