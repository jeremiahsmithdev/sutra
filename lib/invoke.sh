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

    # Capture HEAD at session start so gate templates can scope their git diffs.
    # Exported so Claude sub-processes receive it as $SESSION_START_SHA.
    SESSION_START_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
    export SESSION_START_SHA

    # Session name: <project>-<branch>-<timestamp>
    local project branch timestamp
    project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || echo "unknown")
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    timestamp=$(date +%Y%m%d-%H%M%S)
    SESSION_NAME="${project}-${branch}-${timestamp}"

    _invocation_succeeded=false
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

    # Session log: full stdout+stderr capture (ANSI codes stripped for plain text)
    SESSION_LOG_DIR=".ralph/logs/sessions"
    mkdir -p "$SESSION_LOG_DIR"
    SESSION_LOG="$SESSION_LOG_DIR/${SESSION_NAME}.log"
    ralph_provenance_block > "$SESSION_LOG"
    printf '\n' >> "$SESSION_LOG"
    # Output to terminal with colors, log file with ANSI codes stripped
    # tee writes to both the terminal (colored) and a pipe that strips codes for the log
    exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$SESSION_LOG")) 2>&1
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

        # Check if usage limit is hit and wait for reset
        wait_for_quota

        log "WARNING: Attempt $attempt/$MAX_RETRIES failed (exit $invoke_exit). Retrying in ${RETRY_DELAY}s..."
        escalate_model "$original_model"
        sleep "$RETRY_DELAY"

        augment_prompt_with_failure_context "$invoke_exit" "$attempt"
        attempt=$((attempt + 1))
    done
}

# ── invoke_claude_no_retry ─────────────────────────────────────────────────
#
# Fire-and-forget variant: one attempt only, no quota wait, no retry loop.
# Use for non-load-bearing invocations (e.g. completion reports) where
# burning budget on futile retries is worse than skipping the output.

invoke_claude_no_retry() {
    local _saved_max_retries="$MAX_RETRIES"
    MAX_RETRIES=1
    invoke_claude
    local _rc=$?
    MAX_RETRIES="$_saved_max_retries"
    return $_rc
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

    # Standard mode only: Claude switches branches per-task, so .beads/
    # must be clean before invocation. In playlist mode (one branch per
    # session) we leave .beads/ dirty so commit_bead_work can bundle it
    # with the feature commit instead of producing a standalone chore commit.
    if [[ "$AUTO_COMMIT" == "true" ]]; then
        commit_beads_if_dirty
    fi

    log "Invoking Claude Code (timeout: ${TIMEOUT_MINUTES}m)..."

    # Count this invocation and persist before calling Claude,
    # so a crash mid-invocation doesn't lose the loop count.
    # _invocation_succeeded is cleared here so save_state's playlist_advance
    # guard does NOT fire on this pre-invocation write — the pointer must
    # only advance after Claude exits successfully (see utils.sh:save_state).
    _invocation_succeeded=false
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

    # Signal success so the next save_state call may advance the playlist pointer.
    _invocation_succeeded=true
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


# Retry logic lives in invoke_retry.sh; bead status checking in task_outcome.sh.
