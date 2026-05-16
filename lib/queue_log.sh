# queue_log.sh — High-level roll-up log for a --queue run.
#
# The queue parent process never sets up a SESSION_LOG (only child ralphs
# do, in invoke.sh), so without this its progress vanishes with the
# terminal. This module writes one durable file per queue run recording,
# per playlist: branch, child exit status, beads closed, commits, and the
# report file path. Per-loop detail stays in the child session logs.

# QUEUE_LOG — path to the roll-up file. Persisted in .ralph/state so a
# resumed queue appends to the same file instead of starting a new one.
QUEUE_LOG="${QUEUE_LOG:-}"

# ── queue_log_init ─────────────────────────────────────────────────────────
#
# Resolve QUEUE_LOG. Reuse the persisted path on resume; otherwise create a
# fresh timestamped file with a header. Called once at run_queue start.

queue_log_init() {
    [[ -z "$QUEUE_LOG" ]] && QUEUE_LOG="${queue_log:-}"

    if [[ -n "$QUEUE_LOG" && -f "$QUEUE_LOG" ]]; then
        # Recover the running cost total from cost lines already logged so
        # the final Total cost spans the whole queue, not just post-resume.
        _queue_log_total_cost=$(awk -F'$' '/^  cost:/ {s += $2} END {printf "%.2f", s}' \
            "$QUEUE_LOG")
        printf '\n── resumed %s at entry %d ──\n\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$((${queue_index:-0} + 1))" \
            >> "$QUEUE_LOG"
        return
    fi

    _queue_log_total_cost=0
    mkdir -p ".ralph/logs"
    QUEUE_LOG=".ralph/logs/queue-$(date +%Y%m%d-%H%M%S).log"
    {
        printf 'Ralph queue run\n'
        printf 'Started:  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'Queue:    %s (%d entries)\n\n' "$QUEUE_FILE" "${#QUEUE_ENTRIES[@]}"
    } > "$QUEUE_LOG"
}

# ── queue_log_entry_start ──────────────────────────────────────────────────
#
# Record the start of one queue entry and snapshot state for later diffing:
# the start time (for duration) and the set of already-closed bead IDs.

queue_log_entry_start() {
    local i="$1" total="$2" entry="$3"
    _queue_log_start_epoch=$(date +%s)
    _queue_log_closed_before=" $(_queue_log_closed_ids) "
    {
        printf '▶ %s  (%d/%d)\n' "$entry" "$((i + 1))" "$total"
        printf '  started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    } >> "$QUEUE_LOG"
}

# ── queue_log_entry_finish ─────────────────────────────────────────────────
#
# Record the outcome of one queue entry: status, branch, report path,
# beads closed during the run, and the commits the playlist produced.

queue_log_entry_finish() {
    local entry="$1" exit_status="$2"
    local branch report
    branch=$(_queue_log_branch_for "$entry")
    report=$(_queue_log_latest_report "$entry")
    {
        if [[ "$exit_status" -eq 0 ]]; then
            printf '  status:  complete (exit 0) in %s\n' "$(_queue_log_duration)"
        else
            printf '  status:  FAILED (exit %s) after %s\n' \
                "$exit_status" "$(_queue_log_duration)"
        fi
        printf '  branch:  %s\n' "$branch"
        printf '  report:  %s\n' "${report:-(none)}"
        _queue_log_cost
        _queue_log_beads_closed
        _queue_log_commits "$branch"
        printf '\n'
    } >> "$QUEUE_LOG"
}

# ── _queue_log_cost ────────────────────────────────────────────────────────
#
# Report the child's cumulative cost and fold it into the queue total. The
# child's total_cost_usd sits in .ralph/state until the parent's next
# save_state zeroes it — this runs inside that window.

_queue_log_cost() {
    local cost
    cost=$(grep -E '^total_cost_usd=' "${STATE_FILE:-.ralph/state}" 2>/dev/null \
        | cut -d= -f2)
    cost="${cost:-0}"
    _queue_log_total_cost=$(awk "BEGIN {printf \"%.2f\", ${_queue_log_total_cost:-0} + $cost}")
    printf '  cost:    $%s\n' "$cost"
}

# ── queue_prior_cost ───────────────────────────────────────────────────────
#
# Cost already spent by queue entries that finished before the current
# child. A child ralph re-execs with a zeroed total_cost_usd, so the
# circuit breaker's cost cap would otherwise see only this entry's spend.
# Summing the `  cost:` lines already in the queue log restores a
# queue-wide figure. Returns 0 when there is no queue log — a
# single-playlist run then behaves exactly as before.

queue_prior_cost() {
    local log="${queue_log:-$QUEUE_LOG}"
    [[ -z "$log" || ! -f "$log" ]] && { echo 0; return; }
    awk -F'$' '/^  cost:/ {s += $2} END {printf "%.2f", s + 0}' "$log"
}

# ── queue_log_finish ───────────────────────────────────────────────────────

queue_log_finish() {
    [[ -z "$QUEUE_LOG" ]] && return
    {
        printf 'Total cost: $%s\n' "${_queue_log_total_cost:-0.00}"
        printf '── queue complete %s ──\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    } >> "$QUEUE_LOG"
}

# ── _queue_log_closed_ids ──────────────────────────────────────────────────
#
# Space-joined list of every closed bead ID. Empty if br/jq is unavailable —
# the roll-up degrades to "beads closed: none" rather than failing.

_queue_log_closed_ids() {
    { br list --status closed --json 2>/dev/null \
        | jq -r '.[].id' 2>/dev/null | sort | tr '\n' ' '; } || true
}

# ── _queue_log_beads_closed ────────────────────────────────────────────────
#
# Diff the closed-bead set captured at entry start against the set now;
# the difference is what this playlist closed.

_queue_log_beads_closed() {
    local after=" $(_queue_log_closed_ids) "
    local closed="" id
    for id in $after; do
        [[ "${_queue_log_closed_before:- }" == *" $id "* ]] && continue
        closed+="$id "
    done
    closed="${closed% }"
    if [[ -z "$closed" ]]; then
        printf '  beads closed: none\n'
        return
    fi
    set -- $closed
    printf '  beads closed (%d): %s\n' "$#" "$closed"
}

# ── _queue_log_commits ─────────────────────────────────────────────────────
#
# Commits the playlist branch carries beyond the branch it forked from.

_queue_log_commits() {
    local branch="$1"
    local base="${WORKING_BRANCH:-main}"
    local commits
    commits=$(git log --oneline "${base}..${branch}" 2>/dev/null || true)
    if [[ -z "$commits" ]]; then
        printf '  commits: none\n'
        return
    fi
    printf '  commits (%d):\n' "$(( $(wc -l <<< "$commits") ))"
    while IFS= read -r c; do
        printf '    %s\n' "$c"
    done <<< "$commits"
}

# ── _queue_log_branch_for ──────────────────────────────────────────────────
#
# Branch a playlist entry lands on. Honours a `# branch:` directive in the
# file; otherwise the filename-derived default (mirrors playlist_branch.sh).

_queue_log_branch_for() {
    local entry="$1"
    [[ "$entry" == --* ]] && { echo "(non-playlist entry)"; return; }
    local directive=""
    [[ -f "$entry" ]] && directive=$(sed -n \
        's/^#[[:space:]]*branch:[[:space:]]*//Ip' "$entry" | head -1)
    if [[ -n "$directive" ]]; then
        echo "$directive"
        return
    fi
    local name
    name=$(basename "$entry")
    echo "${name%.*}.playlist"
}

# ── _queue_log_latest_report ───────────────────────────────────────────────
#
# Newest report file matching the playlist basename, written by the child's
# cleanup. Empty if the child exited before generating one.

_queue_log_latest_report() {
    local base
    base=$(basename "$1")
    { ls -t ".ralph/reports/${base%.*}"-*.md 2>/dev/null | head -1; } || true
}

# ── _queue_log_duration ────────────────────────────────────────────────────

_queue_log_duration() {
    local secs=$(( $(date +%s) - ${_queue_log_start_epoch:-$(date +%s)} ))
    printf '%dh%02dm' "$(( secs / 3600 ))" "$(( (secs % 3600) / 60 ))"
}
