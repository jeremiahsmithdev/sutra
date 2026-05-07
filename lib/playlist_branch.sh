# playlist_branch.sh — Resolve the single branch for a playlist session.
#
# In playlist mode, all work lands on one branch. Precedence:
# 1. --playlist-branch CLI flag  2. # branch: directive  3. filename-derived.
# Called from initialize() before ensure_correct_branch().

# ── playlist_resolve_branch ────────────────────────────────────────────────
#
# Resolve the single branch for this playlist session. Precedence:
# 1. --playlist-branch CLI flag  2. # branch: directive  3. filename-derived

playlist_resolve_branch() {
    [[ -z "$PLAYLIST" ]] && return
    local source

    if [[ -n "$PLAYLIST_BRANCH_CLI" ]]; then
        PLAYLIST_BRANCH="$PLAYLIST_BRANCH_CLI"
        source="cli"
    else
        local directive
        directive=$(playlist_scan_directive "branch")
        if [[ -n "$directive" ]]; then
            PLAYLIST_BRANCH="$directive"
            source="file"
        else
            local name
            name=$(basename "$PLAYLIST")
            name="${name%.*}"
            # When ralph is launched inside a worktree, suffix the default
            # branch with the worktree basename so two worktrees running
            # the same playlist filename don't collide on a single branch.
            if [[ "${IS_WORKTREE:-false}" == "true" && -n "${WORKTREE_NAME:-}" ]]; then
                PLAYLIST_BRANCH="${name}.playlist.${WORKTREE_NAME}"
            else
                PLAYLIST_BRANCH="${name}.playlist"
            fi
            source="default"
        fi
    fi

    log "Playlist branch: ${C_BOLD_CYAN}$PLAYLIST_BRANCH${C_RESET} (${source})"
}

# ── playlist_scan_directive ───────────────────────────────────────────────
#
# Scan playlist file header for a "# key: value" directive. Reads comment
# lines before the first actionable line. Returns the value or empty.

playlist_scan_directive() {
    local key="$1"
    local line trimmed
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" != \#* ]] && break
        local match
        match=$(echo "$trimmed" | sed -n "s/^#[[:space:]]*${key}:[[:space:]]*//Ip")
        [[ -n "$match" ]] && { echo "$match"; return; }
    done < "$PLAYLIST"
}
