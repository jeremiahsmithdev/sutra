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
    [[ "${INJECTION_CAPPED:-false}" == "true" ]] && return

    local new_checksum
    new_checksum=$(cksum < "$PLAYLIST")
    if [[ "$new_checksum" == "${_playlist_checksum:-}" ]]; then
        return
    fi

    local old_bead_count
    old_bead_count=$(count_bead_lines)

    backup_playlist
    local expected_content
    expected_content=$(remember_current_line_content)

    reread_playlist_file
    recount_playlist_total
    verify_playlist_position "$expected_content"
    warn_if_branch_directive_changed
    check_injection_limit "$old_bead_count"

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
    local backup=".sutra/playlist-backup-$(date +%s)"
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
    read_playlist_file
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

# ── init_injection_limit ──────────────────────────────────────────────────
#
# Compute the injection cap from config. If MAX_INJECTED_BEADS is set,
# use it directly. Otherwise derive from bead count and INJECTION_RATIO.

init_injection_limit() {
    injected_bead_count="${injected_bead_count:-0}"
    INJECTION_CAPPED="${INJECTION_CAPPED:-false}"

    if [[ "$MAX_INJECTED_BEADS" -gt 0 ]]; then
        injection_limit=$MAX_INJECTED_BEADS
    else
        local bead_count
        bead_count=$(count_bead_lines)
        # floor(beads * ratio), minimum 5
        injection_limit=$(awk "BEGIN{v=int($bead_count * $INJECTION_RATIO); print (v<5)?5:v}")
    fi
}

# ── count_bead_lines ──────────────────────────────────────────────────────
#
# Count non-prompt actionable lines (bead IDs) in PLAYLIST_LINES.

count_bead_lines() {
    local count=0
    for line in "${PLAYLIST_LINES[@]}"; do
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* || "$trimmed" == ">"* ]] && continue
        count=$((count + 1))
    done
    echo "$count"
}

# ── check_injection_limit ─────────────────────────────────────────────────
#
# After reload, count new bead lines and check against the cap.

check_injection_limit() {
    local old_bead_count="$1"
    local new_bead_count
    new_bead_count=$(count_bead_lines)
    local delta=$((new_bead_count - old_bead_count))

    [[ $delta -le 0 ]] && return

    injected_bead_count=$((injected_bead_count + delta))

    if [[ $injected_bead_count -ge $injection_limit ]]; then
        INJECTION_CAPPED=true
        log "Injection limit reached (${C_BOLD_YELLOW}$injected_bead_count/$injection_limit${C_RESET}). Self-healing disabled for remainder of run."
    fi
}
