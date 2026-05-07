# queue.sh — Sequential playlist execution from a queue file.
#
# read_queue_file parses lines into QUEUE_ENTRIES[]; run_queue spawns a
# child ralph for each entry. Each child gets a clean session, branch,
# log dir, and completion report.

# Initialise so callers under `set -u` can expand the array safely
# even when --queue runs without forwarded args.
FORWARDED_QUEUE_ARGS=()

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
# Verify the working tree is clean before moving to the next queue
# entry. Each playlist's commits must stay attributable to its branch.

ensure_clean_tree() {
    local just_finished="$1"
    local dirty
    dirty=$(git status --porcelain 2>/dev/null)
    [[ -z "$dirty" ]] && return 0
    local first_file
    first_file=$(printf '%s\n' "$dirty" | head -1 | awk '{print $NF}')
    log "ERROR: Working tree dirty after playlist '$just_finished': $first_file"
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
    if (( i < total - 1 )); then
        ensure_clean_tree "$entry" || return 1
    fi
}

# ── run_queue ──────────────────────────────────────────────────────────────
#
# Walk QUEUE_ENTRIES, spawning one child ralph per entry. Halt on any
# non-zero child exit or any dirty tree between entries.

run_queue() {
    read_queue_file        || return 1
    require_queue_nonempty || return 1
    log "=== Queue: $QUEUE_FILE (${#QUEUE_ENTRIES[@]} entries) ==="
    local i
    for ((i = 0; i < ${#QUEUE_ENTRIES[@]}; i++)); do
        run_queue_entry "$i" || return 1
    done
    log "=== Queue complete: ${#QUEUE_ENTRIES[@]} entries ==="
}
