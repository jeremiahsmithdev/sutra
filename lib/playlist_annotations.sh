# playlist_annotations.sh — Per-line @key=value annotation parsing and apply/restore.
#
# Annotations set per-invocation overrides for model, turns, and timeout.
# First attempt only — retries fall back to global values.

# ── reset_line_annotations ────────────────────────────────────────────────

reset_line_annotations() {
    playlist_line_model=""
    playlist_line_turns=""
    playlist_line_timeout=""
    playlist_line_gate_tag=""
    playlist_line_gate_context=""
}

# ── apply_annotation_token ────────────────────────────────────────────────
#
# Parse a single @token (e.g. @opus, @model=sonnet, @turns=30, @timeout=15).
# Backward compat: bare @opus (no =) sets model.

apply_annotation_token() {
    local token="$1"
    token="${token#@}"

    if [[ "$token" == *=* ]]; then
        local key="${token%%=*}" val="${token#*=}"
        case "$key" in
            model)   playlist_line_model="$val" ;;
            turns)   playlist_line_turns="$val" ;;
            timeout) playlist_line_timeout="$val" ;;
            *)       log "WARNING: Unknown annotation @$key=$val (ignored)" ;;
        esac
    else
        # Bare @name — backward compat for model
        playlist_line_model="$token"
    fi
}

# ── parse_bead_annotations ────────────────────────────────────────────────
#
# Split a bead line into ID + trailing @annotations.
# "chippie-xyz.1 @turns=30 @model=sonnet" → ID=chippie-xyz.1, annotations applied.

parse_bead_annotations() {
    local line="$1"
    playlist_current_line="${line%% @*}"

    # If line has annotations after the ID
    if [[ "$line" == *" @"* ]]; then
        local rest="${line#* @}"
        rest="@$rest"
        local token
        for token in $rest; do
            [[ "$token" == @* ]] && apply_annotation_token "$token"
        done
    fi
}

# ── apply_line_overrides ──────────────────────────────────────────────────
#
# Save global values and apply annotation overrides before invocation.
# Returns saved values via globals so restore can use them.

apply_line_overrides() {
    _saved_model="" _saved_turns="" _saved_timeout=""

    if [[ -n "$playlist_line_model" ]]; then
        _saved_model="$MODEL"
        MODEL="$playlist_line_model"
    fi
    if [[ -n "$playlist_line_turns" ]]; then
        _saved_turns="$MAX_TURNS"
        MAX_TURNS="$playlist_line_turns"
    fi
    if [[ -n "$playlist_line_timeout" ]]; then
        _saved_timeout="$TIMEOUT_MINUTES"
        TIMEOUT_MINUTES="$playlist_line_timeout"
        TIMEOUT_SECS=$((TIMEOUT_MINUTES * 60))
    fi
}

# ── restore_line_overrides ────────────────────────────────────────────────
#
# Restore global values after invocation completes.

restore_line_overrides() {
    [[ -n "$_saved_model" ]] && MODEL="$_saved_model"
    [[ -n "$_saved_turns" ]] && MAX_TURNS="$_saved_turns"
    if [[ -n "$_saved_timeout" ]]; then
        TIMEOUT_MINUTES="$_saved_timeout"
        TIMEOUT_SECS=$((TIMEOUT_MINUTES * 60))
    fi
}

# ── format_annotation_display ─────────────────────────────────────────────
#
# Return a parenthesized summary of active annotations for log display.

format_annotation_display() {
    local parts=()
    [[ -n "$playlist_line_model" ]] && parts+=("model=$playlist_line_model")
    [[ -n "$playlist_line_turns" ]] && parts+=("turns=$playlist_line_turns")
    [[ -n "$playlist_line_timeout" ]] && parts+=("timeout=$playlist_line_timeout")
    [[ ${#parts[@]} -gt 0 ]] && printf ' (%s)' "$(IFS=', '; echo "${parts[*]}")"
}
