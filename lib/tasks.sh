# tasks.sh — Task selection, claiming, and detail retrieval from beads.

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

    log "=== Loop $((total_loops + 1))/$MAX_LOOPS ==="

    task_details=$(get_task_details "$tid")
    local task_title
    task_title=$(echo "$task_details" | head -1 | sed 's/^Title: //')
    log "Task: ${C_BOLD_CYAN}$tid${C_RESET} — ${C_BOLD}$task_title${C_RESET}"

    # Only claim (set in_progress) if this is a fresh pick, not a retry
    if [[ -z "${current_task:-}" ]]; then
        bd update "$tid" --status in_progress 2>/dev/null || true
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

    ready_json=$(bd ready --json --limit 20 2>/dev/null) || {
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

    tj=$(bd show "$1" --json 2>/dev/null) || {
        echo ""
        return
    }

    local title desc notes ac design
    title=$(echo "$tj" | jq -r '.[0].title // empty')
    desc=$(echo "$tj" | jq -r '.[0].description // empty')
    notes=$(echo "$tj" | jq -r '.[0].notes // empty')
    ac=$(echo "$tj" | jq -r '.[0].acceptance_criteria // empty')
    design=$(echo "$tj" | jq -r '.[0].design // empty')

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
# Uses bd show --json to check parent epic and epic dependencies.
#
# Output (one line):
#   "standalone"                         — work on ralph branch
#   "epic:<branch>:ralph"                — epic, branch from ralph
#   "epic:<branch>:ralph/<dep-slug>"     — epic, branch from dependency epic

get_branch_context() {
    local task_id="$1"
    local tj

    tj=$(bd show "$task_id" --json 2>/dev/null) || {
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
    epic_json=$(bd show "$parent_id" --json 2>/dev/null) || {
        echo "standalone"
        return
    }
    epic_title=$(echo "$epic_json" | jq -r '.[0].title // empty' 2>/dev/null)
    epic_slug=$(slugify "$epic_title")

    # Check if the epic depends on another epic (blocks dependency, not parent-child)
    local dep_epic_id dep_epic_title dep_epic_slug
    dep_epic_id=$(echo "$epic_json" | jq -r '
        [.[0].dependencies // [] | .[] | select(.dependency_type == "blocks") | select(.issue_type == "epic")]
        | .[0].id // empty
    ' 2>/dev/null)

    if [[ -z "$dep_epic_id" ]]; then
        echo "epic:ralph-$epic_slug:ralph"
    else
        dep_epic_title=$(echo "$epic_json" | jq -r "
            [.[0].dependencies // [] | .[] | select(.id == \"$dep_epic_id\")]
            | .[0].title // empty
        " 2>/dev/null)
        dep_epic_slug=$(slugify "$dep_epic_title")
        echo "epic:ralph-$epic_slug:ralph-$dep_epic_slug"
    fi
}

# ── slugify ───────────────────────────────────────────────────────────────
#
# Convert a string to a branch-safe slug: lowercase, hyphens, no specials.

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//'
}
