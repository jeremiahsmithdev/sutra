# project_summary.sh — Generate and cache .ralph/project-context.md.
#
# On first run or when stale, invoke Claude (haiku) to produce a concise
# project summary. Subsequent runs reuse the cached file.

PROJECT_SUMMARY=".ralph/project-context.md"
SUMMARY_MAX_AGE_HOURS=24
SUMMARY_MAX_COMMITS=10

# ── ensure_project_summary ────────────────────────────────────────────────
#
# Check if summary exists and is fresh. Regenerate if stale or missing.
# Called from initialize() after init_invoke.

ensure_project_summary() {
    if summary_is_fresh; then
        log "Using cached project summary"
        return
    fi
    generate_project_summary
}

# ── summary_is_fresh ──────────────────────────────────────────────────────
#
# Returns 0 if the cached summary exists, is <24h old, and <10 commits
# have been made since generation.

summary_is_fresh() {
    [[ ! -f "$PROJECT_SUMMARY" ]] && return 1

    # Check age
    local file_age_hours
    file_age_hours=$(file_age_in_hours "$PROJECT_SUMMARY")
    [[ $file_age_hours -ge $SUMMARY_MAX_AGE_HOURS ]] && return 1

    # Check commit distance
    local generated_at
    generated_at=$(head -1 "$PROJECT_SUMMARY" | sed -n 's/.*generated-at: \([a-f0-9]*\).*/\1/p')
    if [[ -n "$generated_at" ]]; then
        local commit_count
        commit_count=$(git rev-list --count "$generated_at"..HEAD 2>/dev/null) || return 1
        [[ $commit_count -ge $SUMMARY_MAX_COMMITS ]] && return 1
    fi

    return 0
}

# ── file_age_in_hours ─────────────────────────────────────────────────────

file_age_in_hours() {
    local file="$1"
    local now file_mtime
    now=$(date +%s)
    file_mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null) || { echo 999; return; }
    echo $(( (now - file_mtime) / 3600 ))
}

# ── generate_project_summary ──────────────────────────────────────────────

generate_project_summary() {
    log "Generating project summary..."
    local saved_model="$MODEL"
    MODEL="haiku"
    local head_hash
    head_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    prompt="Analyze this project and write a concise project summary to $PROJECT_SUMMARY.
Include: directory structure (tree -L 2), key files and their purposes, dependency versions
(from package.json/pubspec.yaml/requirements.txt/Cargo.toml/go.mod), architecture patterns
observed, and any conventions (naming, testing, etc). Keep it under 300 lines.
Add <!-- generated-at: $head_hash --> as the FIRST line.
Output ONLY the file — no commentary."

    if invoke_claude; then
        log "Project summary generated: ${C_BOLD}$PROJECT_SUMMARY${C_RESET}"
    else
        log "WARNING: Project summary generation failed. Continuing without it."
    fi
    MODEL="$saved_model"
}

# ── format_project_summary ────────────────────────────────────────────────
#
# Read the cached summary and return it for prompt injection. Truncated
# to 100 lines. Returns empty if file doesn't exist.

format_project_summary() {
    [[ ! -f "$PROJECT_SUMMARY" ]] && return
    printf '\n## Project Summary\n'
    head -100 "$PROJECT_SUMMARY"
}
