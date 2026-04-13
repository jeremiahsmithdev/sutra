# gates.sh — Quality gate template system for playlist prompts.
#
# Gate tags (#SMOKE_TEST, #COMPLETENESS_SCAN, #REVIEW) are shorthand in
# playlist files that ralph expands at runtime, same as @opus resolves
# the model. The playlist file is never modified by expansion.

declare -A GATE_TEMPLATES

GATE_TEMPLATES[SMOKE_TEST]="Test API endpoints against live backend. curl each endpoint implemented in the last batch of beads. Verify responses match expected schemas. If issues found: create beads (type=bug only) with br create, insert IDs into the playlist file after this line."

GATE_TEMPLATES[COMPLETENESS_SCAN]="Scan for incomplete work: grep -rn 'TODO|FIXME|HACK|STUB|placeholder|not yet|not implemented' in the project source. For each match in code written during this playlist, implement it fully or remove it with justification. If issues require separate tasks: create beads (type=bug only) and inject into playlist."

GATE_TEMPLATES[REVIEW]="Review the work completed in the last epic. Check architecture, patterns, test coverage. Flag issues. If significant work needed: create beads (type=bug only) and inject into playlist."

# ── gate_expand_tag ───────────────────────────────────────────────────────
#
# Look up a gate tag and return the expanded prompt text: template base
# text followed by user-provided context. Claude receives this; the raw
# #TAG never reaches the inner loop.

gate_expand_tag() {
    local tag="$1"
    local context="${2:-}"
    local base="${GATE_TEMPLATES[$tag]}"

    if [[ -n "$context" ]]; then
        printf '%s\n%s' "$base" "$context"
    else
        printf '%s' "$base"
    fi
}

# ── gate_is_valid_tag ─────────────────────────────────────────────────────
#
# Return 0 if tag exists in GATE_TEMPLATES, 1 otherwise.

gate_is_valid_tag() {
    [[ -v "GATE_TEMPLATES[$1]" ]]
}

# ── gate_valid_tags_list ──────────────────────────────────────────────────
#
# Return comma-separated list of valid tag names for error messages.

gate_valid_tags_list() {
    local IFS=','
    echo "${!GATE_TEMPLATES[*]}"
}

# ── parse_playlist_gate_tag ────────────────────────────────────────────────
#
# After parse_playlist_prompt_line, detect #TAG in playlist_current_line.
# Validates the tag, rejects multiple tags, and splits into tag + context.
# Sets playlist_line_gate_tag and playlist_line_gate_context globals.
# Returns 1 (halts playlist) on unknown or multiple tags.

parse_playlist_gate_tag() {
    [[ "$playlist_current_line" != \#* ]] && return 0

    local rest="$playlist_current_line"
    local tag="${rest%% *}"
    tag="${tag#\#}"

    # Reject multiple tags on same line
    local after="${rest#* }"
    if [[ "$after" != "$rest" && "$after" == \#* ]]; then
        log "ERROR: Multiple gate tags on line $scan_line: $rest"
        return 1
    fi

    if ! gate_is_valid_tag "$tag"; then
        log "ERROR: Unknown gate template: #$tag on line $scan_line. Valid tags: $(gate_valid_tags_list)"
        return 1
    fi

    playlist_line_gate_tag="$tag"
    if [[ "$after" != "$rest" ]]; then
        playlist_line_gate_context="$after"
    fi
    playlist_current_line="$rest"
}

# ── gate_check_playlist ──────────────────────────────────────────────────
#
# Scan PLAYLIST_LINES for #TAG markers and bead lines. Returns a
# structured report: bead count, gate count, per-tag counts, density
# ratio, and violations against minimum rules.

gate_check_playlist() {
    local bead_count=0 gate_count=0
    declare -A tag_counts

    for line in "${PLAYLIST_LINES[@]}"; do
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* && "$trimmed" != *">"* ]] && continue

        if [[ "$trimmed" == ">"* ]]; then
            local content="${trimmed#>}"
            content="${content#"${content%%[![:space:]]*}"}"
            # Strip @model prefix
            [[ "$content" == @* ]] && content="${content#* }"
            # Check for #TAG
            if [[ "$content" == \#* ]]; then
                local tag="${content%% *}"
                tag="${tag#\#}"
                gate_count=$((gate_count + 1))
                tag_counts[$tag]=$(( ${tag_counts[$tag]:-0} + 1 ))
            fi
        else
            bead_count=$((bead_count + 1))
        fi
    done

    printf 'beads=%d gates=%d' "$bead_count" "$gate_count"
    for tag in "${!tag_counts[@]}"; do
        printf ' %s=%d' "$tag" "${tag_counts[$tag]}"
    done
    echo
}

# ── gate_minimum_rules ────────────────────────────────────────────────────
#
# Check gate density against configurable minimums. Prints violations
# as ERROR or WARNING lines. Returns 1 if any ERROR found, 0 otherwise.

gate_minimum_rules() {
    local bead_count="$1" gate_count="$2"
    shift 2
    # Remaining args: TAG=count pairs
    declare -A tag_counts
    local pair
    for pair in "$@"; do
        local key="${pair%%=*}" val="${pair#*=}"
        tag_counts[$key]="$val"
    done

    local has_error=false

    if [[ $bead_count -gt 1 && $gate_count -eq 0 ]]; then
        echo "ERROR: Zero gates in playlist with $bead_count beads"
        has_error=true
    fi

    if [[ $bead_count -gt 0 && $gate_count -gt 0 ]]; then
        local ratio=$((bead_count / gate_count))
        if [[ $ratio -gt $GATE_DENSITY_RATIO ]]; then
            echo "WARNING: Low gate density — 1 gate per $ratio beads (target: 1 per $GATE_DENSITY_RATIO)"
        fi
    fi

    if [[ $bead_count -gt 10 && ${tag_counts[COMPLETENESS_SCAN]:-0} -eq 0 ]]; then
        echo "WARNING: No #COMPLETENESS_SCAN in playlist with $bead_count beads"
    fi

    if [[ $bead_count -gt 5 && ${tag_counts[SMOKE_TEST]:-0} -eq 0 ]]; then
        echo "WARNING: No #SMOKE_TEST in playlist with $bead_count beads"
    fi

    if [[ $bead_count -gt 10 && ${tag_counts[REVIEW]:-0} -eq 0 ]]; then
        echo "WARNING: No #REVIEW in playlist with $bead_count beads"
    fi

    [[ "$has_error" == true ]] && return 1
    return 0
}
