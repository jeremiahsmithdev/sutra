# invoke.sh — Claude Code invocation, retry logic, and bead status check.

# Maximum retry attempts before giving up on a failed invocation.
MAX_RETRIES=3
RETRY_DELAY=10

# ── init_invoke ─────────────────────────────────────────────────────────────
#
# One-time setup: create temp file for Claude output, compute timeout.
# Called once during initialisation, not per-loop.

init_invoke() {
    TIMEOUT_SECS=$((TIMEOUT_MINUTES * 60))
    CLAUDE_PID=""
    INVOKE_COUNT=0

    # Session name: <project>-<branch>-<timestamp>
    local project branch timestamp
    project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || echo "unknown")
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    timestamp=$(date +%Y%m%d-%H%M%S)
    SESSION_NAME="${project}-${branch}-${timestamp}"

    INVOKE_LOG=""  # set per-invocation

    # Skip filesystem setup in dry-run — no Claude invocations will occur.
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        STREAM_LOG_DIR=""
        SESSION_LOG="(dry-run)"
        return
    fi

    # Per-invocation stream-json logs (diagnosis + replay)
    STREAM_LOG_DIR=".ralph/logs/stream"
    mkdir -p "$STREAM_LOG_DIR"

    # Session log: full stdout+stderr capture
    SESSION_LOG_DIR=".ralph/logs/sessions"
    mkdir -p "$SESSION_LOG_DIR"
    SESSION_LOG="$SESSION_LOG_DIR/${SESSION_NAME}.log"
    exec > >(tee -a "$SESSION_LOG") 2>&1
}

# ── invoke_claude ───────────────────────────────────────────────────────────
#
# Runs Claude Code with the global $prompt, retrying up to MAX_RETRIES
# times on failure. Each retry augments the prompt with failure context
# (exit code diagnosis + tail of the raw log) so Claude can adapt.
# Returns 0 on success, 1 if all attempts fail.

invoke_claude() {
    local attempt=1
    local original_model="$MODEL"

    while [[ $attempt -le $MAX_RETRIES ]]; do
        _invoke_claude_once && { MODEL="$original_model"; return 0; }

        # All retries exhausted?
        if [[ $attempt -ge $MAX_RETRIES ]]; then
            log "ERROR: All $MAX_RETRIES attempts failed. Giving up."
            EXIT_REASON="Claude invocation failed after $MAX_RETRIES retries (exit $invoke_exit)"
            MODEL="$original_model"
            return 1
        fi

        log "WARNING: Attempt $attempt/$MAX_RETRIES failed (exit $invoke_exit). Retrying in ${RETRY_DELAY}s..."
        escalate_model "$original_model"
        sleep "$RETRY_DELAY"

        augment_prompt_with_failure_context "$invoke_exit" "$attempt"
        attempt=$((attempt + 1))
    done
}

# ── escalate_model ─────────────────────────────────────────────────────────
#
# Bump MODEL to the next capability tier. Chain: haiku→sonnet→opus→opus.
# No-op if AUTO_ESCALATE is false.

escalate_model() {
    local original="$1"
    [[ "$AUTO_ESCALATE" != "true" ]] && return

    local old="$MODEL"
    case "$MODEL" in
        *haiku*)  MODEL="sonnet" ;;
        *sonnet*) MODEL="opus" ;;
        *)        return ;;  # already at ceiling
    esac
    log "Escalating model: ${C_BOLD_YELLOW}$old → $MODEL${C_RESET}"
}

# ── _invoke_claude_once ────────────────────────────────────────────────────
#
# Single Claude Code invocation. Called by invoke_claude's retry loop.
# Sets invoke_exit on failure. Returns 0 on success, 1 on failure.

_invoke_claude_once() {
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

    # Log file for this invocation's raw stream-json output
    INVOKE_COUNT=$((INVOKE_COUNT + 1))
    INVOKE_LOG="$STREAM_LOG_DIR/${SESSION_NAME}-$(printf '%03d' $INVOKE_COUNT).jsonl"

    invoke_exit=0
    "${prefix[@]}" command claude \
        -p "$prompt" \
        --dangerously-skip-permissions \
        --model "$MODEL" \
        --output-format stream-json \
        --max-turns "$MAX_TURNS" \
        --verbose \
        > >(tee "$INVOKE_LOG" | format_stream) &
    CLAUDE_PID=$!
    wait "$CLAUDE_PID" 2>/dev/null || invoke_exit=$?
    CLAUDE_PID=""

    if [[ $invoke_exit -ne 0 ]]; then
        log "ERROR: Claude invocation failed (exit code: $invoke_exit)"
        log "  Raw log: $INVOKE_LOG"
        current_task=""
        return 1
    fi

    accumulate_cost
    log "  Stream log: $INVOKE_LOG"
    return 0
}

# ── accumulate_cost ────────────────────────────────────────────────────────
#
# Parse cost from the result entry and add to running total.

accumulate_cost() {
    local cost
    cost=$(tail -5 "$INVOKE_LOG" | jq -r 'select(.type=="result") | .total_cost_usd // 0' 2>/dev/null)
    [[ -z "$cost" || "$cost" == "null" ]] && cost=0
    total_cost_usd=$(awk "BEGIN {printf \"%.2f\", ${total_cost_usd:-0} + $cost}")
}

# Retry context injection, failure tail extraction, and exit code diagnosis
# live in invoke_retry.sh — sourced by loader.sh immediately after this file.

# ── check_bead_status ───────────────────────────────────────────────────────
#
# Query beads for the current status of the task after Claude ran.
# Sets the global $bead_status variable to one of:
#   "closed"      — Claude completed and closed the task
#   "open"        — Claude released it (blocked)
#   "in_progress" — Claude made progress but didn't finish

check_bead_status() {
    local tid="$1"

    bead_status=$(get_bead_status "$tid")

    local status_color="$C_RESET"
    case "$bead_status" in
        closed)      status_color="$C_BOLD_GREEN" ;;
        open)        status_color="$C_YELLOW" ;;
        in_progress) status_color="$C_YELLOW" ;;
        *)           status_color="$C_RED" ;;
    esac
    log "Claude finished. Bead status: ${status_color}${bead_status}${C_RESET}"
}
