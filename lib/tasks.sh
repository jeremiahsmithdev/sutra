# tasks.sh — Task selection, claiming, detail retrieval, and skip logic.

# ── bead_already_closed ────────────────────────────────────────────────────
#
# Check if a bead is already closed. Used by playlist mode to skip
# completed beads on resume. Returns 0 if closed (should skip), 1 otherwise.

bead_already_closed() {
    local tid="$1"
    if [[ "$(get_bead_status "$tid")" == "closed" ]]; then
        log "Skipping ${C_BOLD_CYAN}$tid${C_RESET} ${C_DIM}(already closed)${C_RESET}"
        return 0
    fi
    return 1
}

# ── select_task ─────────────────────────────────────────────────────────────
#
# Sets global $tid to the next task to work on.
# Reuses current_task if retrying, otherwise picks from beads.
# Returns 1 (and sets EXIT_REASON) if nothing is available.

select_task() {
    tid=""

    if [[ -n "${current_task:-}" ]]; then
        # Retrying a task that's still in_progress
        tid="$current_task"
    else
        tid=$(pick_next_task)
    fi

    if [[ -z "$tid" ]]; then
        EXIT_REASON="No ready tasks${SCOPE:+ matching scope '$SCOPE'}"
        return 1
    fi

    return 0
}

# ── handle_dry_run ──────────────────────────────────────────────────────────
#
# If --dry-run is set, log the next task and return 0 (signals break).
# If not dry run, return 1 (signals continue).

handle_dry_run() {
    if [[ "$DRY_RUN" != "true" ]]; then
        return 1
    fi

    log "DRY RUN — next task:"
    log "  ID: $tid"
    get_task_details "$tid" | while IFS= read -r line; do
        log "  $line"
    done
    EXIT_REASON="Dry run complete"
    return 0
}

# ── claim_task ──────────────────────────────────────────────────────────────
#
# Log the loop iteration, fetch task details, and claim in beads.
# Sets global $task_details for prompt construction.

claim_task() {
    local tid="$1"

    local loop_ceiling="${playlist_total:-$MAX_LOOPS}"
    log "=== Loop $((total_loops + 1))/$loop_ceiling ==="

    task_details=$(get_task_details "$tid")
    local task_title
    task_title=$(echo "$task_details" | grep '^Title: ' | head -1 | sed 's/^Title: //')
    log "Task: ${C_BOLD_CYAN}$tid${C_RESET} — ${C_BOLD}$task_title${C_RESET}"

    # Only claim (set in_progress) if this is a fresh pick, not a retry
    if [[ -z "${current_task:-}" ]]; then
        br update "$tid" --status in_progress 2>/dev/null || true
    fi

    current_task="$tid"
    save_state
}

# ── pick_next_task ──────────────────────────────────────────────────────────
#
# Finds the highest-priority unblocked task from beads.
# Skips epics. Applies --scope filter if set.
# Prints task ID to stdout, or empty string if nothing available.

pick_next_task() {
    local ready_json

    ready_json=$(br ready --json --limit 20 2>/dev/null) || {
        echo ""
        return
    }

    if [[ -n "$SCOPE" ]]; then
        echo "$ready_json" \
            | jq -r --arg s "$SCOPE" \
                '[.[] | select(.issue_type != "epic") | select(.id | test($s))] | .[0].id // empty' \
                2>/dev/null \
            || echo ""
    else
        echo "$ready_json" \
            | jq -r '[.[] | select(.issue_type != "epic")] | .[0].id // empty' \
                2>/dev/null \
            || echo ""
    fi
}

# ── get_task_details ────────────────────────────────────────────────────────
#
# Given a task ID, fetches its full details from beads and prints them
# as labelled lines. Used for dry-run display and prompt construction.

get_task_details() {
    local tj

    tj=$(br show "$1" --json 2>/dev/null) || {
        echo ""
        return
    }

    local title desc notes ac design parent
    title=$(echo "$tj" | jq -r '.[0].title // empty')
    desc=$(echo "$tj" | jq -r '.[0].description // empty')
    notes=$(echo "$tj" | jq -r '.[0].notes // empty')
    ac=$(echo "$tj" | jq -r '.[0].acceptance_criteria // empty')
    design=$(echo "$tj" | jq -r '.[0].design // empty')
    parent=$(echo "$tj" | jq -r '.[0].parent // empty')

    if [[ -n "$parent" ]]; then
        local epic_json epic_title epic_desc
        epic_json=$(br show "$parent" --json 2>/dev/null)
        epic_title=$(echo "$epic_json" | jq -r '.[0].title // empty')
        epic_desc=$(echo "$epic_json" | jq -r '.[0].description // empty')
        if [[ -n "$epic_title" ]]; then
            printf 'Epic context (background only — implement the task below, not the epic):\n'
            printf '  %s — %s\n' "$parent" "$epic_title"
            [[ -n "$epic_desc" ]] && printf '  %s\n' "$epic_desc"
        fi
    fi

    printf 'Title: %s\n' "$title"
    [[ -n "$desc" ]]   && printf 'Description: %s\n' "$desc"
    [[ -n "$notes" ]]  && printf 'Notes: %s\n' "$notes"
    [[ -n "$ac" ]]     && printf 'Acceptance Criteria: %s\n' "$ac"
    [[ -n "$design" ]] && printf 'Design: %s\n' "$design"

    # Prevent set -e from exiting when the last field test is false
    true
}

# ── get_branch_context ────────────────────────────────────────────────────
#
# Given a task ID, determines which branch Claude should work on.
# Uses br show --json to check parent epic and epic dependencies.
#
# Output (one line):
#   "standalone"                         — work on sutra branch
#   "epic:<branch>:sutra"                — epic, branch from sutra
#   "epic:<branch>:sutra/<dep-slug>"     — epic, branch from dependency epic

get_branch_context() {
    local task_id="$1"

    # Playlist mode: single branch, skip epic walk entirely
    if [[ -n "${PLAYLIST_BRANCH:-}" ]]; then
        echo "playlist:$PLAYLIST_BRANCH"
        return
    fi

    local tj
    tj=$(br show "$task_id" --json 2>/dev/null) || {
        echo "standalone"
        return
    }

    # Check if task has a parent epic
    local parent_id
    parent_id=$(echo "$tj" | jq -r '.[0].parent // empty' 2>/dev/null)

    if [[ -z "$parent_id" ]]; then
        echo "standalone"
        return
    fi

    # Get the epic's title for the branch name
    local epic_json epic_title epic_slug
    epic_json=$(br show "$parent_id" --json 2>/dev/null) || {
        echo "standalone"
        return
    }
    epic_title=$(echo "$epic_json" | jq -r '.[0].title // empty' 2>/dev/null)
    epic_slug=$(slugify "$epic_title")

    # Check if the epic depends on another epic (blocks dependency, not parent-child)
    local dep_epic_id dep_epic_title dep_epic_slug
    dep_epic_id=$(extract_epic_blocker "$epic_json")

    if [[ -z "$dep_epic_id" ]]; then
        echo "epic:sutra-$epic_slug:sutra"
    else
        dep_epic_title=$(get_epic_dependency_title "$epic_json" "$dep_epic_id")
        dep_epic_slug=$(slugify "$dep_epic_title")
        echo "epic:sutra-$epic_slug:sutra-$dep_epic_slug"
    fi
}

# ── slugify ───────────────────────────────────────────────────────────────
#
# Convert a string to a branch-safe slug: lowercase, hyphens, no specials.

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//'
}
