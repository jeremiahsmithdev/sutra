# utils.sh — Logging, state persistence, and small helpers.
#
# Provides the core utilities that every other component depends on:
#   log()         — timestamped console output with auto-coloring
#   load_state()  — read circuit breaker + progress from disk
#   save_state()  — write circuit breaker + progress to disk

# ── ANSI colors ───────────────────────────────────────────────────────────
#
# Shared palette used by log(), format_stream, prompt display, etc.
# Named for semantics, not raw colors, so the palette is easy to change.

C_RESET=$'\033[0m'
C_DIM=$'\033[2m'
C_BOLD=$'\033[1m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'
C_MAGENTA=$'\033[35m'
C_BOLD_CYAN=$'\033[1;36m'
C_BOLD_GREEN=$'\033[1;32m'
C_BOLD_RED=$'\033[1;31m'
C_BOLD_YELLOW=$'\033[1;33m'
C_BOLD_MAGENTA=$'\033[1;35m'

# ── Logging ───────────────────────────────────────────────────────────────

# Print a timestamped message to stdout with automatic coloring.
# ERROR: → red, WARNING: → yellow, success keywords → green.
log() {
    local ts="${C_DIM}[ralph $(date +%H:%M:%S)]${C_RESET}"
    local msg="$*"

    case "$msg" in
        ERROR:*|"ERROR "*)
            printf '%s %s%s%s\n' "$ts" "$C_BOLD_RED" "$msg" "$C_RESET" ;;
        WARNING:*|"WARNING "*)
            printf '%s %s%s%s\n' "$ts" "$C_BOLD_YELLOW" "$msg" "$C_RESET" ;;
        *complete*|*"Complete"*|*recovered*|*"Auto-closed"*)
            printf '%s %s%s%s\n' "$ts" "$C_GREEN" "$msg" "$C_RESET" ;;
        "=== "*)
            printf '%s %s%s%s\n' "$ts" "$C_BOLD_CYAN" "$msg" "$C_RESET" ;;
        *)
            printf '%s %s\n' "$ts" "$msg" ;;
    esac
}

# ── Prompt display ────────────────────────────────────────────────────────
#
# Pretty-print the prompt sent to Claude. Highlights markdown headers,
# backtick code, and task metadata for easy scanning.

show_prompt() {
    local line
    printf '%s\n' "${C_DIM}┌─── Prompt ────────────────────────────────────────────┐${C_RESET}"
    while IFS= read -r line; do
        case "$line" in
            "## "*)
                printf '%s│%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD_MAGENTA" "$line" "$C_RESET" ;;
            "ID: "*)
                printf '%s│%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD_CYAN" "$line" "$C_RESET" ;;
            "Title: "*|"Description: "*)
                printf '%s│%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_CYAN" "$line" "$C_RESET" ;;
            "  git "*)
                printf '%s│%s   %s%s%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$line" "$C_RESET" ;;
            [0-9]". "*)
                printf '%s│%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_YELLOW" "$line" "$C_RESET" ;;
            "")
                printf '%s│%s\n' "$C_DIM" "$C_RESET" ;;
            *)
                printf '%s│%s %s\n' "$C_DIM" "$C_RESET" "$line" ;;
        esac
    done <<< "$1"
    printf '%s└───────────────────────────────────────────────────────┘%s\n' "$C_DIM" "$C_RESET"
}

# ── State persistence ─────────────────────────────────────────────────────
#
# Ralph tracks its progress in a plain-text key=value file (.sutra/state).
# This lets it survive restarts and lets --status and --reset inspect or
# clear state without running the loop.
#
# ── Beads housekeeping ───────────────────────────────────────────────
#
# br auto-flushes its SQLite DB to .beads/issues.jsonl on most commands.
# If that file is git-tracked, it creates dirty working-tree state
# that blocks `git checkout`. Auto-commit it before each invocation
# so Claude always starts with a clean tree.

migrate_state_file() {
    if [[ -f ".sutra_state" && ! -f ".sutra/state" ]]; then
        mkdir -p .sutra
        mv .sutra_state .sutra/state
        log "Migrated .sutra_state → .sutra/state"
    fi
}

# ── ralph self-provenance ─────────────────────────────────────────────────
#
# Record which ralph commit produced this session, so harvest can tell
# whether a finding from an old run is already fixed in current ralph.
# `--dirty` flags uncommitted edits — the recorded hash lies otherwise.

sutra_version_string() {
    local repo
    repo="$(dirname "$LIB_DIR")"
    git -C "$repo" describe --tags --always --dirty 2>/dev/null \
        || echo "unknown"
}

ralph_provenance_block() {
    local repo branch
    repo="$(dirname "$LIB_DIR")"
    branch="$(git -C "$repo" branch --show-current 2>/dev/null || echo "?")"
    cat <<EOF
# === ralph session ===
# ralph:    $(sutra_version_string) (branch: $branch)
# invoked:  ralph ${SUTRA_INVOKED_AS:-}
# model:    ${MODEL:-haiku}
# playlist: ${PLAYLIST:-(none)}
# dev port: ${SUTRA_DEV_PORT:-(unset)}
# started:  $(date -u +%Y-%m-%dT%H:%M:%SZ)
# =====================
EOF
}

commit_beads_if_dirty() {
    if git diff --quiet .beads/ 2>/dev/null && git diff --cached --quiet .beads/ 2>/dev/null; then
        return   # nothing dirty
    fi
    git add .beads/ 2>/dev/null
    git commit --no-verify -m "chore(ralph): sync beads state" .beads/ 2>/dev/null || true
}

# Read state from disk, or initialise defaults if no state file exists.
load_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$STATE_FILE"
    else
        # First run — set safe defaults
        circuit="CLOSED"
        no_progress_count=0
        total_tasks_completed=0
        total_loops=0
        current_task=""
    fi

    # Playlist resume: if state has a playlist_file that doesn't match current
    # --playlist arg, warn and reset position.
    if [[ -n "${PLAYLIST:-}" && -n "${playlist_file:-}" ]]; then
        if [[ "$playlist_file" != "$PLAYLIST" ]]; then
            log "WARNING: State file has playlist_file=$playlist_file but --playlist is $PLAYLIST. Resetting position."
            playlist_line=0
        fi
    fi

    # Queue resume: if state has a queue_file that doesn't match current
    # --queue arg, warn and reset index. Otherwise queue_index from disk
    # is preserved so an interrupted queue picks up where it stopped.
    if [[ -n "${QUEUE_FILE:-}" && -n "${queue_file:-}" ]]; then
        if [[ "$queue_file" != "$QUEUE_FILE" ]]; then
            log "WARNING: State file has queue_file=$queue_file but --queue is $QUEUE_FILE. Resetting index."
            queue_index=0
        fi
    fi

    # Always reset session counters — each `ralph` invocation is a new session.
    # Use local time with RFC3339 offset to match beads' closed_at format.
    # BSD date gives +0530; sed inserts the colon for RFC3339 (+05:30).
    session_start=$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')
    total_loops=0
    total_tasks_completed=0
    save_state
}

# Write current state variables to disk.
# Called after every meaningful state change so a crash doesn't lose progress.
# Uses templates/state.txt and templates/state_playlist.txt for persistence.
# No-op during --dry-run to preserve read-only guarantee.
save_state() {
    [[ "${DRY_RUN:-false}" == "true" ]] && return

    # Preserve queue state if we're a queue child (no QUEUE_FILE set) so
    # child playlist save_state cycles don't wipe the parent's queue
    # progress. When we ARE the queue parent, fresh state is written below.
    local preserved_queue=""
    if [[ -z "${QUEUE_FILE:-}" && -f "$STATE_FILE" ]]; then
        preserved_queue=$(grep -E '^(queue_file|queue_index|queue_log)=' "$STATE_FILE" 2>/dev/null || true)
    fi

    # Preserve playlist state if we're not in playlist mode (e.g. queue
    # parent has PLAYLIST empty) so the parent's save cycles don't wipe
    # the child playlist's progress lines from disk.
    local preserved_playlist=""
    if [[ -z "${PLAYLIST:-}" && -f "$STATE_FILE" ]]; then
        preserved_playlist=$(grep -E '^(playlist_file|playlist_line|injected_bead_count|INJECTION_CAPPED)=' "$STATE_FILE" 2>/dev/null || true)
    fi

    local state_content
    state_content=$(render_template "$TEMPLATES_DIR/state.txt" \
        "CIRCUIT=${circuit:-CLOSED}" \
        "NO_PROGRESS_COUNT=${no_progress_count:-0}" \
        "TOTAL_TASKS_COMPLETED=${total_tasks_completed:-0}" \
        "TOTAL_LOOPS=${total_loops:-0}" \
        "CURRENT_TASK=${current_task:-}" \
        "SESSION_START=${session_start:-}" \
        "MODEL=${MODEL:-haiku}" \
        "MAX_LOOPS=${MAX_LOOPS:-50}" \
        "TOTAL_COST_USD=${total_cost_usd:-0.00}")
    printf '%s\n' "$state_content" > "$STATE_FILE"

    # Append playlist state when in playlist mode (skip during dry-run).
    # playlist_advance() commits the pending line position.  It is only allowed
    # when _invocation_succeeded=true, which _invoke_claude_once sets after a
    # successful Claude exit.  The pre-invocation save_state call (which
    # persists total_loops for crash recovery) clears the flag beforehand, so
    # the pointer does NOT advance on that write.  After advancing, the flag is
    # reset so subsequent save_state calls in the same iteration are no-ops.
    if [[ -n "${PLAYLIST:-}" && "${DRY_RUN:-false}" != "true" ]]; then
        if [[ "${_invocation_succeeded:-false}" == "true" ]]; then
            playlist_advance
            _invocation_succeeded=false
        fi
        local playlist_state
        playlist_state=$(render_template "$TEMPLATES_DIR/state_playlist.txt" \
            "PLAYLIST_FILE=${PLAYLIST}" \
            "PLAYLIST_LINE=${playlist_line:-0}" \
            "INJECTED_BEAD_COUNT=${injected_bead_count:-0}" \
            "INJECTION_CAPPED=${INJECTION_CAPPED:-false}")
        printf '%s\n' "$playlist_state" >> "$STATE_FILE"
        playlist_write_progress
    elif [[ -n "$preserved_playlist" ]]; then
        printf '%s\n' "$preserved_playlist" >> "$STATE_FILE"
    fi

    # Queue state — written by the queue parent; preserved verbatim when
    # called from a child playlist process (no QUEUE_FILE set).
    if [[ -n "${QUEUE_FILE:-}" ]]; then
        local queue_state
        queue_state=$(render_template "$TEMPLATES_DIR/state_queue.txt" \
            "QUEUE_FILE=${QUEUE_FILE}" \
            "QUEUE_INDEX=${queue_index:-0}" \
            "QUEUE_LOG=${QUEUE_LOG:-}")
        printf '%s\n' "$queue_state" >> "$STATE_FILE"
    elif [[ -n "$preserved_queue" ]]; then
        printf '%s\n' "$preserved_queue" >> "$STATE_FILE"
    fi
}

# ── render_template ───────────────────────────────────────────────────────
#
# Read a template file and substitute {{KEY}} placeholders with values.
# Usage: render_template <template_file> [KEY=value ...]
# Pure bash — no external deps. Handles multi-line values correctly.
#
# Values are sentinel-escaped before substitution so that any {{...}} tokens
# inside a value (e.g. bead titles, task descriptions, playlist progress)
# are not treated as template placeholders in subsequent iterations.
# This prevents external content from leaking unfilled placeholder names
# into the rendered output.
render_template() {
    local template_file="$1"; shift
    local content pair key value _safe_value
    local _sentinel_brace=$'\x01\x01'
    local _sentinel_amp=$'\x02\x02'
    content=$(<"$template_file")
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        # Escape {{ so injected tokens are not re-expanded as placeholders.
        # Escape & because bash's ${var//pat/repl} treats & in the
        # replacement as a back-reference to the matched pattern.
        _safe_value="${value//\{\{/$_sentinel_brace}"
        _safe_value="${_safe_value//&/$_sentinel_amp}"
        content="${content//\{\{$key\}\}/$_safe_value}"
    done
    content="${content//$_sentinel_brace/\{\{}"
    # \& escapes the back-reference so it lands as a literal '&' in the output.
    content="${content//$_sentinel_amp/\&}"
    printf '%s' "$content"
}
