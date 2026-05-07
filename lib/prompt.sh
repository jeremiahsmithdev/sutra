# prompt.sh — Construct the prompts sent to Claude Code.
#
# Each builder assembles the global $prompt variable by rendering a
# template file from templates/ with substituted values. Template files
# live in sibling helpers so the shell code here reads as composition.

# ── build_prompt ──────────────────────────────────────────────────────────
#
# Bead task prompt. Substitutes task ID, details, branch instructions,
# and commit rule into templates/prompt_bead.txt.

build_prompt() {
    local task_id="$1"
    local details="$2"
    local branch_ctx branch_section commit_rule prior_task_context

    branch_ctx=$(get_branch_context "$task_id")
    branch_section=$(format_branch_instructions "$branch_ctx")
    commit_rule=$(format_commit_rule)
    prior_task_context=$(format_prior_task_context)

    local file_map playlist_progress
    file_map=$(format_file_map)
    playlist_progress=$(format_playlist_progress)

    prompt=$(render_template "$TEMPLATES_DIR/prompt_bead.txt" \
        "TASK_ID=$task_id" \
        "DETAILS=$details" \
        "PRIOR_TASK_CONTEXT=$prior_task_context" \
        "BRANCH_SECTION=$branch_section" \
        "COMMIT_RULE=$commit_rule" \
        "FILE_MAP=$file_map" \
        "PLAYLIST_PROGRESS=$playlist_progress")

    clear_task_handoff
}

# ── build_raw_prompt ──────────────────────────────────────────────────────
#
# Free-form playlist prompt (no bead to claim/close). Renders
# templates/prompt_raw.txt with runtime git context.

build_raw_prompt() {
    local prompt_text="$1"
    local current_branch recent_commits prior_task_context

    current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    recent_commits=$(git log --oneline -5 2>/dev/null || echo "(no commits)")
    prior_task_context=$(format_prior_task_context)

    local file_map playlist_progress
    file_map=$(format_file_map)
    playlist_progress=$(format_playlist_progress)

    prompt=$(render_template "$TEMPLATES_DIR/prompt_raw.txt" \
        "PROMPT_TEXT=$prompt_text" \
        "PRIOR_TASK_CONTEXT=$prior_task_context" \
        "WORKING_DIR=$(pwd)" \
        "CURRENT_BRANCH=$current_branch" \
        "RECENT_COMMITS=$recent_commits" \
        "FILE_MAP=$file_map" \
        "PLAYLIST_PROGRESS=$playlist_progress")

    clear_task_handoff
}

# ── build_report_prompt ───────────────────────────────────────────────────
#
# Playlist completion report prompt. Gives Claude all the raw data and
# asks it to write a markdown report file.

build_report_prompt() {
    local report_dir="$1"
    local report_file="$2"
    local playlist_data="$3"
    local git_log="$4"

    prompt=$(render_template "$TEMPLATES_DIR/prompt_report.txt" \
        "REPORT_DIR=$report_dir" \
        "REPORT_FILE=$report_file" \
        "PLAYLIST_NAME=$(basename "$PLAYLIST")" \
        "TIMESTAMP=$(date '+%Y-%m-%d %H:%M')" \
        "MODEL=$MODEL" \
        "RALPH_VERSION=$(ralph_version_string)" \
        "EXIT_REASON=$EXIT_REASON" \
        "CIRCUIT=${circuit:-CLOSED}" \
        "TASKS_COMPLETED=$total_tasks_completed" \
        "TOTAL_LOOPS=$total_loops" \
        "PLAYLIST_PATH=$PLAYLIST" \
        "PLAYLIST_TOTAL=$playlist_total" \
        "PROCESSED=$(playlist_processed)" \
        "PLAYLIST_DATA=$playlist_data" \
        "GIT_LOG=$git_log")
}

# ── format_branch_instructions ────────────────────────────────────────────
#
# Render the branch-section of the bead prompt. Dispatches on the branch
# context string returned by get_branch_context() in tasks.sh.

format_branch_instructions() {
    local branch_ctx="$1"
    case "$branch_ctx" in
        playlist:*)
            local branch="${branch_ctx#playlist:}"
            render_template "$TEMPLATES_DIR/branch_playlist.txt" \
                "BRANCH=$branch"
            ;;
        standalone)
            cat "$TEMPLATES_DIR/branch_standalone.txt"
            ;;
        epic:*:ralph)
            local epic_branch="${branch_ctx#epic:}"
            epic_branch="${epic_branch%:ralph}"
            render_template "$TEMPLATES_DIR/branch_epic_ralph.txt" \
                "EPIC_BRANCH=$epic_branch"
            ;;
        epic:*:*)
            local rest="${branch_ctx#epic:}"
            local epic_branch="${rest%%:*}"
            local dep_branch="${rest#*:}"
            render_template "$TEMPLATES_DIR/branch_epic_dep.txt" \
                "EPIC_BRANCH=$epic_branch" \
                "DEP_BRANCH=$dep_branch"
            ;;
    esac
}

# ── format_commit_rule ────────────────────────────────────────────────────
#
# Return rule 4 of the bead prompt, conditional on AUTO_COMMIT.

format_commit_rule() {
    if [[ "$AUTO_COMMIT" == true ]]; then
        echo "4. Commit your changes with a conventional commit message."
    else
        echo "4. Do NOT commit. Leave changes staged or unstaged — commits are handled externally."
    fi
}
