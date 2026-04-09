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

    # Per-invocation stream-json logs (diagnosis + replay)
    STREAM_LOG_DIR=".ralph/logs/stream"
    mkdir -p "$STREAM_LOG_DIR"
    INVOKE_LOG=""  # set per-invocation

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

    while [[ $attempt -le $MAX_RETRIES ]]; do
        _invoke_claude_once && return 0

        # All retries exhausted?
        if [[ $attempt -ge $MAX_RETRIES ]]; then
            log "ERROR: All $MAX_RETRIES attempts failed. Giving up."
            EXIT_REASON="Claude invocation failed after $MAX_RETRIES retries (exit $invoke_exit)"
            return 1
        fi

        log "WARNING: Attempt $attempt/$MAX_RETRIES failed (exit $invoke_exit). Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"

        augment_prompt_with_failure_context "$invoke_exit" "$attempt"
        attempt=$((attempt + 1))
    done
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

    log "  Stream log: $INVOKE_LOG"
    return 0
}

# ── augment_prompt_with_failure_context ────────────────────────────────────
#
# Append failure context to $prompt so the next attempt can adapt its approach.
# Maps exit codes to human-readable diagnoses with actionable guidance.

augment_prompt_with_failure_context() {
    local exit_code="$1"
    local attempt="$2"
    local diagnosis last_output

    diagnosis=$(diagnose_exit_code "$exit_code")
    last_output=$(extract_failure_tail)

    prompt="$prompt

## RETRY CONTEXT (attempt $((attempt + 1))/$MAX_RETRIES)
The previous attempt FAILED. Here is what happened:
* Exit code: $exit_code
* Diagnosis: $diagnosis

### Last output before failure
$last_output

IMPORTANT — adapt your approach:
* If the issue was a timeout: work in smaller steps, do less per invocation.
* If the issue was context overflow: produce shorter output, avoid large file reads.
* If the issue was an API error: this may be transient, try the same approach.
* If the issue was a tool error: try an alternative approach to achieve the same goal.
* Do NOT repeat the exact same sequence of actions that failed."
}

# ── extract_failure_tail ───────────────────────────────────────────────────
#
# Extract the last meaningful content from the raw stream-json log.
# Pulls the last few assistant text blocks and any error messages,
# giving the retry prompt concrete context about what happened.

extract_failure_tail() {
    if [[ ! -f "${INVOKE_LOG:-}" ]]; then
        echo "(no log available)"
        return
    fi

    # Extract the last assistant text blocks + any error/result events
    local tail_content
    tail_content=$(tail -50 "$INVOKE_LOG" | jq -r '
        if .type == "assistant" then
            (.message.content[]? |
                if .type == "text" then "TEXT: " + (.text | .[0:200])
                elif .type == "tool_use" then "TOOL: " + .name + " " + (.input | to_entries | map(.key + "=" + (.value | tostring | .[0:80])) | join(", "))
                else empty end)
        elif .type == "result" then
            "RESULT: " + (.result // "no result") + " (turns: " + (.num_turns | tostring) + ")"
        elif .type == "error" then
            "ERROR: " + (.error.message // .error // "unknown error")
        else empty end
    ' 2>/dev/null | tail -10)

    if [[ -z "$tail_content" ]]; then
        echo "(log exists but no parseable content — raw log: $INVOKE_LOG)"
    else
        echo "$tail_content"
    fi
}

# ── diagnose_exit_code ─────────────────────────────────────────────────────
#
# Map Claude CLI exit codes to human-readable failure reasons.

diagnose_exit_code() {
    local code="$1"
    case "$code" in
        124) echo "Timeout — invocation exceeded ${TIMEOUT_MINUTES}m limit" ;;
        137) echo "Killed (SIGKILL) — likely OOM or external signal" ;;
        1)   echo "General error — possibly API failure, auth issue, or tool crash" ;;
        2)   echo "Misuse — bad arguments or configuration" ;;
        *)   echo "Unknown failure (exit code $code)" ;;
    esac
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
