# playlist_reload.sh — Re-read the playlist file after prompt execution.
#
# When a > prompt invocation modifies the playlist file (e.g. injects fix
# beads), this function picks up the changes. Called from
# playlist_execute_prompt() after invoke_claude returns successfully.

# ── playlist_reload ──────────────────────────────────────────────────────
#
# Re-read PLAYLIST if the file has changed since last read. Backs up the
# file before reloading, verifies current position by content match, and
# recounts actionable lines. Silent no-op if the file is unchanged.

playlist_reload() {
    [[ ! -f "$PLAYLIST" ]] && return

    local new_checksum
    new_checksum=$(cksum < "$PLAYLIST")
    if [[ "$new_checksum" == "${_playlist_checksum:-}" ]]; then
        return
    fi

    backup_playlist
    local expected_content
    expected_content=$(remember_current_line_content)

    reread_playlist_file
    recount_playlist_total
    verify_playlist_position "$expected_content"
    warn_if_branch_directive_changed

    _playlist_checksum="$new_checksum"
}

# ── init_playlist_checksum ────────────────────────────────────────────────
#
# Capture initial checksum after playlist_init reads the file.
# Called from playlist_init().

init_playlist_checksum() {
    _playlist_checksum=$(cksum < "$PLAYLIST")
}

# ── backup_playlist ───────────────────────────────────────────────────────

backup_playlist() {
    local backup=".ralph/playlist-backup-$(date +%s)"
    cp "$PLAYLIST" "$backup"
    _playlist_backup_path="$backup"
}

# ── remember_current_line_content ─────────────────────────────────────────
#
# Return the content of the line at _playlist_pending_line (the line just
# executed) for post-reload position verification.

remember_current_line_content() {
    local idx=$(( ${_playlist_pending_line:-0} - 1 ))
    if [[ $idx -ge 0 && $idx -lt ${#PLAYLIST_LINES[@]} ]]; then
        echo "${PLAYLIST_LINES[$idx]}"
    fi
}

# ── reread_playlist_file ──────────────────────────────────────────────────

reread_playlist_file() {
    local old_count=${#PLAYLIST_LINES[@]}
    PLAYLIST_LINES=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        PLAYLIST_LINES+=("$line")
    done < "$PLAYLIST"

    local new_count=${#PLAYLIST_LINES[@]}
    local delta=$((new_count - old_count))

    if [[ $delta -ne 0 ]]; then
        log "Playlist reloaded: ${C_BOLD}$delta new lines${C_RESET} (backup: ${_playlist_backup_path:-unknown})"
    else
        log "Playlist reloaded: content changed (backup: ${_playlist_backup_path:-unknown})"
    fi
}

# ── verify_playlist_position ──────────────────────────────────────────────
#
# After reload, check that _playlist_pending_line still points to the
# expected content. If lines were inserted above the current position,
# scan forward to relocate.

verify_playlist_position() {
    local expected="$1"
    [[ -z "$expected" ]] && return

    local idx=$(( ${_playlist_pending_line:-0} - 1 ))
    [[ $idx -lt 0 ]] && return

    if [[ $idx -lt ${#PLAYLIST_LINES[@]} && "${PLAYLIST_LINES[$idx]}" == "$expected" ]]; then
        return
    fi

    log "WARNING: Playlist content shifted at line $((_playlist_pending_line)). Scanning..."
    local i
    for (( i = idx; i < ${#PLAYLIST_LINES[@]}; i++ )); do
        if [[ "${PLAYLIST_LINES[$i]}" == "$expected" ]]; then
            _playlist_pending_line=$((i + 1))
            log "WARNING: Adjusted position to line $((i + 1))"
            return
        fi
    done
    log "WARNING: Could not relocate previous position. Continuing from line $((_playlist_pending_line))."
}

# ── warn_if_branch_directive_changed ──────────────────────────────────────
#
# If the reloaded file has a different "# branch:" directive than what
# was resolved at startup (ralph-0h1.20), log a warning. Branch is fixed
# for the session to prevent mid-run branch switches.

warn_if_branch_directive_changed() {
    [[ -z "${PLAYLIST_BRANCH:-}" ]] && return
    local new_directive
    new_directive=$(head -5 "$PLAYLIST" | sed -n 's/^#[[:space:]]*branch:[[:space:]]*//p' | head -1)
    if [[ -n "$new_directive" && "$new_directive" != "$PLAYLIST_BRANCH" ]]; then
        log "WARNING: Playlist reload: # branch: directive changed to '$new_directive', ignoring — branch is fixed for the session"
    fi
}
