#!/usr/bin/env bash
# format_playlist_progress_test.sh — Regression tests for prompt-tail trimming.
#
# Verifies that '## Completed' is dropped (replaced by a single-line '## Recent work'
# reference) by default, and that PLAYLIST_PROGRESS_LOOKBACK opts back into a
# bounded entry list. Remaining-section lookahead behaviour is also covered.
#
# Run from project root: bash test/format_playlist_progress_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Stub the get_bead_status / get_bead_title hooks pulled in transitively;
# we drive format_playlist_progress directly from a fixture progress file.
source "$PROJECT_ROOT/lib/playlist_progress.sh"

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

contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'PASS: %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s\n  expected to contain: %q\n  actual:              %q\n' \
            "$desc" "$needle" "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'PASS: %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s\n  expected NOT to contain: %q\n  actual:                  %q\n' \
            "$desc" "$needle" "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

PROGRESS_FILE=$(mktemp /tmp/progress_XXXXXX.md)
trap 'rm -f "$PROGRESS_FILE"' EXIT

write_fixture() {
    cat > "$PROGRESS_FILE" <<'EOF'
# Playlist Progress: foo.playlist
Updated: 2026-05-08 12:00:00

## Status: 5/10 items completed

## In Progress
* [bead] foo-current — current task

## Completed
* [bead] foo-1 — first thing
* [bead] foo-2 — second thing
* [bead] foo-3 — third thing
* [bead] foo-4 — fourth thing
* [bead] foo-5 — fifth thing

## Remaining
* [bead] foo-6 — sixth
* [bead] foo-7 — seventh
* [bead] foo-8 — eighth
* [bead] foo-9 — ninth
* [bead] foo-10 — tenth
EOF
}

# ── Test 1: Default (LOOKBACK=0) drops ## Completed entries ───────────────
write_fixture
unset PLAYLIST_PROGRESS_LOOKBACK
result=$(format_playlist_progress)
not_contains "default: ## Completed header dropped" "## Completed" "$result"
contains     "default: ## Recent work reference present" \
             "## Recent work" "$result"
contains     "default: count surfaced" \
             "Last 5 bead(s) closed" "$result"
not_contains "default: completed entries dropped" \
             "* [bead] foo-1 — first thing" "$result"
contains     "default: in-progress preserved" \
             "* [bead] foo-current — current task" "$result"

# ── Test 2: LOOKBACK=2 shows last 2 completed entries ─────────────────────
PLAYLIST_PROGRESS_LOOKBACK=2
write_fixture
result=$(format_playlist_progress)
contains     "lookback=2: ## Completed header preserved" "## Completed" "$result"
not_contains "lookback=2: foo-1 omitted (oldest)" "* [bead] foo-1 — first thing" "$result"
not_contains "lookback=2: foo-2 omitted (oldest)" "* [bead] foo-2 — second thing" "$result"
not_contains "lookback=2: foo-3 omitted (oldest)" "* [bead] foo-3 — third thing" "$result"
contains     "lookback=2: foo-4 shown (last 2)"   "* [bead] foo-4 — fourth thing" "$result"
contains     "lookback=2: foo-5 shown (last 2)"   "* [bead] foo-5 — fifth thing" "$result"
unset PLAYLIST_PROGRESS_LOOKBACK

# ── Test 3: Remaining lookahead still caps at 3 ───────────────────────────
write_fixture
result=$(format_playlist_progress)
contains "lookahead=3: foo-6 shown" "* [bead] foo-6 — sixth" "$result"
contains "lookahead=3: foo-7 shown" "* [bead] foo-7 — seventh" "$result"
contains "lookahead=3: foo-8 shown" "* [bead] foo-8 — eighth" "$result"
contains "lookahead=3: overflow line"           "…plus 2 more" "$result"
not_contains "lookahead=3: foo-9 omitted"  "* [bead] foo-9 — ninth" "$result"
not_contains "lookahead=3: foo-10 omitted" "* [bead] foo-10 — tenth" "$result"

# ── Test 4: 0 completed → compact line, no ## Recent work header ──────────
cat > "$PROGRESS_FILE" <<'EOF'
# Playlist Progress: foo.playlist
Updated: 2026-05-08 12:00:00

## Status: 0/3 items completed

## In Progress
* [bead] foo-1 — first

## Completed
(none yet)

## Remaining
* [bead] foo-2 — second
* [bead] foo-3 — third
EOF
result=$(format_playlist_progress)
contains     "0 completed: compact Position line"  "Position: 1/3" "$result"
contains     "0 completed: in-progress on same line" "In Progress: [bead] foo-1 — first" "$result"
not_contains "0 completed: no Recent work header"  "## Recent work" "$result"

# ── Test 5: Bead title containing & survives intact (regression for ralph-lz8) ──
# Although & is rendered through render_template, format_playlist_progress
# also handles raw '* [bead] X — Title with & symbol' lines from the progress
# file. Must not corrupt the title.
PLAYLIST_PROGRESS_LOOKBACK=2
cat > "$PROGRESS_FILE" <<'EOF'
# Playlist Progress: foo.playlist
Updated: 2026-05-08 12:00:00

## Status: 2/4 items completed

## In Progress
* [bead] foo-cur — current

## Completed
* [bead] foo-1 — endpoints & shape drifts
* [bead] foo-2 — auth & sessions

## Remaining
* [bead] foo-3 — next
* [bead] foo-4 — last
EOF
result=$(format_playlist_progress)
contains "& in completed title preserved (entry 1)" \
         "* [bead] foo-1 — endpoints & shape drifts" "$result"
contains "& in completed title preserved (entry 2)" \
         "* [bead] foo-2 — auth & sessions" "$result"
unset PLAYLIST_PROGRESS_LOOKBACK

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
