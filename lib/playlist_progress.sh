# playlist_progress.sh — Playlist progress tracking and reporting.
#
# playlist_write_progress(): human-readable snapshot after each task.
# playlist_report_data(): text summary for the completion report prompt.
# playlist_processed(): count of actionable lines processed so far.

PROGRESS_FILE=".ralph/playlist-progress.md"

# ── playlist_write_progress ───────────────────────────────────────────────

playlist_write_progress() {
    [[ -z "${PLAYLIST:-}" ]] && return
    [[ -z "${playlist_total:-}" ]] && return

    local total=${#PLAYLIST_LINES[@]}
    local completed=0 remaining=0
    local in_progress_line=""
    local -a completed_items=() remaining_items=()
    local idx=0
    # _playlist_pending_line is set by playlist_next() and not yet committed —
    # it identifies the task currently being executed.
    local pending="${_playlist_pending_line:-0}"

    while [[ $idx -lt $total ]]; do
        local raw="${PLAYLIST_LINES[$idx]}"
        local trimmed="${raw#"${raw%%[![:space:]]*}"}"
        idx=$((idx + 1))

        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        local item
        item=$(format_progress_item "$trimmed")

        if [[ $idx -le ${playlist_line:-0} ]]; then
            completed=$((completed + 1))
            completed_items+=("$item")
        elif [[ $pending -gt 0 && $idx -eq $pending ]]; then
            in_progress_line="$item"
        else
            remaining=$((remaining + 1))
            remaining_items+=("$item")
        fi
    done

    {
        printf '# Playlist Progress: %s\n' "$(basename "$PLAYLIST")"
        printf 'Updated: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf '## Status: %d/%d items completed\n\n' "$completed" "$playlist_total"

        printf '## In Progress\n'
        if [[ -n "$in_progress_line" ]]; then
            printf '* %s\n' "$in_progress_line"
        else
            printf '(none)\n'
        fi

        printf '\n## Completed\n'
        if [[ ${#completed_items[@]} -gt 0 ]]; then
            for item in "${completed_items[@]}"; do printf '* %s\n' "$item"; done
        else
            printf '(none yet)\n'
        fi

        printf '\n## Remaining\n'
        if [[ ${#remaining_items[@]} -gt 0 ]]; then
            for item in "${remaining_items[@]}"; do printf '* %s\n' "$item"; done
        else
            printf '(none)\n'
        fi
    } > "$PROGRESS_FILE"
}

# ── format_progress_item ──────────────────────────────────────────────────
#
# Format a playlist line for the progress file. Bead lines get title lookup;
# prompt lines render in full so subsequent tasks see the complete directive
# when this file is injected as PLAYLIST_PROGRESS context.

format_progress_item() {
    local line="$1"

    if [[ "$line" == ">"* ]]; then
        local text="${line#>}"
        text="${text#"${text%%[![:space:]]*}"}"
        printf '[prompt] %s' "$text"
    else
        local id="${line%% @*}"
        local title
        title=$(get_bead_title "$id" 2>/dev/null)
        printf '[bead] %s — %s' "$id" "${title:-(unknown)}"
    fi
}

# ── get_bead_title ────────────────────────────────────────────────────────

get_bead_title() {
    br show "$1" --json 2>/dev/null | jq -r '.[0].title // ""'
}

# ── format_playlist_progress ──────────────────────────────────────────────
#
# Read the progress file and return a prompt-optimised excerpt.
# Returns empty string when no progress file exists.
#
# Argument: include_in_progress (default: true)
#   true  — keep '## In Progress' section (Type A bead prompts use this as
#           an orientation cue: "you are working on bead X").
#   false — drop '## In Progress' entirely (Type B injection / @opus prompts:
#           the task text is already inline in '## Task' so the duplicate
#           adds nothing).
#
# Token-saving rules applied here (playlist_write_progress is unchanged):
#   - 0 completed: single "Position: 1/N · In Progress: …" line.
#   - ≥1 completed: '## Completed' is replaced by a one-line '## Recent work'
#     reference to git log (PLAYLIST_PROGRESS_LOOKBACK=0, default). Setting
#     LOOKBACK to N>0 shows the last N entries verbatim.
#     '## Remaining' is capped at PLAYLIST_PROGRESS_LOOKAHEAD entries with
#     a "…plus N more" tail.
# The full progress file at PROGRESS_FILE is always written by
# playlist_write_progress for monitor/debug tooling.

format_playlist_progress() {
    local include_in_progress="${1:-true}"
    [[ ! -f "$PROGRESS_FILE" ]] && return

    # Parse completed/total from the Status line
    local status_line completed=0 total=0
    status_line=$(grep -m1 '^## Status:' "$PROGRESS_FILE" || true)
    [[ "$status_line" =~ ([0-9]+)/([0-9]+) ]] \
        && completed="${BASH_REMATCH[1]}" total="${BASH_REMATCH[2]}"

    printf '\n## Playlist Progress\n'

    if [[ $completed -eq 0 ]]; then
        # Compact format: no completed list, no remaining noise.
        printf 'Position: 1/%d' "$total"
        if [[ "$include_in_progress" == "true" ]]; then
            local in_progress
            in_progress=$(awk '/^## In Progress/{f=1;next} f && /^\* /{sub(/^\* /,""); print; exit}' "$PROGRESS_FILE")
            [[ -n "$in_progress" ]] && printf ' · In Progress: %s' "$in_progress"
        fi
        printf '\n'
        return
    fi

    # Count total completed and remaining for summary lines.
    local total_completed total_remaining
    total_completed=$(awk '/^## Completed/{f=1;next} /^## /{f=0} f && /^\* /{c++} END{print c+0}' "$PROGRESS_FILE")
    total_remaining=$(awk '/^## Remaining/{f=1;next} f && /^\* /{c++} END{print c+0}' "$PROGRESS_FILE")

    local lookahead="${PLAYLIST_PROGRESS_LOOKAHEAD:-3}"
    local lookback="${PLAYLIST_PROGRESS_LOOKBACK:-0}"
    local section="" completed_shown=0 remaining_shown=0
    while IFS= read -r line; do
        case "$line" in
            "# Playlist Progress:"*|"Updated:"*) continue ;;
            "## In Progress")
                section="in_progress"
                [[ "$include_in_progress" == "true" ]] && printf '%s\n' "$line"
                ;;
            "## Completed")
                section="completed"
                if [[ $lookback -eq 0 ]]; then
                    printf '## Recent work\nLast %d bead(s) closed — see `git log --oneline -20` for full history.\n' "$total_completed"
                else
                    printf '%s\n' "$line"
                fi
                ;;
            "## Remaining")
                section="remaining"
                printf '%s\n' "$line"
                ;;
            *)
                if [[ "$section" == "in_progress" ]]; then
                    [[ "$include_in_progress" == "true" ]] && printf '%s\n' "$line"
                elif [[ "$section" == "completed" && "$line" == \** ]]; then
                    completed_shown=$((completed_shown + 1))
                    if [[ $lookback -gt 0 && $completed_shown -gt $((total_completed - lookback)) ]]; then
                        printf '%s\n' "$line"
                    fi
                    # LOOKBACK=0: entries replaced by '## Recent work' summary above.
                elif [[ "$section" == "remaining" && "$line" == \** ]]; then
                    remaining_shown=$((remaining_shown + 1))
                    if [[ $remaining_shown -le $lookahead ]]; then
                        printf '%s\n' "$line"
                    elif [[ $remaining_shown -eq $((lookahead + 1)) ]]; then
                        printf '…plus %d more\n' $((total_remaining - lookahead))
                    fi
                    # Items beyond the first overflow line are silently dropped
                else
                    printf '%s\n' "$line"
                fi
                ;;
        esac
    done < "$PROGRESS_FILE"
}

# ── playlist_report_data ──────────────────────────────────────────────────
#
# Text summary of all playlist lines and their current status.
# Consumed by the completion report prompt to give Claude full context.

playlist_report_data() {
    local total=${#PLAYLIST_LINES[@]}
    local idx=0 item_num=0

    while [[ $idx -lt $total ]]; do
        local raw="${PLAYLIST_LINES[$idx]}"
        idx=$((idx + 1))
        local trimmed="${raw#"${raw%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        item_num=$((item_num + 1))
        local was_processed="no"
        [[ $idx -le $playlist_line ]] && was_processed="yes"

        if [[ "$trimmed" == ">"* ]]; then
            local prompt_text="${trimmed#>}"
            prompt_text="${prompt_text#"${prompt_text%%[![:space:]]*}"}"
            printf '%d. [prompt] %s (processed: %s)\n' "$item_num" "$prompt_text" "$was_processed"
        else
            local bead_status
            bead_status=$(get_bead_status "$trimmed")
            printf '%d. [bead] %s (status: %s, processed: %s)\n' "$item_num" "$trimmed" "$bead_status" "$was_processed"
        fi
    done
}

# ── playlist_processed ─────────────────────────────────────────────────────
#
# Return the number of actionable lines processed so far.

playlist_processed() {
    local count=0
    local i=0
    while [[ $i -lt $playlist_line ]]; do
        local raw="${PLAYLIST_LINES[$i]}"
        local trimmed="${raw#"${raw%%[![:space:]]*}"}"
        [[ -n "$trimmed" && "$trimmed" != \#* ]] && count=$((count + 1))
        i=$((i + 1))
    done
    echo "$count"
}
