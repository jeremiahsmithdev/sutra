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
4. Commit your changes with a conventional commit message.
5. If you are blocked and cannot complete the task, say so clearly.
6. Do NOT touch .beads/ files — never commit, stash, or modify them. Do NOT run \`br sync\`. The outer loop handles beads state automatically.

## When Done
Close the issue with a reason that a human reviewer can use to verify your work:
  br close $task_id --reason \"VERIFY: [how to test] NOTES: [what changed]\"

If you are BLOCKED and cannot complete the task, release it:
  br update $task_id --status open"
}
