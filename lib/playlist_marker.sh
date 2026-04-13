# playlist_marker.sh — Validation marker check on playlist startup.
#
# Scans for "# ✓ VALIDATED:" in the playlist header. If absent, warns
# and offers inline validation. Called from playlist_init().

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
# Interactive prompt when validation marker is missing. Non-TTY skips.

prompt_for_validation() {
    if [[ ! -t 0 ]]; then
        log "WARNING: Playlist not validated (non-interactive, continuing)"
        return
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
            PLAYLIST_LINES=()
            while IFS= read -r line || [[ -n "$line" ]]; do
                PLAYLIST_LINES+=("$line")
            done < "$PLAYLIST"
            recount_playlist_total
            init_playlist_checksum
            ;;
    esac
}
