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
# Ralph tracks its progress in a plain-text key=value file (.ralph/state).
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
    if [[ -f ".ralph_state" && ! -f ".ralph/state" ]]; then
        mkdir -p .ralph
        mv .ralph_state .ralph/state
        log "Migrated .ralph_state → .ralph/state"
    fi
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
    # playlist_advance() commits the pending line position — only called here,
    # so a crash mid-task means playlist_line stays at the unfinished line.
    if [[ -n "${PLAYLIST:-}" && "${DRY_RUN:-false}" != "true" ]]; then
        playlist_advance
        local playlist_state
        playlist_state=$(render_template "$TEMPLATES_DIR/state_playlist.txt" \
            "PLAYLIST_FILE=${PLAYLIST}" \
            "PLAYLIST_LINE=${playlist_line:-0}" \
            "INJECTED_BEAD_COUNT=${injected_bead_count:-0}" \
            "INJECTION_CAPPED=${INJECTION_CAPPED:-false}")
        printf '%s\n' "$playlist_state" >> "$STATE_FILE"
        playlist_write_progress
    fi
}

# ── render_template ───────────────────────────────────────────────────────
#
# Read a template file and substitute {{KEY}} placeholders with values.
# Usage: render_template <template_file> [KEY=value ...]
# Pure bash — no external deps. Handles multi-line values correctly.
render_template() {
    local template_file="$1"; shift
    local content pair key value
    content=$(<"$template_file")
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        content="${content//\{\{$key\}\}/$value}"
    done
    printf '%s' "$content"
}
