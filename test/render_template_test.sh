#!/usr/bin/env bash
# render_template_test.sh — Regression test for render_template placeholder leak.
#
# Verifies that {{KEY}} tokens inside substituted VALUES are not treated as new
# placeholders in subsequent iterations. This prevents bead titles, task
# descriptions, and playlist progress blocks from injecting unfilled {{...}}
# tokens into rendered prompts.
#
# Run from project root: bash test/render_template_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Inline render_template so the test can run standalone without sourcing
# the full utils.sh (which has side effects like color-var assignment).
render_template() {
    local template_file="$1"; shift
    local content pair key value _safe_value
    local _sentinel_brace=$'\x01\x01'
    local _sentinel_amp=$'\x02\x02'
    content=$(<"$template_file")
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        _safe_value="${value//\{\{/$_sentinel_brace}"
        _safe_value="${_safe_value//&/$_sentinel_amp}"
        content="${content//\{\{$key\}\}/$_safe_value}"
    done
    content="${content//$_sentinel_brace/\{\{}"
    content="${content//$_sentinel_amp/\&}"
    printf '%s' "$content"
}

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf 'PASS: %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s\n' "$desc"
        printf '  expected: %q\n' "$expected"
        printf '  actual:   %q\n' "$actual"
        FAIL=$((FAIL + 1))
    fi
}

tmpfile=$(mktemp /tmp/tmpl_XXXXXX.txt)
trap 'rm -f "$tmpfile"' EXIT

# ── Test 1: Basic substitution ────────────────────────────────────────────
printf '{{GREETING}} world' > "$tmpfile"
result=$(render_template "$tmpfile" "GREETING=hello")
check "basic substitution" "hello world" "$result"

# ── Test 2: PLAYLIST_PROGRESS value contains {{PROMPT_TEXT}} ─────────────
# Root-cause scenario: bead title includes "{{PROMPT_TEXT}}" literally.
# When PLAYLIST_PROGRESS is substituted after PROMPT_TEXT, the injected
# {{PROMPT_TEXT}} must NOT be re-expanded — it should survive as literal text.
printf 'before {{PROMPT_TEXT}} after\n{{PLAYLIST_PROGRESS}}' > "$tmpfile"
result=$(render_template "$tmpfile" \
    "PROMPT_TEXT=gate content" \
    "PLAYLIST_PROGRESS=bead title with {{PROMPT_TEXT}} in it")
check "{{PROMPT_TEXT}} in PLAYLIST_PROGRESS value preserved" \
    "before gate content after
bead title with {{PROMPT_TEXT}} in it" \
    "$result"

# ── Test 3: Gate context "foo {{DETAILS}} bar" passed as PROMPT_TEXT ─────
# Acceptance-criteria scenario: "> #DOCUMENT foo {{DETAILS}} bar"
# The {{DETAILS}} in the context must appear literally in the output.
printf '{{PROMPT_TEXT}}' > "$tmpfile"
result=$(render_template "$tmpfile" \
    "PROMPT_TEXT=Edge Cases {{DETAILS}} Limitations")
check "{{DETAILS}} inside PROMPT_TEXT value preserved literally" \
    "Edge Cases {{DETAILS}} Limitations" \
    "$result"

# ── Test 4: Earlier value injects a placeholder for a later key ───────────
# A's value contains {{B}}. The standalone {{B}} in the template IS expanded;
# the {{B}} injected by A's value is NOT expanded (it arrived too late).
printf '{{A}}---{{B}}' > "$tmpfile"
result=$(render_template "$tmpfile" \
    "A=value with {{B}} inside" \
    "B=real-b")
check "injected {{B}} NOT expanded; original {{B}} IS expanded" \
    "value with {{B}} inside---real-b" \
    "$result"

# ── Test 5: Multiple {{}} tokens in a single value ───────────────────────
printf '{{PLAYLIST_PROGRESS}}' > "$tmpfile"
result=$(render_template "$tmpfile" \
    "PLAYLIST_PROGRESS=* [bead] ralph-y4i.6 — HV: {{DETAILS}} mangled to {{PROMPT_TEXT}}")
check "both {{DETAILS}} and {{PROMPT_TEXT}} in value preserved" \
    "* [bead] ralph-y4i.6 — HV: {{DETAILS}} mangled to {{PROMPT_TEXT}}" \
    "$result"

# ── Test 6: Multi-line value with embedded placeholders ──────────────────
printf '{{DETAILS}}' > "$tmpfile"
result=$(render_template "$tmpfile" \
    "DETAILS=line one
line two with {{TASK_ID}} embedded
line three")
check "multi-line value with {{TASK_ID}} preserved" \
    "line one
line two with {{TASK_ID}} embedded
line three" \
    "$result"

# ── Test 7: Ampersand in value preserved literally ───────────────────────
# Bash 5.x's ${var//pat/repl} treats `&` in the replacement as a back-reference
# to the matched pattern (sed-like, undocumented). A bead title containing `&`
# would otherwise render as the placeholder name, e.g.
#   title="A & B" → rendered as "A {{TITLE}} B".
printf '{{TITLE}}' > "$tmpfile"
result=$(render_template "$tmpfile" "TITLE=Fix endpoints & shape drifts")
check "& in value preserved literally (no back-reference expansion)" \
    "Fix endpoints & shape drifts" \
    "$result"

# ── Test 8: Multiple ampersands and surrounding placeholders ─────────────
printf '{{A}} | {{B}}' > "$tmpfile"
result=$(render_template "$tmpfile" \
    "A=tom & jerry & spike" \
    "B=foo&bar")
check "multiple & in multiple values preserved" \
    "tom & jerry & spike | foo&bar" \
    "$result"

# ── Test 9: Verify against real prompt_raw.txt (integration) ─────────────
raw_tmpl="$PROJECT_ROOT/templates/prompt_raw.txt"
if [[ -f "$raw_tmpl" ]]; then
    result=$(render_template "$raw_tmpl" \
        "PROMPT_TEXT=check {{DETAILS}} preserved" \
        "PRIOR_TASK_CONTEXT=" \
        "WORKING_DIR=/tmp" \
        "CURRENT_BRANCH=main" \
        "RECENT_COMMITS=abc123 commit" \
        "FILE_MAP=" \
        "PLAYLIST_PROGRESS=bead title with {{PROMPT_TEXT}} in it")
    if echo "$result" | grep -qF '{{DETAILS}}'; then
        check "prompt_raw.txt: {{DETAILS}} in PROMPT_TEXT value preserved" "pass" "pass"
    else
        check "prompt_raw.txt: {{DETAILS}} in PROMPT_TEXT value preserved" "should contain {{DETAILS}}" "not found"
    fi
    if echo "$result" | grep -qF '{{PROMPT_TEXT}}'; then
        check "prompt_raw.txt: {{PROMPT_TEXT}} in PLAYLIST_PROGRESS value preserved" "pass" "pass"
    else
        check "prompt_raw.txt: {{PROMPT_TEXT}} in PLAYLIST_PROGRESS value preserved" "should contain {{PROMPT_TEXT}}" "not found"
    fi
else
    printf 'SKIP: templates/prompt_raw.txt not found\n'
fi

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
