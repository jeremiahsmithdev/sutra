# queue.sh — Sequential playlist execution from a queue file.
#
# read_queue_file parses lines into QUEUE_ENTRIES[]; run_queue spawns a
# child ralph for each entry. Each child gets a clean session, branch,
# log dir, and completion report.

# Initialise so callers under `set -u` can expand the array safely
# even when --queue runs without forwarded args.
FORWARDED_QUEUE_ARGS=()

# queue_index — index of the next queue entry to run. Persisted in
# .ralph/state alongside playlist progress so an interrupted queue
# resumes where it stopped instead of restarting at entry 0.
queue_index=0

# ── read_queue_file ────────────────────────────────────────────────────────
#
# Read QUEUE_FILE into QUEUE_ENTRIES[]. Comments and blank lines are
# skipped. Lines beginning with "--" are kept verbatim (forwarded raw
# as ralph args); other lines are treated as playlist paths.

read_queue_file() {
    QUEUE_ENTRIES=()
    if [[ ! -f "$QUEUE_FILE" ]]; then
        log "ERROR: Queue file not found: $QUEUE_FILE"
        return 1
    fi
    local line trimmed
    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
        QUEUE_ENTRIES+=("$trimmed")
    done < "$QUEUE_FILE"
}

# ── require_queue_nonempty ─────────────────────────────────────────────────

require_queue_nonempty() {
    [[ ${#QUEUE_ENTRIES[@]} -gt 0 ]] && return 0
    log "ERROR: No entries in queue: $QUEUE_FILE"
    return 1
}

# ── queue_entry_args ───────────────────────────────────────────────────────
#
# Resolve a queue entry to argv for a child ralph invocation.
# "--"-prefixed lines split into raw args; bare paths become
# "--playlist <path>".

queue_entry_args() {
    local entry="$1"
    if [[ "$entry" == --* ]]; then
        # shellcheck disable=SC2206
        QUEUE_CHILD_ARGS=($entry)
    else
        QUEUE_CHILD_ARGS=(--playlist "$entry")
    fi
}

# ── spawn_queue_child ──────────────────────────────────────────────────────

spawn_queue_child() {
    "$SCRIPT_DIR/ralph" "${QUEUE_CHILD_ARGS[@]}" "${FORWARDED_QUEUE_ARGS[@]}"
}

# ── ensure_clean_tree ──────────────────────────────────────────────────────
#
# Verify no tracked-file changes remain before moving to the next queue
# entry. Untracked files are ignored — they can't be the playlist's
# uncommitted work, only stray runtime files (lockfiles, logs, etc.).
# Each playlist's commits must stay attributable to its branch.

ensure_clean_tree() {
    local just_finished="$1"
    local dirty
    dirty=$(git status --porcelain --untracked-files=no 2>/dev/null)
    [[ -z "$dirty" ]] && return 0
    local first_file
    first_file=$(printf '%s\n' "$dirty" | head -1 | awk '{print $NF}')
    log "ERROR: Tracked file uncommitted after playlist '$just_finished': $first_file"
    log "Each queue entry must produce committed work only. Halting."
    return 1
}

# ── run_queue_entry ────────────────────────────────────────────────────────

run_queue_entry() {
    local i="$1"
    local entry="${QUEUE_ENTRIES[$i]}"
    local total="${#QUEUE_ENTRIES[@]}"
    log "── Queue $((i + 1))/$total: $entry"
    queue_entry_args "$entry"
    if ! spawn_queue_child; then
        log "ERROR: Child ralph failed on entry: $entry"
        return 1
    fi
    queue_index=$((i + 1))
    save_state
    if (( i < total - 1 )); then
        ensure_clean_tree "$entry" || return 1
    fi
}

# ── run_queue ──────────────────────────────────────────────────────────────
#
# Walk QUEUE_ENTRIES, spawning one child ralph per entry. Halt on any
# non-zero child exit or any dirty tree between entries. Resumes from
# queue_index in .ralph/state when --queue points at the same file as
# the previous run.

run_queue() {
    read_queue_file        || return 1
    require_queue_nonempty || return 1
    load_state
    local total="${#QUEUE_ENTRIES[@]}"
    local start="${queue_index:-0}"
    if (( start >= total )); then
        log "Queue $QUEUE_FILE already complete (index $start of $total). Use --reset to rerun."
        queue_index=0
        save_state
        return 0
    fi
    if (( start > 0 )); then
        log "=== Queue: $QUEUE_FILE — resuming at entry $((start + 1))/$total ==="
    else
        log "=== Queue: $QUEUE_FILE ($total entries) ==="
    fi
    local i
    for ((i = start; i < total; i++)); do
        run_queue_entry "$i" || return 1
    done
    queue_index=0
    save_state
    log "=== Queue complete: $total entries ==="
}
