# playlist_validate.sh — Dry-run validation and post-run reporting.
#
# Dry-run path (called per-line when --dry-run is set): validate bead IDs,
# check statuses, detect unsatisfied blockers, accumulate warnings.
# Report path: playlist_report_data() generates the post-run text summary
# consumed by the completion report prompt.
#
# All "_dry_run_*" globals are module-scoped accumulators that reset on
# fresh source so each session starts clean.

_dry_run_count=0
_dry_run_beads=0
_dry_run_prompts=0
_dry_run_warnings=()
_dry_run_seen_beads=()

# ── playlist_dry_run ──────────────────────────────────────────────────────
#
# Entry point called from playlist_handle_dry_run. Dispatches to
# bead-validation or prompt-validation based on the current line type.

playlist_dry_run() {
    _dry_run_count=$((_dry_run_count + 1))
    if [[ "$playlist_line_type" == "bead" ]]; then
        validate_bead_dry_run
    else
        validate_prompt_dry_run
    fi
}

# ── validate_bead_dry_run ─────────────────────────────────────────────────
#
# Validate the current bead line: fetch from br, compute display status,
# log the plan entry. Missing beads and already-closed beads become warnings.

validate_bead_dry_run() {
    _dry_run_beads=$((_dry_run_beads + 1))
    _dry_run_seen_beads+=("$playlist_current_line")

    local bead_json
    bead_json=$(br show "$playlist_current_line" --json 2>/dev/null) || bead_json=""

    if [[ -z "$bead_json" ]]; then
        _dry_run_warnings+=("Line $_dry_run_count: $playlist_current_line does not exist in beads")
        log "  $_dry_run_count. [bead]   $playlist_current_line (${C_BOLD_RED}NOT FOUND${C_RESET})"
        return
    fi

    local bead_title status_display
    bead_title=$(echo "$bead_json" | jq -r '.[0].title // "—"' 2>/dev/null)
    status_display=$(compute_bead_display_status "$bead_json")
    log "  $_dry_run_count. [bead]   $playlist_current_line — $bead_title ($status_display)"
}

# ── compute_bead_display_status ───────────────────────────────────────────
#
# Given pre-fetched bead JSON, return the colored status string to show
# in the dry-run plan. Handles closed/in_progress/open + dependency check.

compute_bead_display_status() {
    local bead_json="$1"
    local bead_status
    bead_status=$(echo "$bead_json" | jq -r '.[0].status // "unknown"' 2>/dev/null)

    case "$bead_status" in
        closed)
            _dry_run_warnings+=("Line $_dry_run_count: $playlist_current_line is already closed")
            echo "${C_YELLOW}already closed${C_RESET}"
            ;;
        in_progress)
            echo "${C_CYAN}in progress${C_RESET}"
            ;;
        *)
            check_bead_blockers "$bead_json"
            ;;
    esac
}

# ── check_bead_blockers ───────────────────────────────────────────────────
#
# Examine the bead's blocks dependencies. If any blockers don't appear
# earlier in the playlist, flag them as unsatisfied and add a warning.

check_bead_blockers() {
    local bead_json="$1"
    local deps
    deps=$(echo "$bead_json" | jq -r '[.[0].dependencies // [] | .[] | select(.dependency_type == "blocks") | select(.status != "closed") | .id] | join(", ")' 2>/dev/null)

    if [[ -z "$deps" ]]; then
        echo "${C_GREEN}ready${C_RESET}"
        return
    fi

    local unsatisfied
    unsatisfied=$(find_unsatisfied_blockers "$deps")

    if [[ -n "$unsatisfied" ]]; then
        _dry_run_warnings+=("Line $_dry_run_count: $playlist_current_line blocked by $unsatisfied — ensure prior lines complete first")
        echo "${C_YELLOW}blocked by $unsatisfied${C_RESET}"
    else
        echo "${C_GREEN}ready${C_RESET}"
    fi
}

# ── find_unsatisfied_blockers ─────────────────────────────────────────────
#
# Given a comma-separated list of blocker IDs, return the ones that don't
# appear in _dry_run_seen_beads (earlier in the playlist). Empty if all
# blockers are satisfied.

find_unsatisfied_blockers() {
    local deps="$1"
    local unsatisfied=""
    local dep_id seen found
    IFS=', ' read -ra dep_ids <<< "$deps"
    for dep_id in "${dep_ids[@]}"; do
        found=false
        for seen in "${_dry_run_seen_beads[@]}"; do
            [[ "$seen" == "$dep_id" ]] && { found=true; break; }
        done
        [[ "$found" == false ]] && unsatisfied+="${unsatisfied:+, }$dep_id"
    done
    echo "$unsatisfied"
}

# ── validate_prompt_dry_run ───────────────────────────────────────────────
#
# Log a prompt-type playlist line with its optional @model tag.

validate_prompt_dry_run() {
    _dry_run_prompts=$((_dry_run_prompts + 1))
    local model_tag=""
    [[ -n "$playlist_line_model" ]] && model_tag=" ${C_DIM}(@$playlist_line_model)${C_RESET}"
    log "  $_dry_run_count. [prompt] ${playlist_current_line:0:80}${model_tag}"
}

# ── playlist_dry_run_summary ──────────────────────────────────────────────
#
# Print the final summary after dry-run walks the whole playlist.

playlist_dry_run_summary() {
    log ""
    log "PLAYLIST: $PLAYLIST ($_dry_run_count items: $_dry_run_beads beads + $_dry_run_prompts prompts)"

    if [[ ${#_dry_run_warnings[@]} -gt 0 ]]; then
        log ""
        log "WARNINGS:"
        local warning
        for warning in "${_dry_run_warnings[@]}"; do
            log "  * $warning"
        done
    fi
}

# ── playlist_report_data ──────────────────────────────────────────────────
#
# Text summary of all playlist lines and their current status.
# Consumed by the completion report prompt to give Claude full context.

playlist_report_data() {
    local total=${#PLAYLIST_LINES[@]}
    local idx=0 item_num=0

    while [[ $idx -lt $total ]]; do
        local raw="${PLAYLIST_LINES[$idx]}"
        idx=$((idx + 1))
        local trimmed="${raw#"${raw%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        item_num=$((item_num + 1))
        local was_processed="no"
        [[ $idx -le $playlist_line ]] && was_processed="yes"

        if [[ "$trimmed" == ">"* ]]; then
            local prompt_text="${trimmed#>}"
            prompt_text="${prompt_text#"${prompt_text%%[![:space:]]*}"}"
            printf '%d. [prompt] %s (processed: %s)\n' "$item_num" "${prompt_text:0:80}" "$was_processed"
        else
            local bead_status
            bead_status=$(get_bead_status "$trimmed")
            printf '%d. [bead] %s (status: %s, processed: %s)\n' "$item_num" "$trimmed" "$bead_status" "$was_processed"
        fi
    done
}

# ── playlist_processed ─────────────────────────────────────────────────────
#
# Return the number of actionable lines processed so far.

playlist_processed() {
    local count=0
    local i=0
    while [[ $i -lt $playlist_line ]]; do
        local raw="${PLAYLIST_LINES[$i]}"
        local trimmed="${raw#"${raw%%[![:space:]]*}"}"
        [[ -n "$trimmed" && "$trimmed" != \#* ]] && count=$((count + 1))
        i=$((i + 1))
    done
    echo "$count"
}
