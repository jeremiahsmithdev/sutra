# glm.sh — GLM (z.ai) model integration.
#
# GLM models mimic Anthropic's API via environment variables:
#   ANTHROPIC_AUTH_TOKEN  — API key (from GLM_API_KEY env var)
#   ANTHROPIC_BASE_URL    — API endpoint
#   ANTHROPIC_MODEL       — Model name
#
# This module handles detection, setup, and teardown of GLM mode.

# Track whether GLM mode was activated (for cleanup)
_GLM_ACTIVE=""

# ── is_glm_model ───────────────────────────────────────────────────────────────
#
# Check if a model string is a GLM model (e.g., "glm-4.7", "glm-5").
# Returns 0 if GLM model, 1 otherwise.

is_glm_model() {
    local model="$1"
    [[ "$model" =~ ^glm-[0-9]+(\.[0-9]+)?$ ]]
}

# ── extract_glm_version ────────────────────────────────────────────────────────
#
# Extract the version number from a GLM model string.
#   "glm-4.7" → "4.7"
#   "glm-5"   → "5"
# Returns empty string if not a valid GLM model.

extract_glm_version() {
    local model="$1"
    [[ "$model" =~ ^glm-([0-9]+(\.[0-9]+)?)$ ]] && echo "${BASH_REMATCH[1]}"
}

# ── setup_glm_env ────────────────────────────────────────────────────────────
#
# Configure environment for GLM API invocation.
# Sets ANTHROPIC_AUTH_TOKEN, ANTHROPIC_BASE_URL, ANTHROPIC_MODEL.
# Aborts if GLM_API_KEY is not set in user environment.

setup_glm_env() {
    local version="$1"

    if [[ -z "${GLM_API_KEY:-}" ]]; then
        log "ERROR: GLM_API_KEY environment variable not set"
        log "  Required for GLM model usage. Set it in your shell profile:"
        log "  export GLM_API_KEY=\"your-api-key-here\""
        exit 1
    fi

    _GLM_ACTIVE="true"
    export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
    export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
    export ANTHROPIC_MODEL="glm-${version}"

    log "GLM mode enabled: glm-${version}"
}

# ── teardown_glm_env ───────────────────────────────────────────────────────────
#
# Unset GLM-specific environment variables to avoid affecting
# subsequent Claude invocations. Safe to call even if not active.

teardown_glm_env() {
    if [[ -n "$_GLM_ACTIVE" ]]; then
        unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL
        _GLM_ACTIVE=""
        log "GLM environment variables cleared"
    fi
}

# ── validate_glm_version ───────────────────────────────────────────────────────
#
# Validate that the extracted GLM version is non-empty.
# Returns 0 if valid, 1 if empty.

validate_glm_version() {
    local version="$1"
    [[ -n "$version" ]]
}

# ── detect_invalid_glm_pattern ────────────────────────────────────────────────────
#
# Detect if a model name looks like it was intended to be a GLM model
# but doesn't match the expected pattern (e.g., "glm-invalid").
# Returns 0 if likely invalid GLM pattern, 1 otherwise.

detect_invalid_glm_pattern() {
    local model="$1"
    # If it starts with "glm-" but is_glm_model() returns false, it's likely malformed
    [[ "$model" == glm-* ]] && ! is_glm_model "$model"
}
