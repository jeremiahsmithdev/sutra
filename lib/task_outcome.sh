# task_outcome.sh — Track loop counters and decide retry vs move on.
#
#   closed      → task done, increment counter, maybe close epic, pick next
#   open        → Claude released it (blocked), pick next
#   in_progress → not done, re-invoke on same task

handle_task_outcome() {
    local tid="$1"

    case "$bead_status" in

        closed)
            total_tasks_completed=$((total_tasks_completed + 1))
            log "Task ${C_BOLD_CYAN}$tid${C_RESET} ${C_BOLD_GREEN}complete${C_RESET}"
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

    # Get parent epic ID
    local parent_id
    parent_id=$(br show "$tid" --json 2>/dev/null \
        | jq -r '.[0].parent // empty' 2>/dev/null) || return
    [[ -z "$parent_id" ]] && return

    # Skip if epic is already closed
    local epic_status
    epic_status=$(br show "$parent_id" --json 2>/dev/null \
        | jq -r '.[0].status // empty' 2>/dev/null) || return
    [[ "$epic_status" == "closed" ]] && return

    # Count non-closed children of this epic via br show's dependents list.
    # Filter to parent-child relationships only (excludes blocks dependencies).
    local open_count
    open_count=$(br show "$parent_id" --json 2>/dev/null \
        | jq '[.[0].dependents // [] | .[] | select(.dependency_type == "parent-child") | select(.status != "closed")] | length' \
        2>/dev/null) || return

    if [[ "$open_count" -eq 0 ]]; then
        br close "$parent_id" 2>/dev/null
        log "Auto-closed epic ${C_BOLD_CYAN}$parent_id${C_RESET} (all children complete)"
    fi
}
