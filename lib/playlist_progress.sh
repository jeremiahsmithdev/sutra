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
# prompt lines show the first 60 chars.

format_progress_item() {
    local line="$1"

    if [[ "$line" == ">"* ]]; then
        local text="${line#>}"
        text="${text#"${text%%[![:space:]]*}"}"
        printf '[prompt] %s' "${text:0:60}"
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
# Read the progress file and return it for prompt injection. Returns empty
# string when no progress file exists (first task, or non-playlist mode).

format_playlist_progress() {
    [[ ! -f "$PROGRESS_FILE" ]] && return
    printf '\n## Playlist Progress\n'
    cat "$PROGRESS_FILE"
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
            printf '%d. [prompt] %s (processed: %s)\n' "$item_num" "${prompt_text:0:80}" "$was_processed"
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
