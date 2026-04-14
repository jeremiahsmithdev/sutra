# playlist_create.sh — Generate playlists via Claude and verify them.
#
# Entry point: run_playlist_create(), dispatched from args.sh when
# `ralph playlist create` is invoked. Gathers beads, invokes Claude
# to generate the playlist, then pipes through run_playlist_init.

# ── extract_playlist_from_log ─────────────────────────────────────────────
#
# Extract the playlist content from Claude's stream-json output.
# Looks for text inside ``` code blocks first. Falls back to lines
# that look like bead IDs or > prompt lines.

extract_playlist_from_log() {
    local log_file="$1"
    local raw_text
    raw_text=$(jq -rs '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text] | join("\n")' "$log_file")

    # Try code block extraction first
    local code_block
    code_block=$(echo "$raw_text" | sed -n '/^```/,/^```/{/^```/d;p;}')

    if [[ -n "$code_block" ]]; then
        echo "$code_block"
        return
    fi

    # Fallback: grab lines that look like playlist entries
    echo "$raw_text" | grep -E '^(>|[a-z]+-[a-z0-9]+\.[0-9]+)' || true
}

# ── inject_epic_branch_directive ──────────────────────────────────────────
#
# For a single-epic playlist, generate and set the branch directive.
# Sets global _injected_branch with "# branch: <epic-slug>.playlist"

inject_epic_branch_directive() {
    local epic_id="$1"
    local epic_json
    epic_json=$(br show "$epic_id" --json 2>/dev/null)
    if [[ -n "$epic_json" ]]; then
        local epic_title
        epic_title=$(echo "$epic_json" | jq -r '.[0].title // ""')
        if [[ -n "$epic_title" ]]; then
            local epic_slug
            epic_slug=$(slugify "$epic_title")
            _injected_branch="# branch: ${epic_slug}.playlist"
        fi
    fi
}

# ── run_playlist_create ────────────────────────────────────────────────────
#
# Entry point for `ralph playlist create [ids...] [--epic epic-id] -o file`.
# Gathers beads, invokes Claude to generate playlist with ordering + gates,
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

    # Add raw bead IDs
    bead_list+=("${PLAYLIST_CREATE_BEADS[@]}")

    if [[ ${#bead_list[@]} -eq 0 ]]; then
        log "ERROR: No beads found"
        return 1
    fi

    log "  ${#bead_list[@]} beads to include"

    # Step 2: Build creation prompt
    log "Building creation prompt..."
    build_playlist_create_prompt "${bead_list[@]}" "$epic_count"

    # Step 3: Invoke Claude
    log "Invoking Claude to generate playlist..."
    if ! invoke_claude; then
        log "ERROR: Claude invocation failed"
        return 1
    fi

    # Step 4: Inject branch directive if single epic
    if [[ $epic_count -eq 1 ]]; then
        inject_epic_branch_directive "${PLAYLIST_CREATE_EPICS[0]}"
    fi

    # Step 5: Extract Claude's output and write playlist file
    local claude_output
    claude_output=$(extract_playlist_from_log "$INVOKE_LOG")
    if [[ -z "$claude_output" ]]; then
        log "ERROR: No playlist content in Claude's output"
        return 1
    fi

    log "Writing playlist to: $OUTPUT_FILE"
    {
        [[ -n "${_injected_branch:-}" ]] && echo "$_injected_branch"
        echo "$claude_output"
    } > "$OUTPUT_FILE"

    # Step 6: Pipe through init for verification
    log "Running validation pipeline..."
    PLAYLIST="$OUTPUT_FILE"
    read_playlist_file

    run_playlist_init || return 1

    log ""
    log "${C_GREEN}✓ Playlist created successfully${C_RESET}"
    log "Output: $OUTPUT_FILE"
}

# ── build_playlist_create_prompt ───────────────────────────────────────────
#
# Build Claude prompt for playlist generation. Focuses on ordering, gate
# placement, and structure. Verification happens in init pipeline.

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
        "EPIC_NOTES=$epic_notes")
}
