# invoke.sh — Claude Code invocation and bead status check.

# ── init_invoke ─────────────────────────────────────────────────────────────
#
# One-time setup: create temp file for Claude output, compute timeout.
# Called once during initialisation, not per-loop.

init_invoke() {
    TIMEOUT_SECS=$((TIMEOUT_MINUTES * 60))
}

# ── invoke_claude ───────────────────────────────────────────────────────────
#
# Runs Claude Code with the global $prompt. Uses $TIMEOUT_CMD to kill
# hung invocations. Returns 0 on success, 1 on failure.

invoke_claude() {
    show_prompt "$prompt"

    # Auto-commit any dirty .beads/ files so the working tree is clean.
    # The daemon writes to issues.jsonl continuously; uncommitted changes
    # block `git checkout` when Claude switches branches.
    commit_beads_if_dirty

    log "Invoking Claude Code (timeout: ${TIMEOUT_MINUTES}m)..."

    # Count this invocation and persist before calling Claude,
    # so a crash mid-invocation doesn't lose the loop count.
    total_loops=$((total_loops + 1))
    save_state

    # Build command prefix: timeout + optional bwrap sandbox.
    # `command` bypasses any shell aliases (e.g. claude aliased to claude --ide).
    local -a prefix=("$TIMEOUT_CMD" "${TIMEOUT_SECS}s")
    if [[ "$SANDBOX_MODE" == "true" ]]; then
        prefix+=(bwrap "${BWRAP_ARGS[@]}" --)
    fi

    invoke_exit=0
    "${prefix[@]}" command claude \
        -p "$prompt" \
        --dangerously-skip-permissions \
        --model haiku \
        --output-format stream-json \
        --max-turns 50 \
        --verbose \
        > >(format_stream) \
        || invoke_exit=$?

    if [[ $invoke_exit -ne 0 ]]; then
        log "ERROR: Claude invocation failed (exit code: $invoke_exit)"
        current_task=""
        EXIT_REASON="Claude invocation failed (exit $invoke_exit)"
        return 1
    fi

    return 0
}

# ── check_bead_status ───────────────────────────────────────────────────────
#
# Query beads for the current status of the task after Claude ran.
# Sets the global $bead_status variable to one of:
#   "closed"      — Claude completed and closed the task
#   "open"        — Claude released it (blocked)
#   "in_progress" — Claude made progress but didn't finish

check_bead_status() {
    local tid="$1"

    bead_status=$(bd show "$tid" --json 2>/dev/null \
        | jq -r '.[0].status // "unknown"' 2>/dev/null \
        || echo "unknown")

    local status_color="$C_RESET"
    case "$bead_status" in
        closed)      status_color="$C_BOLD_GREEN" ;;
        open)        status_color="$C_YELLOW" ;;
        in_progress) status_color="$C_YELLOW" ;;
        *)           status_color="$C_RED" ;;
    esac
    log "Claude finished. Bead status: ${status_color}${bead_status}${C_RESET}"
}
