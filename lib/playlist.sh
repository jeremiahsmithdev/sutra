# playlist.sh — Parse, navigate, and execute playlist files.
#
# A playlist line is one of: <bead-id>, `> <prompt>`, `# comment`, or blank.
# Dry-run validation and reporting live in playlist_validate.sh.

# ── playlist_init ──────────────────────────────────────────────────────────
#
# Read PLAYLIST into PLAYLIST_LINES[], count actionable lines, resume position.

playlist_init() {
    PLAYLIST_LINES=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        PLAYLIST_LINES+=("$line")
    done < "$PLAYLIST"

    recount_playlist_total
    init_playlist_checksum
    init_injection_limit

    # Resume position from state, or start at 0
    playlist_line="${playlist_line:-0}"

    log "Playlist: ${C_BOLD}$PLAYLIST${C_RESET} ($playlist_total actionable lines, starting at line $playlist_line)"
}

# ── recount_playlist_total ────────────────────────────────────────────────
#
# Count actionable lines in PLAYLIST_LINES (not blank, not comments).
# Used by playlist_init and playlist_reload.

recount_playlist_total() {
    playlist_total=0
    for line in "${PLAYLIST_LINES[@]}"; do
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
        playlist_total=$((playlist_total + 1))
    done
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

        local trimmed="${raw#"${raw%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        playlist_line_model=""
        playlist_line_gate_tag=""
        playlist_line_gate_context=""
        if [[ "$trimmed" == ">"* ]]; then
            playlist_line_type="prompt"
            parse_playlist_prompt_line "$trimmed"
            parse_playlist_gate_tag || return 1
        else
            playlist_line_type="bead"
            playlist_current_line="$trimmed"
        fi

        # playlist_line is only updated by playlist_advance() on success.
        _playlist_pending_line=$scan_line
        return 0
    done
    return 1
}

# ── parse_playlist_prompt_line ─────────────────────────────────────────────
#
# Strip the leading > and optional @model prefix from a prompt line.
# Sets playlist_current_line (text) and playlist_line_model (empty or model name).
# Example: ">@opus Review changes" → model=opus, current="Review changes"

parse_playlist_prompt_line() {
    local trimmed="$1"
    playlist_current_line="${trimmed#>}"
    playlist_current_line="${playlist_current_line#"${playlist_current_line%%[![:space:]]*}"}"
    if [[ "$playlist_current_line" == @* ]]; then
        playlist_line_model="${playlist_current_line%% *}"
        playlist_line_model="${playlist_line_model#@}"
        playlist_current_line="${playlist_current_line#* }"
    fi
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
# In --dry-run mode, log and skip. Must call playlist_advance directly
# because save_state (where it normally runs) is skipped in dry-run.

playlist_handle_dry_run() {
    [[ "$DRY_RUN" != "true" ]] && return 1
    playlist_dry_run
    playlist_advance
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

    local prompt_text="$playlist_current_line"
    if [[ -n "$playlist_line_gate_tag" ]]; then
        prompt_text=$(gate_expand_tag "$playlist_line_gate_tag" "$playlist_line_gate_context")
    fi
    build_raw_prompt "$prompt_text"

    if ! invoke_claude; then
        [[ -n "$saved_model" ]] && MODEL="$saved_model"
        return 1
    fi

    [[ -n "$saved_model" ]] && MODEL="$saved_model"
    playlist_reload
    total_tasks_completed=$((total_tasks_completed + 1))
    no_progress_count=0
    if [[ "$circuit" == "HALF_OPEN" ]]; then
        circuit="CLOSED"
        log "Circuit recovered → CLOSED"
    fi
    current_task=""
}
