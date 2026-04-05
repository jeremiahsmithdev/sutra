# playlist.sh — Read and navigate playlist files for ordered task execution.
#
# A playlist is a text file where each line is one of:
#   <bead-id>       — executed as a normal bead task
#   > <prompt>      — executed as a free-form Claude prompt (no bead)
#   # <comment>     — skipped
#   <blank line>    — skipped
#
# Functions:
#   playlist_init    — load playlist, set starting position from state
#   playlist_next    — advance to next actionable line, set globals
#   playlist_count   — return total actionable lines

# ── playlist_init ──────────────────────────────────────────────────────────
#
# Read the playlist file into the PLAYLIST_LINES array.
# Sets playlist_line (current file line number, 0-based) from state or 0.
# Sets playlist_total (count of actionable lines).

playlist_init() {
    PLAYLIST_LINES=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        PLAYLIST_LINES+=("$line")
    done < "$PLAYLIST"

    # Count actionable lines (not blank, not comments)
    playlist_total=0
    for line in "${PLAYLIST_LINES[@]}"; do
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
        playlist_total=$((playlist_total + 1))
    done

    # Resume position from state, or start at 0
    playlist_line="${playlist_line:-0}"

    log "Playlist: ${C_BOLD}$PLAYLIST${C_RESET} ($playlist_total actionable lines, starting at line $playlist_line)"
}

# ── playlist_next ──────────────────────────────────────────────────────────
#
# Advance past comments/blanks to the next actionable line.
# Sets globals:
#   playlist_current_line — the line text (bead ID or prompt text with > stripped)
#   playlist_line_type    — "bead" or "prompt"
#   playlist_line         — current file line number (for state persistence)
# Returns 1 when playlist is exhausted.

playlist_next() {
    local total=${#PLAYLIST_LINES[@]}
    local scan_line=$playlist_line

    while [[ $scan_line -lt $total ]]; do
        local raw="${PLAYLIST_LINES[$scan_line]}"
        scan_line=$((scan_line + 1))

        # Trim leading whitespace
        local trimmed="${raw#"${raw%%[![:space:]]*}"}"

        # Skip blanks and comments
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        # Classify line and reset per-line model override
        playlist_line_model=""
        if [[ "$trimmed" == ">"* ]]; then
            playlist_line_type="prompt"
            # Strip leading > and whitespace
            playlist_current_line="${trimmed#>}"
            playlist_current_line="${playlist_current_line#"${playlist_current_line%%[![:space:]]*}"}"
            # Check for @model prefix (e.g. >@opus Review changes)
            if [[ "$playlist_current_line" == @* ]]; then
                playlist_line_model="${playlist_current_line%% *}"
                playlist_line_model="${playlist_line_model#@}"
                playlist_current_line="${playlist_current_line#* }"
            fi
        else
            playlist_line_type="bead"
            playlist_current_line="$trimmed"
        fi

        # Store where to advance to AFTER successful execution.
        # playlist_line is only updated by playlist_advance() called from save_state.
        _playlist_pending_line=$scan_line
        return 0
    done

    # Exhausted
    return 1
}

# ── playlist_advance ──────────────────────────────────────────────────────
#
# Commit the playlist position after successful task execution.
# Called from save_state() — only advances after the task completes.
# This ensures that a crash mid-task resumes at the same line.

playlist_advance() {
    if [[ -n "${_playlist_pending_line:-}" ]]; then
        playlist_line=$_playlist_pending_line
        _playlist_pending_line=""
    fi
}

# ── playlist_handle_dry_run ────────────────────────────────────────────────
#
# If --dry-run is set, log the current playlist line and return 0 (skip).
# If not dry-run, return 1 (continue to execution).
# Mirrors handle_dry_run() from tasks.sh.

playlist_handle_dry_run() {
    [[ "$DRY_RUN" != "true" ]] && return 1
    playlist_dry_run
    return 0
}

# ── playlist_execute ──────────────────────────────────────────────────────
#
# Dispatch and execute the current playlist line (bead or prompt).
# Skips already-closed beads. Returns 0 on success or skip, 1 on abort.

playlist_execute() {
    if [[ "$playlist_line_type" == "bead" ]]; then
        bead_already_closed "$playlist_current_line" && return 0
        playlist_execute_bead || { _playlist_pending_line=""; return 1; }
    else
        playlist_execute_prompt || { _playlist_pending_line=""; return 1; }
    fi
}

# ── playlist_execute_bead ──────────────────────────────────────────────────
#
# Execute a bead-type playlist line using the standard task flow:
# claim → build prompt → invoke Claude → check status → circuit breaker.
# Returns 1 if invoke_claude fails (caller should break).

playlist_execute_bead() {
    tid="$playlist_current_line"
    claim_task "$tid"
    build_prompt "$tid" "$task_details"
    invoke_claude            || return 1
    check_bead_status "$tid"
    update_circuit_breaker
    handle_task_outcome "$tid"
}

# ── playlist_execute_prompt ───────────────────────────────────────────────
#
# Execute a raw-prompt playlist line (no bead to claim/close).
# Handles per-line model override and restore. Raw prompts always count
# as progress, resetting the circuit breaker.
# Returns 1 if invoke_claude fails (caller should break).

playlist_execute_prompt() {
    local saved_model=""
    if [[ -n "$playlist_line_model" ]]; then
        saved_model="$MODEL"
        MODEL="$playlist_line_model"
    fi

    local model_note=""
    [[ -n "$saved_model" ]] && model_note=" ${C_DIM}(model: $MODEL)${C_RESET}"

    log "=== Loop $((total_loops + 1))/$MAX_LOOPS === ${C_MAGENTA}[prompt]${C_RESET}${model_note}"
    log "Prompt: ${C_BOLD}${playlist_current_line:0:80}${C_RESET}"
    build_raw_prompt "$playlist_current_line"

    if ! invoke_claude; then
        [[ -n "$saved_model" ]] && MODEL="$saved_model"
        return 1
    fi

    [[ -n "$saved_model" ]] && MODEL="$saved_model"
    total_tasks_completed=$((total_tasks_completed + 1))
    no_progress_count=0
    if [[ "$circuit" == "HALF_OPEN" ]]; then
        circuit="CLOSED"
        log "Circuit recovered → CLOSED"
    fi
    current_task=""
}

# ── playlist_dry_run ───────────────────────────────────────────────────────
#
# Called per-line in dry-run mode. Validates bead IDs against br,
# checks status, and prints the execution plan with warnings.

# Accumulators for dry-run tracking
_dry_run_count=0
_dry_run_beads=0
_dry_run_prompts=0
_dry_run_warnings=()
_dry_run_seen_beads=()

playlist_dry_run() {
    _dry_run_count=$((_dry_run_count + 1))

    if [[ "$playlist_line_type" == "bead" ]]; then
        _dry_run_beads=$((_dry_run_beads + 1))
        _dry_run_seen_beads+=("$playlist_current_line")

        # Validate bead exists and get status
        local bead_json bead_status bead_title status_display
        bead_json=$(br show "$playlist_current_line" --json 2>/dev/null) || bead_json=""

        if [[ -z "$bead_json" ]]; then
            status_display="${C_BOLD_RED}NOT FOUND${C_RESET}"
            _dry_run_warnings+=("Line $_dry_run_count: $playlist_current_line does not exist in beads")
        else
            bead_status=$(echo "$bead_json" | jq -r '.[0].status // "unknown"' 2>/dev/null)
            bead_title=$(echo "$bead_json" | jq -r '.[0].title // "—"' 2>/dev/null)

            case "$bead_status" in
                closed)
                    status_display="${C_YELLOW}already closed${C_RESET}"
                    _dry_run_warnings+=("Line $_dry_run_count: $playlist_current_line is already closed")
                    ;;
                in_progress)
                    status_display="${C_CYAN}in progress${C_RESET}"
                    ;;
                *)
                    # Check dependencies
                    local deps_json blocked_by=""
                    deps_json=$(echo "$bead_json" | jq -r '
                        [.[0].dependencies // [] | .[]
                         | select(.dependency_type == "blocks")
                         | select(.status != "closed")
                         | .id] | join(", ")
                    ' 2>/dev/null) || deps_json=""

                    if [[ -n "$deps_json" ]]; then
                        # Check if blockers appear earlier in the playlist
                        local unsatisfied=""
                        IFS=', ' read -ra dep_ids <<< "$deps_json"
                        for dep_id in "${dep_ids[@]}"; do
                            local found=false
                            for seen in "${_dry_run_seen_beads[@]}"; do
                                [[ "$seen" == "$dep_id" ]] && { found=true; break; }
                            done
                            if [[ "$found" == false ]]; then
                                unsatisfied+="${unsatisfied:+, }$dep_id"
                            fi
                        done
                        if [[ -n "$unsatisfied" ]]; then
                            status_display="${C_YELLOW}blocked by $unsatisfied${C_RESET}"
                            _dry_run_warnings+=("Line $_dry_run_count: $playlist_current_line blocked by $unsatisfied — ensure prior lines complete first")
                        else
                            status_display="${C_GREEN}ready${C_RESET}"
                        fi
                    else
                        status_display="${C_GREEN}ready${C_RESET}"
                    fi
                    ;;
            esac
            log "  $_dry_run_count. [bead]   $playlist_current_line — $bead_title ($status_display)"
            return
        fi
        log "  $_dry_run_count. [bead]   $playlist_current_line ($status_display)"
    else
        _dry_run_prompts=$((_dry_run_prompts + 1))
        local model_tag=""
        [[ -n "$playlist_line_model" ]] && model_tag=" ${C_DIM}(@$playlist_line_model)${C_RESET}"
        log "  $_dry_run_count. [prompt] ${playlist_current_line:0:80}${model_tag}"
    fi
}

# ── playlist_dry_run_summary ──────────────────────────────────────────────
#
# Print summary after dry-run completes with totals and warnings.

playlist_dry_run_summary() {
    log ""
    log "PLAYLIST: $PLAYLIST ($_dry_run_count items: $_dry_run_beads beads + $_dry_run_prompts prompts)"

    if [[ ${#_dry_run_warnings[@]} -gt 0 ]]; then
        log ""
        log "WARNINGS:"
        for warning in "${_dry_run_warnings[@]}"; do
            log "  * $warning"
        done
    fi
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

# ── playlist_report_data ───────────────────────────────────────────────────
#
# Generate a text summary of all playlist lines and their current status.
# Used by the completion report prompt to give Claude full context.

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
            local bead_status="unknown"
            bead_status=$(br show "$trimmed" --json 2>/dev/null \
                | jq -r '.[0].status // "unknown"' 2>/dev/null) || true
            printf '%d. [bead] %s (status: %s, processed: %s)\n' "$item_num" "$trimmed" "$bead_status" "$was_processed"
        fi
    done
}
