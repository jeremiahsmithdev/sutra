# invoke_retry.sh — Retry context injection and failure diagnostics.
#
# Used by invoke.sh's retry loop. Separated to keep invoke.sh focused on
# the inner-loop invocation itself.

# ── augment_prompt_with_failure_context ───────────────────────────────────
#
# Append retry context to $prompt so the next attempt can adapt its approach.
# The block itself lives in templates/retry_context.txt — this function
# just gathers the substitution values and renders the template.

augment_prompt_with_failure_context() {
    local exit_code="$1"
    local attempt="$2"
    local diagnosis last_output retry_block

    diagnosis=$(diagnose_exit_code "$exit_code")
    last_output=$(extract_failure_tail)

    retry_block=$(render_template "$TEMPLATES_DIR/retry_context.txt" \
        "ATTEMPT=$((attempt + 1))" \
        "MAX_RETRIES=$MAX_RETRIES" \
        "EXIT_CODE=$exit_code" \
        "DIAGNOSIS=$diagnosis" \
        "LAST_OUTPUT=$last_output")

    prompt="${prompt}${retry_block}"
}

# ── extract_failure_tail ──────────────────────────────────────────────────
#
# Extract the last meaningful content from the raw stream-json log.
# Uses templates/failure_tail.jq as the jq filter file so the multi-line
# expression isn't inline in shell code.

extract_failure_tail() {
    if [[ ! -f "${INVOKE_LOG:-}" ]]; then
        echo "(no log available)"
        return
    fi

    local tail_content
    tail_content=$(tail -50 "$INVOKE_LOG" \
        | jq -r -f "$TEMPLATES_DIR/failure_tail.jq" 2>/dev/null \
        | tail -10)

    if [[ -z "$tail_content" ]]; then
        echo "(log exists but no parseable content — raw log: $INVOKE_LOG)"
    else
        echo "$tail_content"
    fi
}

# ── diagnose_exit_code ────────────────────────────────────────────────────
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
