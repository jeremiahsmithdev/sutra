# playlist_create.sh — Generate playlists via Claude and verify them.
#
# Entry point: run_playlist_create(), dispatched from args.sh when
# `ralph playlist create` is invoked. Gathers beads, invokes Claude
# to generate and write the playlist file, then pipes through run_playlist_init.

# ── run_playlist_create ────────────────────────────────────────────────────
#
# Entry point for `ralph playlist create [ids...] [--epic epic-id] -o file`.
# Gathers beads, invokes Claude to generate and write the playlist,
# then pipes through init for verification.

run_playlist_create() {
    log "Creating playlist: ${C_BOLD}$OUTPUT_FILE${C_RESET}"

    # Step 1: Gather bead list
    local -a bead_list=()
    local epic_count=${#PLAYLIST_CREATE_EPICS[@]}

    if [[ $epic_count -gt 0 ]]; then
        log "Expanding epics..."
        for epic_id in "${PLAYLIST_CREATE_EPICS[@]}"; do
            local epic_beads
            epic_beads=$(br ready --parent="$epic_id" -r --json 2>/dev/null | jq -r '.[].id' | tr '\n' ' ')
            bead_list+=($epic_beads)
        done
    fi

    bead_list+=("${PLAYLIST_CREATE_BEADS[@]}")

    if [[ ${#bead_list[@]} -eq 0 ]]; then
        log "ERROR: No beads found"
        return 1
    fi

    log "  ${#bead_list[@]} beads to include"

    # Step 2: Build creation prompt
    log "Building creation prompt..."
    build_playlist_create_prompt "${bead_list[@]}" "$epic_count"

    # Step 3: Invoke Claude — writes OUTPUT_FILE directly
    log "Invoking Claude to generate playlist..."
    if ! invoke_claude; then
        log "ERROR: Claude invocation failed"
        return 1
    fi

    if [[ ! -f "$OUTPUT_FILE" ]]; then
        log "ERROR: Claude did not write $OUTPUT_FILE"
        return 1
    fi

    # Step 4: Pipe through init for verification (auto — no prompt)
    log "Running validation pipeline..."
    PLAYLIST="$OUTPUT_FILE"
    read_playlist_file
    run_playlist_init "auto" || return 1

    log ""
    log "${C_GREEN}✓ Playlist created successfully${C_RESET}"
    log "Output: $OUTPUT_FILE"
}

# ── build_playlist_create_prompt ───────────────────────────────────────────
#
# Build Claude prompt for playlist generation. Passes OUTPUT_FILE so
# Claude writes the file directly. Verification happens in init pipeline.

build_playlist_create_prompt() {
    local -a beads=("${@:1:$#-1}")
    local epic_count="${@: -1}"

    local bead_details=""
    for bead_id in "${beads[@]}"; do
        local bead_json
        bead_json=$(br show "$bead_id" --json 2>/dev/null)
        if [[ -n "$bead_json" ]]; then
            local title parent deps
            title=$(echo "$bead_json" | jq -r '.[0].title // ""')
            parent=$(echo "$bead_json" | jq -r '.[0].parent // ""')
            deps=$(echo "$bead_json" | jq -r '[.[0].dependencies[]? | .id] | join(", ") // ""')
            local line="$bead_id — $title (parent: $parent)"
            [[ -n "$deps" ]] && line+=" [depends: $deps]"
            bead_details+="$line"$'\n'
        fi
    done

    local epic_notes=""
    if [[ $epic_count -gt 1 ]]; then
        epic_notes="Multiple epics included. Mark epic boundaries with #REVIEW gates."
    fi

    prompt=$(render_template "$TEMPLATES_DIR/prompt_playlist_create.txt" \
        "BEAD_DETAILS=$bead_details" \
        "EPIC_NOTES=$epic_notes" \
        "OUTPUT_FILE=$OUTPUT_FILE")
}
