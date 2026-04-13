# prompt_context.sh — Cross-bead handoff and project file map for prompts.
#
# format_prior_task_context() renders the claimed summary from the last bead.
# format_file_map() renders a path+purpose manifest from CONTEXT_FILES.
# clear_task_handoff() resets handoff globals after prompt injection.

# ── format_prior_task_context ─────────────────────────────────────────────
#
# Render the "## Prior Task Context" section from the globals set by
# capture_task_handoff(). Returns empty string if no prior task info —
# that's the first-task-in-session case, and the placeholder collapses
# to nothing in the rendered prompt.

format_prior_task_context() {
    [[ -z "${LAST_TASK_SUMMARY:-}" ]] && return
    render_template "$TEMPLATES_DIR/prior_task_context.txt" \
        "LAST_TASK_ID=${LAST_TASK_ID:-unknown}" \
        "LAST_TASK_SUMMARY=$LAST_TASK_SUMMARY"
}

# ── clear_task_handoff ────────────────────────────────────────────────────
#
# Called after the prior-task context has been rendered into a prompt.
# Ensures a retry of the same task doesn't re-inject stale handoff data.

clear_task_handoff() {
    LAST_TASK_SUMMARY=""
    LAST_TASK_ID=""
}

# ── format_file_map ───────────────────────────────────────────────────────
#
# Build a "## Project File Map" section from CONTEXT_FILES. Each file's
# first comment line is extracted as a purpose summary. Returns empty
# string when CONTEXT_FILES is unset — the {{FILE_MAP}} placeholder
# collapses to nothing.

format_file_map() {
    [[ -z "${CONTEXT_FILES:-}" ]] && return

    local IFS=',' map="" path purpose
    # shellcheck disable=SC2206  # intentional split on comma
    local -a files=($CONTEXT_FILES)

    for path in "${files[@]}"; do
        path="${path## }"; path="${path%% }"  # trim spaces
        if [[ ! -f "$path" ]]; then
            log "WARNING: Context file not found: $path"
            continue
        fi
        purpose=$(extract_file_purpose "$path")
        map+="* ${path} — ${purpose}"$'\n'
    done

    [[ -z "$map" ]] && return
    printf '\n## Project File Map\n%s' "$map"
}

# ── extract_file_purpose ─────────────────────────────────────────────────
#
# Read the first 10 lines of a file and return the first comment line's
# content as a purpose string. Handles #, //, /*, --, and """ markers.
# Returns "(no description)" if no comment is found.

extract_file_purpose() {
    local path="$1" line stripped
    while IFS= read -r line; do
        stripped="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace
        case "$stripped" in
            '#!'*)  continue ;;
            '#'*)   stripped="${stripped#\#}"; stripped="${stripped# }" ;;
            '//'*)  stripped="${stripped#//}"; stripped="${stripped# }" ;;
            '/*'*)  stripped="${stripped#/\*}"; stripped="${stripped# }" ;;
            '--'*)  stripped="${stripped#--}"; stripped="${stripped# }" ;;
            *)      continue ;;
        esac
        [[ -n "$stripped" ]] && { echo "$stripped"; return; }
    done < <(head -10 "$path")
    echo "(no description)"
}
