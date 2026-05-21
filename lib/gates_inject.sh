# gates_inject.sh — Inject missing gate lines into playlist files.
#
# Called by playlist authoring tools (sutra playlist init, playlist create).
# Inserts tactical gates (SMOKE_TEST, COMPLETENESS_SCAN, REVIEW) at
# density-based intervals and tail gates (REFACTOR, DOCUMENT) at the end.

# ── playlist_inject_gates ──────────────────────────────────────────────────
#
# Inject missing gate lines into a playlist file. Reads the file, tracks
# bead count, epic boundaries, and gate presence. Inserts:
#   - #SMOKE_TEST after first 5 beads if missing
#   - #COMPLETENESS_SCAN every ~5 beads without a gate
#   - #REVIEW at epic boundaries (parent epic changes)
#   - #REFACTOR and #DOCUMENT at playlist tail (>5 beads only)
#
# Writes augmented playlist back to file. Returns count of gates injected.

playlist_inject_gates() {
    local playlist_file="$1"
    [[ ! -f "$playlist_file" ]] && return 1

    local -a lines=()
    local -a output=()
    local gate_count=0
    local bead_count=0
    local beads_since_gate=0
    local last_epic=""
    local has_smoke_test=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$playlist_file"

    # Pre-scan: if a SMOKE_TEST gate already exists anywhere in the file,
    # don't inject another one. Without this, the injection fires at bead 5
    # before encountering an existing gate that sits after bead 5.
    local prescan_line
    for prescan_line in "${lines[@]}"; do
        local prescan_trimmed="${prescan_line#"${prescan_line%%[![:space:]]*}"}"
        if [[ "$prescan_trimmed" == ">"* ]]; then
            local prescan_content="${prescan_trimmed#>}"
            prescan_content="${prescan_content#"${prescan_content%%[![:space:]]*}"}"
            [[ "$prescan_content" == @* ]] && prescan_content="${prescan_content#* }"
            [[ "$prescan_content" == "#SMOKE_TEST"* ]] && has_smoke_test=true
        fi
    done

    for line in "${lines[@]}"; do
        local trimmed="${line#"${line%%[![:space:]]*}"}"

        if [[ -z "$trimmed" || ("$trimmed" == \#* && "$trimmed" != *">"*) ]]; then
            output+=("$line")
            continue
        fi

        if [[ "$trimmed" == ">"* ]]; then
            output+=("$line")
            local content="${trimmed#>}"
            content="${content#"${content%%[![:space:]]*}"}"
            [[ "$content" == @* ]] && content="${content#* }"
            if [[ "$content" == \#* ]]; then
                local tag="${content%% *}"
                tag="${tag#\#}"
                beads_since_gate=0
                [[ "$tag" == "SMOKE_TEST" ]] && has_smoke_test=true
            fi
            continue
        fi

        local bead_id="$trimmed"
        bead_count=$((bead_count + 1))
        beads_since_gate=$((beads_since_gate + 1))

        local current_epic=""
        current_epic=$(br show "$bead_id" --json 2>/dev/null | jq -r '.[0].parent // ""')

        if [[ -n "$last_epic" && "$current_epic" != "$last_epic" && $bead_count -gt 1 ]]; then
            output+=("> #REVIEW")
            gate_count=$((gate_count + 1))
            beads_since_gate=0
        fi

        if [[ "$has_smoke_test" == false && $bead_count -eq 5 ]]; then
            output+=("> #SMOKE_TEST")
            gate_count=$((gate_count + 1))
            has_smoke_test=true
            beads_since_gate=0
        fi

        if [[ $beads_since_gate -ge 5 ]]; then
            output+=("> #COMPLETENESS_SCAN")
            gate_count=$((gate_count + 1))
            beads_since_gate=0
        fi

        output+=("$line")
        last_epic="$current_epic"
    done

    if [[ $bead_count -gt 5 ]]; then
        inject_tail_gate output gate_count "REFACTOR"
        inject_tail_gate output gate_count "DOCUMENT"
    fi

    {
        for line in "${output[@]}"; do
            echo "$line"
        done
    } > "$playlist_file"

    echo "$gate_count"
}

# ── inject_tail_gate ──────────────────────────────────────────────────────
#
# Append a gate tag at the end of the output array if not already present.

inject_tail_gate() {
    local -n _output=$1 _count=$2
    local tag="$3"

    local line
    for line in "${_output[@]}"; do
        [[ "$line" == *"#$tag"* ]] && return
    done

    _output+=("> #$tag")
    _count=$((_count + 1))
}
