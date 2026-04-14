# playlist_semantic.sh — Phase 2: Claude-assisted playlist validation.
#
# Called from run_playlist_init() after Phase 1 (syntax + gate density)
# passes. Injects missing gates, invokes Claude for semantic audit,
# and adds the validation marker.

# ── playlist_validate_semantic ─────────────────────────────────────────────
#
# Phase 2: semantic validation via Claude. Injects missing gates, then
# invokes Claude to add context, verify descriptions, and add marker.
#
# Modifies PLAYLIST in place. Caller should review with git diff.

playlist_validate_semantic() {
    log ""
    log "${C_BOLD}Phase 2: Semantic Validation${C_RESET}"

    # Step 1: Inject missing gate shorthand lines
    log "Injecting missing gates..."
    local injected
    injected=$(playlist_inject_gates "$PLAYLIST")
    log "  Injected $injected gates"

    # Reload PLAYLIST_LINES since we modified the file
    read_playlist_file

    # Step 2: Build Claude prompt for semantic audit
    log "Building audit prompt..."
    build_playlist_semantic_prompt

    # Step 3: Invoke Claude
    log "Invoking Claude for semantic audit..."
    if ! invoke_claude; then
        log "${C_BOLD_RED}ERROR${C_RESET}: Claude invocation failed. Playlist may have been partially modified."
        return 1
    fi

    # Add validation marker if not already present
    add_validation_marker

    log ""
    log "${C_GREEN}✓ Semantic validation complete${C_RESET}"
    log "Review changes with: ${C_DIM}git diff $PLAYLIST${C_RESET}"
}

# ── build_playlist_semantic_prompt ────────────────────────────────────────
#
# Build a detailed Claude prompt for semantic playlist audit.
# Sets the global $prompt variable for invoke_claude.
# Uses templates/prompt_playlist_validate.txt for the prompt structure.

build_playlist_semantic_prompt() {
    local playlist_content
    playlist_content=$(<"$PLAYLIST")

    # Gather bead summaries — title and deps only, no implementation details
    local bead_details=""
    for line in "${PLAYLIST_LINES[@]}"; do
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* || "$trimmed" == ">"* ]] && continue

        local bead_id="$trimmed"
        local bead_json
        bead_json=$(br show "$bead_id" --json 2>/dev/null)
        if [[ -n "$bead_json" ]]; then
            local title deps
            title=$(echo "$bead_json" | jq -r '.[0].title // ""')
            deps=$(echo "$bead_json" | jq -r '[.[0].dependencies[]? | .id] | join(", ") // ""')
            local line="$bead_id — $title"
            [[ -n "$deps" ]] && line+=" [depends: $deps]"
            bead_details+="$line"$'\n'
        fi
    done

    prompt=$(render_template "$TEMPLATES_DIR/prompt_playlist_validate.txt" \
        "PLAYLIST_PATH=$PLAYLIST" \
        "PLAYLIST_CONTENT=$playlist_content" \
        "BEAD_DETAILS=$bead_details")
}
