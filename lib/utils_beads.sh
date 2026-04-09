# utils_beads.sh — Shared br+jq query helpers.
#
# Use these instead of inlining br show/list | jq pipelines in callers.
# The query logic lives in one place and callers read more clearly.
#
# Each "get_*" / "count_*" helper spawns a br subprocess. Prefer the
# "extract_*" helpers when the caller already has pre-fetched JSON.

# Return the status of a bead, or "unknown" on lookup failure.
get_bead_status() {
    br show "$1" --json 2>/dev/null \
        | jq -r '.[0].status // "unknown"' 2>/dev/null \
        || echo "unknown"
}

# Return a single top-level field from a bead, or empty on failure.
# Usage: get_bead_field <id> <field>
get_bead_field() {
    br show "$1" --json 2>/dev/null \
        | jq -r ".[0].$2 // empty" 2>/dev/null
}

# Given pre-fetched epic JSON, return the ID of the first epic blocker
# (dependency_type=blocks, issue_type=epic), or empty.
extract_epic_blocker() {
    echo "$1" | jq -r '[.[0].dependencies // [] | .[] | select(.dependency_type == "blocks") | select(.issue_type == "epic")] | .[0].id // empty' 2>/dev/null
}

# Given pre-fetched epic JSON and a dependency ID, return that dep's title.
get_epic_dependency_title() {
    echo "$1" | jq -r --arg d "$2" '[.[0].dependencies // [] | .[] | select(.id == $d)] | .[0].title // empty' 2>/dev/null
}

# Count non-closed parent-child children of an epic.
count_open_epic_children() {
    br show "$1" --json 2>/dev/null \
        | jq '[.[0].dependents // [] | .[] | select(.dependency_type == "parent-child") | select(.status != "closed")] | length' 2>/dev/null
}

# Return JSON array of tasks closed since the given RFC3339 timestamp.
get_closed_tasks_since() {
    br list --status=closed --all --json 2>/dev/null \
        | jq --arg s "$1" '[.issues[] | select(.closed_at >= $s)]' 2>/dev/null
}
