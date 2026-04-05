# prompt.sh — Construct the prompt sent to Claude Code.
#
# Sets the global $prompt variable with the task details,
# branching instructions, execution rules, and issue closure protocol.

build_prompt() {
    local task_id="$1"
    local details="$2"

    # Determine branching context from epic membership and dependencies
    local branch_ctx branch_section
    branch_ctx=$(get_branch_context "$task_id")

    case "$branch_ctx" in
        standalone)
            branch_section="Work on the \`ralph\` branch.
Ensure you are on it before starting:
  git checkout ralph
Do NOT create feature branches for standalone tasks. Commit directly to \`ralph\`."
            ;;
        epic:*:ralph)
            local epic_branch="${branch_ctx#epic:}"
            epic_branch="${epic_branch%:ralph}"
            branch_section="This task belongs to an epic. Work on branch \`$epic_branch\`.
If the branch does not exist, create it from \`ralph\`:
  git checkout ralph && git checkout -b $epic_branch
If it already exists:
  git checkout $epic_branch
Commit all work to \`$epic_branch\`. Do NOT merge — merging happens at harvest."
            ;;
        epic:*:*)
            local rest="${branch_ctx#epic:}"
            local epic_branch="${rest%%:*}"
            local dep_branch="${rest#*:}"
            branch_section="This task belongs to an epic that depends on a prior epic.
Work on branch \`$epic_branch\`.
If the branch does not exist, create it from \`$dep_branch\` (the dependency):
  git checkout $dep_branch && git checkout -b $epic_branch
If it already exists:
  git checkout $epic_branch
Commit all work to \`$epic_branch\`. Do NOT merge — merging happens at harvest."
            ;;
    esac

    prompt="You are executing a single task from a beads issue tracker as part of an automated ralph loop.

## Your Task
ID: $task_id
$details

## Branch
$branch_section

## Rules
1. Implement this ONE task completely. Do not work on other tasks.
2. Search the codebase before assuming anything about structure.
3. Run tests or manual verification after implementation.
$(if [[ "$AUTO_COMMIT" == true ]]; then
    echo "4. Commit your changes with a conventional commit message."
else
    echo "4. Do NOT commit. Leave changes staged or unstaged — commits are handled externally."
fi)
5. If you are blocked and cannot complete the task, say so clearly.
6. Do NOT touch .beads/ files — never commit, stash, or modify them. Do NOT run \`br sync\`. The outer loop handles beads state automatically.

## When Done
Close the issue with a reason that a human reviewer can use to verify your work:
  br close $task_id --reason \"VERIFY: [how to test] NOTES: [what changed]\"

If you are BLOCKED and cannot complete the task, release it:
  br update $task_id --status open"
}

# ── build_raw_prompt ───────────────────────────────────────────────────────
#
# Construct a prompt for a raw (non-bead) playlist line.
# These are maintenance/review tasks that don't have a bead to close.
# Sets the global $prompt variable.

build_raw_prompt() {
    local prompt_text="$1"
    local current_branch recent_commits

    current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    recent_commits=$(git log --oneline -5 2>/dev/null || echo "(no commits)")

    prompt="You are performing a maintenance task between automated bead implementations
in the ralph autonomous loop.

## Task
$prompt_text

## Context
* Working directory: $(pwd)
* Branch: $current_branch
* Recent commits:
$recent_commits

## Rules
1. Search the codebase before assuming anything about structure.
2. Make targeted fixes and commit with conventional commit messages.
3. You may update beads using br update/br create/br close as needed.
4. Do NOT touch .beads/ files directly — use br commands only.
5. Do NOT run br sync — the outer loop handles that.
6. When done, just exit. There is no bead to close for this task."
}

# ── build_report_prompt ────────────────────────────────────────────────────
#
# Construct a prompt for the playlist completion report.
# Gives Claude all the raw data and asks it to write a markdown report file.
# Sets the global $prompt variable.

build_report_prompt() {
    local report_dir="$1"
    local report_file="$2"
    local playlist_data="$3"
    local git_log="$4"

    prompt="You are generating a completion report for a ralph playlist run.

## Instructions
Write a markdown report to: $report_file
Create the directory $report_dir if it does not exist (mkdir -p).

## Report Template

# Ralph Playlist Report: $(basename "$PLAYLIST")
**Date:** $(date '+%Y-%m-%d %H:%M') **Model:** $MODEL
**Exit reason:** $EXIT_REASON **Circuit breaker:** ${circuit:-CLOSED}

## Summary
- Tasks completed: $total_tasks_completed
- Total loops: $total_loops
- Playlist: $PLAYLIST ($playlist_total items)
- Processed: $(playlist_processed) / $playlist_total

## Task Results
$playlist_data

## Commits This Session
$git_log

## Notes
Add any observations about the run: blocked tasks, patterns, issues discovered.

## Rules
1. Write the report file directly using the template above. Fill in the Notes section with useful observations.
2. Commit the report: git add $report_dir && git commit -m 'docs(ralph): playlist completion report'
3. Do NOT modify any other files. Do NOT run br commands.
4. When done, just exit."
}
