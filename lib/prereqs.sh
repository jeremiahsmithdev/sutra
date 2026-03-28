# prereqs.sh — Prerequisite checks before the loop can start.
#
# Verifies that all required CLI tools are installed and that the
# current directory is a beads-enabled project. Exits with a clear
# error message if anything is missing.

check_prereqs() {
    local missing=0

    # Check for required CLI tools
    for cmd in jq br claude; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR: Required: $cmd"
            missing=1
        fi
    done

    # GNU timeout is needed to kill hung Claude invocations.
    # On macOS it's installed as gtimeout via `brew install coreutils`.
    TIMEOUT_CMD=$(command -v gtimeout 2>/dev/null || command -v timeout 2>/dev/null || true)
    if [[ -z "$TIMEOUT_CMD" ]]; then
        log "ERROR: gtimeout or timeout required (brew install coreutils)"
        missing=1
    fi

    # Ralph only works inside a beads-tracked project
    if [[ ! -d ".beads" ]]; then
        log "ERROR: No .beads/ in $(pwd)"
        missing=1
    fi

    # Bubblewrap is only available on Linux.
    if [[ "$SANDBOX_MODE" == "true" ]]; then
        if [[ "$(uname -s)" != "Linux" ]]; then
            log "WARNING: --sandbox requires Linux (bwrap unavailable on $(uname -s)), disabling"
            SANDBOX_MODE=false
        elif ! command -v bwrap &>/dev/null; then
            log "ERROR: --sandbox requires bwrap (apt install bubblewrap)"
            missing=1
        fi
    fi

    if [[ $missing -eq 1 ]]; then
        exit 1
    fi

    # Ensure "event" issue type is configured for br.
    # Only log when we actually need to add it (not every startup).
    if ! br config get types.custom 2>/dev/null | grep -q "event"; then
        br config set types.custom "event" 2>/dev/null || true
    fi
}

# ── ensure_ralph_branch ───────────────────────────────────────────────────
#
# Ensure the dedicated "ralph" working branch exists and is checked out.
# Creates it from WORKING_BRANCH (set in .ralph.conf) or the current branch.

ensure_ralph_branch() {
    if git rev-parse --verify ralph &>/dev/null; then
        git checkout ralph 2>/dev/null || {
            log "ERROR: Could not switch to ralph branch"
            exit 1
        }
        log "On branch: ${C_BOLD_CYAN}ralph${C_RESET}"
    else
        local base="${WORKING_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
        log "Creating branch ${C_BOLD_CYAN}ralph${C_RESET} from ${C_CYAN}$base${C_RESET}..."
        git checkout -b ralph "$base" 2>/dev/null || {
            log "ERROR: Could not create ralph branch from $base"
            exit 1
        }
        log "Created and switched to branch: ${C_BOLD_CYAN}ralph${C_RESET}"
    fi
}
