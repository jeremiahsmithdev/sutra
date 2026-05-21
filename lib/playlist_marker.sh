# playlist_marker.sh — Validation marker check and insertion.
#
# check_validation_marker(): scans playlist header on startup, warns if absent.
# add_validation_marker(): inserts marker after init validation passes.

# ── check_validation_marker ───────────────────────────────────────────────
#
# Scan first 5 lines for the validation marker. If absent: warn and
# prompt (interactive) or continue silently (non-TTY / dry-run).

check_validation_marker() {
    local i=0 found=false
    while [[ $i -lt 5 && $i -lt ${#PLAYLIST_LINES[@]} ]]; do
        if [[ "${PLAYLIST_LINES[$i]}" == *"✓ VALIDATED:"* ]]; then
            found=true
            break
        fi
        i=$((i + 1))
    done

    if [[ "$found" == true ]]; then
        log "Playlist validated: ${PLAYLIST_LINES[$i]}"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "WARNING: Playlist not validated (dry-run, skipping prompt)"
        return
    fi

    prompt_for_validation
}

# ── prompt_for_validation ─────────────────────────────────────────────────
#
# Interactive prompt when validation marker is missing.
# Non-interactive (no TTY): halts unless PLAYLIST_AUTO_CONTINUE=true or --yes.

prompt_for_validation() {
    if [[ ! -t 0 ]]; then
        if [[ "${PLAYLIST_AUTO_CONTINUE:-false}" == "true" || "${YES:-false}" == "true" ]]; then
            log "WARNING: Playlist not validated (non-interactive, PLAYLIST_AUTO_CONTINUE=true — proceeding)"
            return
        fi
        log "ERROR: Playlist not validated and running non-interactively."
        log "  Run 'ralph playlist init $PLAYLIST' first, or:"
        log "    set PLAYLIST_AUTO_CONTINUE=true in .sutra/config, or"
        log "    pass --yes to ralph on the CLI."
        exit 1
    fi

    log "WARNING: Playlist not validated."
    printf '%s\n' "  Run 'ralph playlist init $PLAYLIST' to validate and add quality gates."
    printf '%s' "  Continue anyway? [y/N] "

    local answer
    read -r answer </dev/tty
    case "$answer" in
        [yY])
            log "Proceeding without validation"
            ;;
        *)
            offer_inline_init
            ;;
    esac
}

# ── offer_inline_init ─────────────────────────────────────────────────────
#
# Offer to run syntax validation inline when user declines to continue.

offer_inline_init() {
    printf '%s' "  Run syntax validation on $PLAYLIST? [Y/n] "
    local answer
    read -r answer </dev/tty
    case "$answer" in
        [nN])
            log "Exiting."
            exit 1
            ;;
        *)
            run_playlist_init || exit 1
            read_playlist_file
            recount_playlist_total
            init_playlist_checksum
            ;;
    esac
}

# ── add_validation_marker ──────────────────────────────────────────────────
#
# Add validation marker to the top of the playlist if not already present.

add_validation_marker() {
    if head -5 "$PLAYLIST" 2>/dev/null | grep -q "✓ VALIDATED:"; then
        return  # Already present
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local marker="# ✓ VALIDATED: $timestamp by ralph playlist init"

    # Create temp file with marker inserted
    local temp_file
    temp_file=$(mktemp)

    if head -1 "$PLAYLIST" 2>/dev/null | grep -q "^#!"; then
        # Insert after shebang
        head -1 "$PLAYLIST" > "$temp_file"
        echo "$marker" >> "$temp_file"
        tail -n +2 "$PLAYLIST" >> "$temp_file"
    else
        # Insert at beginning
        echo "$marker" > "$temp_file"
        cat "$PLAYLIST" >> "$temp_file"
    fi

    mv "$temp_file" "$PLAYLIST"
}
