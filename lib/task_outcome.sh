# task_outcome.sh — Track loop counters and decide retry vs move on.
#
#   closed      → task done, increment counter, maybe close epic, pick next
#   open        → Claude released it (blocked), pick next
#   in_progress → not done, re-invoke on same task

# Cross-bead context handoff globals — populated when a bead closes,
# consumed and cleared when the next bead's prompt is built.
LAST_TASK_SUMMARY=""
LAST_TASK_ID=""

# ── check_bead_status ───────────────────────────────────────────────────────
#
# Query beads for the task's post-invocation status. Normalises transient
# DONE state (br close --suggest-next race) to closed.

check_bead_status() {
    local tid="$1"
    bead_status=$(get_bead_status "$tid")

    if [[ "${bead_status,,}" == "done" ]]; then
        log "Bead ${C_BOLD_CYAN}$tid${C_RESET} in transient DONE state — rolling forward to closed"
        br close "$tid" --reason "Auto-rolled forward from DONE state" 2>/dev/null || true
        bead_status="closed"
    fi

    local status_color="$C_RESET"
    case "$bead_status" in
        closed)      status_color="$C_BOLD_GREEN" ;;
        open)        status_color="$C_YELLOW" ;;
        in_progress) status_color="$C_YELLOW" ;;
        *)           status_color="$C_RED" ;;
    esac
    log "Claude finished. Bead status: ${status_color}${bead_status}${C_RESET}"
}

handle_task_outcome() {
    local tid="$1"

    case "$bead_status" in

        closed)
            total_tasks_completed=$((total_tasks_completed + 1))
            log "Task ${C_BOLD_CYAN}$tid${C_RESET} ${C_BOLD_GREEN}complete${C_RESET}"
            capture_task_handoff "$tid"
            mark_needs_review "$tid"
            maybe_close_epic "$tid"
            current_task=""
            ;;

        open)
            log "Task ${C_BOLD_CYAN}$tid${C_RESET} ${C_YELLOW}released (blocked). Skipping.${C_RESET}"
            current_task=""
            ;;

        in_progress)
            log "Task ${C_BOLD_CYAN}$tid${C_RESET} ${C_YELLOW}still in progress. Re-invoking...${C_RESET}"
            ;;

        *)
            log "WARNING: Unexpected bead status '$bead_status'. Moving on."
            current_task=""
            ;;
    esac
}

# ── capture_task_handoff ──────────────────────────────────────────────────
#
# After a bead closes, capture the last assistant text block from the
# just-finished invocation's stream log into LAST_TASK_SUMMARY / LAST_TASK_ID.
# The next prompt build renders a "## Prior Task Context" section from these,
# so the next agent sees what the previous one claimed it did.

capture_task_handoff() {
    local tid="$1"
    LAST_TASK_ID="$tid"
    LAST_TASK_SUMMARY=$(extract_last_assistant_text "${INVOKE_LOG:-}")
}

# ── capture_prompt_handoff ────────────────────────────────────────────────
#
# Mirror of capture_task_handoff for `>` prompt and gate lines. Prompt
# items have no bead, so we tag the handoff with a descriptive label
# instead of an ID. The next prompt build renders it into "## Prior Task
# Context" exactly the same way.

capture_prompt_handoff() {
    local label="${1:-prompt}"
    LAST_TASK_ID="$label"
    LAST_TASK_SUMMARY=$(extract_last_assistant_text "${INVOKE_LOG:-}")
}

# ── extract_last_assistant_text ───────────────────────────────────────────
#
# Read a stream-json log and return the last assistant text block in full.
# render_template handles multi-line values cleanly, so paragraph/code-block
# structure flows through into the next prompt's "## Prior Task Context".
# Returns empty string if the log is missing, empty, or has no text blocks.
# Never fails loudly — the handoff is best-effort, not load-bearing.

extract_last_assistant_text() {
    local log_path="$1"
    [[ -f "$log_path" ]] || { echo ""; return; }

    local text
    text=$(jq -rs -f "$TEMPLATES_DIR/last_assistant_text.jq" < "$log_path" 2>/dev/null)
    [[ -z "$text" || "$text" == "null" ]] && { echo ""; return; }

    printf '%s' "$text"
}

# ── mark_needs_review ──────────────────────────────────────────────────
#
# After a task is closed by Claude, label it for human verification.
# Uses a label instead of br set-state to avoid spawning event child beads.
# The close --reason from Claude contains verification notes;
# the label lets the harvest workflow filter for unreviewed work.

mark_needs_review() {
    local tid="$1"
    br label add "$tid" verified:needs-review 2>/dev/null || true
}

# ── maybe_close_epic ────────────────────────────────────────────────────
#
# After a task is closed, check if its parent epic has all children done.
# If so, close the epic automatically. This unblocks dependent epics.

maybe_close_epic() {
    local tid="$1"

    local parent_id
    parent_id=$(get_bead_field "$tid" parent)
    [[ -z "$parent_id" ]] && return

    [[ "$(get_bead_status "$parent_id")" == "closed" ]] && return

    local open_count
    open_count=$(count_open_epic_children "$parent_id") || return

    if [[ "$open_count" -eq 0 ]]; then
        br close "$parent_id" 2>/dev/null
        log "Auto-closed epic ${C_BOLD_CYAN}$parent_id${C_RESET} (all children complete)"
    fi
}
