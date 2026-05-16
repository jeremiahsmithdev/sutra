# playlist_validate_gates.sh — Gate-related dry-run analysis.
#
# Split from playlist_validate.sh to keep both files within the 200-line
# limit. Covers trailing-bead detection and gate-density reporting; the
# functions here read PLAYLIST and accumulate into the _dry_run_* globals
# owned by playlist_validate.sh.

# ── check_trailing_beads ──────────────────────────────────────────────────
#
# A bare bead ID after the trailing gate cluster (#REFACTOR / #DOCUMENT …)
# is mis-positioned — a bead belongs at its dependency slot, not appended
# past the gates that close out the playlist. Scan the file for bead lines
# after the last gate line and accumulate a warning (not a hard error).

check_trailing_beads() {
    [[ -f "$PLAYLIST" ]] || return
    local last_gate=0 lineno=0 line trimmed bead
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in
            \#SMOKE_TEST*|\#COMPLETENESS_SCAN*|\#REVIEW*|\#REFACTOR*|\#DOCUMENT*)
                last_gate=$lineno ;;
        esac
    done < "$PLAYLIST"

    [[ $last_gate -eq 0 ]] && return

    lineno=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        [[ $lineno -le $last_gate ]] && continue
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in
            ''|\#*|\>*|✓*) continue ;;
        esac
        bead="${trimmed%%[[:space:]]*}"
        _dry_run_warnings+=("Line $lineno: $bead appears after the last gate (line $last_gate) — move it to its dependency slot or remove it")
    done < "$PLAYLIST"
}

# ── report_gate_analysis ───────────────────────────────────────────────────
#
# Print gate density analysis from gate_check_playlist() and gate_minimum_rules().

report_gate_analysis() {
    local report
    report=$(gate_check_playlist)

    local beads gates
    local -a tag_pairs
    parse_gate_report "$report" beads gates tag_pairs

    log ""
    log "GATE ANALYSIS:"
    if [[ $beads -gt 0 || $gates -gt 0 ]]; then
        local ratio
        if [[ $gates -gt 0 ]]; then
            ratio=$((beads / gates))
        else
            ratio=0
        fi
        log "  Beads: $beads  |  Gates: $gates  |  Density: $ratio:1"
    fi

    # Show per-template counts if gates exist
    if [[ ${#tag_pairs[@]} -gt 0 ]]; then
        local tags_display=""
        local tag_pair
        for tag_pair in "${tag_pairs[@]}"; do
            local tag="${tag_pair%%=*}" count="${tag_pair#*=}"
            tags_display+="  #${tag}: $count"
            [[ "$tag_pair" != "${tag_pairs[-1]}" ]] && tags_display+=" | "
        done
        [[ -n "$tags_display" ]] && log "$tags_display"
    fi

    # Check for violations
    local violations
    violations=$(gate_minimum_rules "$beads" "$gates" "${tag_pairs[@]}" 2>&1)

    if [[ -n "$violations" ]]; then
        local has_error=false
        while IFS= read -r vline; do
            if [[ "$vline" == ERROR:* ]]; then
                has_error=true
                log "  ${C_BOLD_RED}$vline${C_RESET}"
            elif [[ "$vline" == WARNING:* ]]; then
                log "  ${C_BOLD_YELLOW}$vline${C_RESET}"
            fi
        done <<< "$violations"

        if [[ "$has_error" != true ]] && [[ -n "$violations" ]]; then
            log "  ${C_BOLD_YELLOW}RECOMMENDATIONS:${C_RESET}"
            log "    * Run 'ralph playlist init $PLAYLIST' to add quality gates"
        fi
    else
        [[ $beads -gt 0 ]] && log "  ${C_GREEN}✓ Gate density OK${C_RESET}"
    fi
}
