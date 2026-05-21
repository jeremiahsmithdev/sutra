# queue.sh — Sequential playlist execution from a queue file.
#
# read_queue_file parses lines into QUEUE_ENTRIES[]; run_queue spawns a
# child ralph for each entry. Each child gets a clean session, branch,
# log dir, and completion report.

# Initialise so callers under `set -u` can expand the array safely
# even when --queue runs without forwarded args.
FORWARDED_QUEUE_ARGS=()

# queue_index — index of the next queue entry to run. Persisted in
# .sutra/state alongside playlist progress so an interrupted queue
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
# Tidy the working tree before moving to the next queue entry. Untracked
# files are ignored. Dirty .beads/ state is auto-committed as a chore —
# bead bookkeeping shouldn't halt the queue. Other tracked-file changes
# are reported but do NOT halt: the next entry's Orientation flow will
# either fold them into its own commit or commit as separate cleanup.

ensure_clean_tree() {
    local just_finished="$1"
    commit_beads_if_dirty
    local dirty
    dirty=$(git status --porcelain --untracked-files=no 2>/dev/null)
    [[ -z "$dirty" ]] && return 0
    log "WARNING: Tracked changes uncommitted after playlist '$just_finished':"
    printf '%s\n' "$dirty" | head -5 | while IFS= read -r dirty_line; do
        log "  $dirty_line"
    done
    log "Continuing — next entry's Orientation will absorb leftovers."
    return 0
}

# ── run_queue_entry ────────────────────────────────────────────────────────

run_queue_entry() {
    local i="$1"
    local entry="${QUEUE_ENTRIES[$i]}"
    local total="${#QUEUE_ENTRIES[@]}"
    log "── Queue $((i + 1))/$total: $entry"
    queue_entry_args "$entry"
    queue_log_entry_start "$i" "$total" "$entry"
    local child_status=0
    spawn_queue_child || child_status=$?
    queue_log_entry_finish "$entry" "$child_status"
    if (( child_status != 0 )); then
        log "ERROR: Child ralph failed on entry: $entry"
        return 1
    fi
    queue_index=$((i + 1))
    save_state
    if (( i < total - 1 )); then
        ensure_clean_tree "$entry" || return 1
        maybe_reload_ralph
    fi
}

# ── maybe_reload_ralph ─────────────────────────────────────────────────────
#
# When --auto-reload is set, compare ralph's source SHA against the SHA
# captured at startup. If different, exec the new ralph binary with the
# original argv. Queue state is already persisted to disk; the fresh
# process loads it and continues at queue_index.
#
# Only fires between queue entries — mid-playlist re-exec would lose the
# child playlist's in-memory state (playlist_line is saved, but a child
# already-running invoke_claude would be abandoned).

maybe_reload_ralph() {
    [[ "$AUTO_RELOAD" != "true" ]] && return 0
    [[ -z "$SUTRA_START_SHA" ]] && return 0
    local current_sha
    current_sha="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "")"
    [[ -z "$current_sha" || "$current_sha" == "$SUTRA_START_SHA" ]] && return 0
    log "Ralph source moved: ${SUTRA_START_SHA:0:7} → ${current_sha:0:7}. Re-executing."
    exec "$SCRIPT_DIR/ralph" "${SUTRA_ARGV[@]}"
}

# ── run_queue ──────────────────────────────────────────────────────────────
#
# Walk QUEUE_ENTRIES, spawning one child ralph per entry. Halt on any
# non-zero child exit or any dirty tree between entries. Resumes from
# queue_index in .sutra/state when --queue points at the same file as
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
    queue_log_init
    local i
    for ((i = start; i < total; i++)); do
        run_queue_entry "$i" || return 1
    done
    queue_index=0
    save_state
    queue_log_finish
    log "=== Queue complete: $total entries ==="
    log "Queue log: $QUEUE_LOG"
}
