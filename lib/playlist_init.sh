# playlist_init.sh — ralph playlist init subcommand.
#
# Phase 1: deterministic syntax + gate density validation.
# Phase 2 (task 13): semantic validation via Claude — runs if Phase 1 passes.

# ── run_playlist_init ─────────────────────────────────────────────────────
#
# Entry point for `ralph playlist init <file>`. Validates syntax, then
# (when implemented) runs semantic validation.

run_playlist_init() {
    if [[ ! -f "$PLAYLIST" ]]; then
        log "ERROR: Playlist file not found: $PLAYLIST"
        return 1
    fi

    log "Validating playlist: ${C_BOLD}$PLAYLIST${C_RESET}"

    # Read file into PLAYLIST_LINES for gate analysis
    PLAYLIST_LINES=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        PLAYLIST_LINES+=("$line")
    done < "$PLAYLIST"

    local errors=0 warnings=0

    validate_line_syntax
    errors=$((errors + _syntax_errors))
    warnings=$((warnings + _syntax_warnings))

    validate_gate_density
    errors=$((errors + _gate_errors))
    warnings=$((warnings + _gate_warnings))

    print_validation_summary "$errors" "$warnings"

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    # Phase 2 placeholder (task 13): playlist_validate_semantic
    return 0
}

# ── validate_line_syntax ──────────────────────────────────────────────────
#
# Phase 1a: check each line. Bead IDs verified against br, prompts
# accepted as-is. Branch directives validated for git ref safety.

validate_line_syntax() {
    _syntax_errors=0
    _syntax_warnings=0
    local line_num=0 past_first_actionable=false
    local branch_directive_seen=false

    printf '\n%s\n' "${C_BOLD}Line syntax:${C_RESET}"

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" ]] && continue

        if [[ "$trimmed" == \#* ]]; then
            validate_comment_directive "$line_num" "$trimmed" "$past_first_actionable"
            continue
        fi

        past_first_actionable=true

        if [[ "$trimmed" == ">"* ]]; then
            continue  # prompt lines are syntactically valid
        fi

        validate_bead_id "$line_num" "$trimmed"
    done < "$PLAYLIST"

    if [[ $_syntax_errors -eq 0 && $_syntax_warnings -eq 0 ]]; then
        printf '  %s✓ All lines valid%s\n' "$C_GREEN" "$C_RESET"
    fi
}

# ── validate_comment_directive ────────────────────────────────────────────

validate_comment_directive() {
    local line_num="$1" trimmed="$2" past_first="$3"
    local match
    match=$(echo "$trimmed" | sed -n 's/^#[[:space:]]*branch:[[:space:]]*//Ip')
    [[ -z "$match" ]] && return

    if [[ "$past_first" == true ]]; then
        printf '  Line %d: %sWARNING%s — "# branch:" after first actionable line (ignored at runtime)\n' \
            "$line_num" "$C_BOLD_YELLOW" "$C_RESET"
        _syntax_warnings=$((_syntax_warnings + 1))
        return
    fi

    if [[ "${_branch_directive_seen:-false}" == true ]]; then
        printf '  Line %d: %sERROR%s — duplicate "# branch:" directive\n' \
            "$line_num" "$C_BOLD_RED" "$C_RESET"
        _syntax_errors=$((_syntax_errors + 1))
        return
    fi
    _branch_directive_seen=true

    if ! git check-ref-format --branch "$match" &>/dev/null; then
        printf '  Line %d: %sERROR%s — invalid branch name "%s"\n' \
            "$line_num" "$C_BOLD_RED" "$C_RESET" "$match"
        _syntax_errors=$((_syntax_errors + 1))
    fi
}

# ── validate_bead_id ──────────────────────────────────────────────────────

validate_bead_id() {
    local line_num="$1" id="$2"

    if ! br show "$id" &>/dev/null; then
        printf '  Line %d: %sERROR%s — "%s" is not a valid bead ID\n' \
            "$line_num" "$C_BOLD_RED" "$C_RESET" "$id"
        _syntax_errors=$((_syntax_errors + 1))
        return
    fi

    local status
    status=$(get_bead_status "$id")
    if [[ "$status" == "closed" ]]; then
        printf '  Line %d: %sWARNING%s — bead "%s" is already closed\n' \
            "$line_num" "$C_BOLD_YELLOW" "$C_RESET" "$id"
        _syntax_warnings=$((_syntax_warnings + 1))
    fi
}

# ── validate_gate_density ─────────────────────────────────────────────────
#
# Phase 1b: run gate_check_playlist and gate_minimum_rules.

validate_gate_density() {
    _gate_errors=0
    _gate_warnings=0

    printf '\n%s\n' "${C_BOLD}Gate analysis:${C_RESET}"

    local report
    report=$(gate_check_playlist)

    # Parse report: "beads=N gates=M TAG=C ..."
    local beads=0 gates=0
    local -a tag_pairs=()
    local word
    for word in $report; do
        case "$word" in
            beads=*) beads="${word#beads=}" ;;
            gates=*) gates="${word#gates=}" ;;
            *)       tag_pairs+=("$word") ;;
        esac
    done

    printf '  Beads: %d  |  Gates: %d  |  Density: %d:%d\n' \
        "$beads" "$gates" "$gates" "$beads"

    local violations
    violations=$(gate_minimum_rules "$beads" "$gates" "${tag_pairs[@]}" 2>&1)

    if [[ -n "$violations" ]]; then
        while IFS= read -r vline; do
            case "$vline" in
                ERROR:*)
                    printf '  %s%s%s\n' "$C_BOLD_RED" "$vline" "$C_RESET"
                    _gate_errors=$((_gate_errors + 1))
                    ;;
                WARNING:*)
                    printf '  %s%s%s\n' "$C_BOLD_YELLOW" "$vline" "$C_RESET"
                    _gate_warnings=$((_gate_warnings + 1))
                    ;;
            esac
        done <<< "$violations"
    else
        printf '  %s✓ Gate density OK%s\n' "$C_GREEN" "$C_RESET"
    fi
}

# ── print_validation_summary ──────────────────────────────────────────────

print_validation_summary() {
    local errors="$1" warnings="$2"
    printf '\n'
    if [[ $errors -gt 0 ]]; then
        printf '%s%d errors, %d warnings. Fix errors before proceeding.%s\n' \
            "$C_BOLD_RED" "$errors" "$warnings" "$C_RESET"
    elif [[ $warnings -gt 0 ]]; then
        printf '%s%d warnings. Proceeding to Phase 2.%s\n' \
            "$C_BOLD_YELLOW" "$warnings" "$C_RESET"
    else
        printf '%s✓ Clean. Proceeding to Phase 2.%s\n' "$C_GREEN" "$C_RESET"
    fi
}
