# sutra-with-scout.sh — Outer Loop with Scout Priming

Example overnight sutra outer loop that integrates the scout for pre-execution intelligence.

## Flow

```
┌──────────────────────────────────────────────────────┐
│ Phase 1: Prime unprimed issues (scout)               │
│   scout prime --unprimed --quiet                     │
└──────────────────┬───────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────────────┐
│ Phase 2: Select next task                            │
│   Combined score = (BV triage × 0.6)                 │
│                  + (scout actionability × 0.4)        │
└──────────────────┬───────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────────────┐
│ Phase 3: Execute inner loop (Claude Code)            │
│   Prompt includes scout briefing as context          │
└──────────────────┬───────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────────────┐
│ Phase 4: Inject quality gates                        │
│   Create review + test beads as follow-ups           │
└──────────────────┬───────────────────────────────────┘
                   ↓
              Re-prime any new issues → loop back to Phase 2
```

## Source

```bash
#!/usr/bin/env bash
# ===========================================================================
# sutra-with-scout.sh — Outer loop with scout priming
# ===========================================================================
#
# This is an example overnight sutra outer loop that:
#   1. Primes any unprimed issues using the scout
#   2. Selects the next task using BV triage + scout actionability
#   3. Delegates to Claude Code (inner loop) with the scout briefing
#   4. Injects quality gate beads on completion
#   5. Repeats
#
# Usage:
#   ./sutra-with-scout.sh              # Run the loop
#   ./sutra-with-scout.sh --dry-run    # Show what would run, don't execute
#
# Prerequisites:
#   - bd (beads CLI)
#   - bv (beads-viewer, optional but recommended)
#   - scout (this repo)
#   - claude (Claude Code CLI)
#   - jq
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${1:-}"
SLEEP_INTERVAL="${SUTRA_SLEEP:-20}"
MAX_INNER_TURNS="${SUTRA_MAX_TURNS:-50}"
SCOUT_BIN="${SCOUT_BIN:-$SCRIPT_DIR/scout}"

# Weights for combining triage + actionability scores
W_TRIAGE="${W_TRIAGE:-0.6}"
W_ACTION="${W_ACTION:-0.4}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# Phase 1: Scout Priming
# ---------------------------------------------------------------------------

prime_unprimed_issues() {
    log "🔍 Phase 1: Priming unprimed issues..."
    "$SCOUT_BIN" prime --unprimed --quiet
    log "✓ Priming complete"
}

# ---------------------------------------------------------------------------
# Phase 2: Task Selection
# ---------------------------------------------------------------------------
#
# Combines BV's structural triage_score with scout's actionability_score.
# If bv is unavailable, falls back to plain bd list + scout scores.

select_next_task() {
    local next_id=""

    if command -v bv >/dev/null 2>&1; then
        # Get triage recommendations from BV
        local triage
        triage=$(bv --robot-triage 2>/dev/null || echo '{"triage":{"recommendations":[]}}')

        # Score each candidate by combining triage + actionability
        next_id=$(echo "$triage" | jq -r '
            .triage.recommendations[].id
        ' 2>/dev/null | while read -r cid; do
            [[ -z "$cid" ]] && continue
            local t_score
            t_score=$(echo "$triage" | jq -r --arg id "$cid" '
                .triage.recommendations[] | select(.id == $id) | .triage_score // 0.5
            ')
            local a_score
            a_score=$("$SCOUT_BIN" score "$cid" 2>/dev/null || echo "0.5")

            # Combined score
            local combined
            combined=$(echo "$t_score * $W_TRIAGE + $a_score * $W_ACTION" | bc -l 2>/dev/null || echo "0.5")

            echo "$combined $cid"
        done | sort -rn | head -1 | awk '{print $2}')
    fi

    # Fallback: just pick the first open issue
    if [[ -z "$next_id" ]]; then
        next_id=$(bd list --status open 2>/dev/null | grep -oE 'bd-[a-f0-9]+' | head -1)
    fi

    echo "$next_id"
}

# ---------------------------------------------------------------------------
# Phase 3: Inner Loop Execution
# ---------------------------------------------------------------------------

run_inner_loop() {
    local id="$1"
    local title="$2"
    local body="$3"
    local briefing="$4"

    local prompt="Implement the following task. When complete, output <promise>COMPLETE</promise>.

Task: $title

Description:
$body"

    # Inject scout briefing if available
    if [[ -n "$briefing" ]]; then
        prompt="$prompt

Scout Briefing (from prior reconnaissance — verify before relying on it):
$briefing"
    fi

    prompt="$prompt

Requirements:
- Implement the described change
- Run existing tests to verify nothing breaks
- Add tests for new behaviour where appropriate
- Commit your changes with a descriptive message

Output <promise>COMPLETE</promise> when done."

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "  [DRY RUN] Would run claude with prompt for: $title"
        log "  [DRY RUN] Briefing: ${briefing:-none}"
        return 0
    fi

    # Mark in progress
    bd update "$id" --status in_progress 2>/dev/null || true

    # Run Claude Code inner loop
    claude -p "$prompt" --max-turns "$MAX_INNER_TURNS"

    # Mark complete
    bd update "$id" --status closed 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Phase 4: Quality Gate Injection
# ---------------------------------------------------------------------------

inject_quality_gates() {
    local id="$1"
    local title="$2"

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "  [DRY RUN] Would create review + test gates for: $title"
        return 0
    fi

    bd create \
        --title "Review: $title" \
        --description "Review implementation of parent task. Check: code quality, edge cases, error handling, adherence to requirements." \
        --label sutra-review \
        2>/dev/null || true

    bd create \
        --title "Test: $title" \
        --description "Verify test coverage for parent task. Check: unit tests, integration tests, coverage >80%, regression tests." \
        --label sutra-test \
        2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main Loop
# ---------------------------------------------------------------------------

main() {
    log "🚀 Sutra outer loop starting (scout-enhanced)"
    log "   Model: Claude Code inner loop"
    log "   Scout: $SCOUT_BIN"
    log "   Weights: triage=${W_TRIAGE}, actionability=${W_ACTION}"
    log "   Sleep: ${SLEEP_INTERVAL}s between cycles"
    [[ "$DRY_RUN" == "--dry-run" ]] && log "   ⚠️  DRY RUN MODE"
    echo ""

    # --- Phase 1: Prime before the loop starts ---
    prime_unprimed_issues
    echo ""

    # --- Main loop ---
    while true; do
        # Select next task
        local next_id
        next_id=$(select_next_task)

        if [[ -z "$next_id" ]]; then
            log "💤 No tasks ready. Sleeping ${SLEEP_INTERVAL}s..."
            sleep "$SLEEP_INTERVAL"
            continue
        fi

        # Read task details
        local title body briefing
        title=$(bd show "$next_id" 2>/dev/null | head -1 | sed 's/^#* *//' || echo "$next_id")
        body=$(bd show "$next_id" 2>/dev/null || echo "See bead $next_id")
        briefing=$("$SCOUT_BIN" briefing "$next_id" 2>/dev/null || echo "")

        log "📋 Next task: $next_id — $title"
        [[ -n "$briefing" ]] && log "   Scout says: $(echo "$briefing" | head -c 120)..."

        # Execute inner loop
        run_inner_loop "$next_id" "$title" "$body" "$briefing"

        # Inject quality gates
        inject_quality_gates "$next_id" "$title"

        log "✅ Completed: $next_id"

        # Re-prime any new issues that appeared during execution
        "$SCOUT_BIN" prime --unprimed --quiet 2>/dev/null || true

        # Brief pause before next cycle
        sleep 2
    done
}

main "$@"
```

## Usage

```bash
# Overnight run
./sutra-with-scout.sh

# Preview what would happen
./sutra-with-scout.sh --dry-run

# Customise via environment
SUTRA_MAX_TURNS=30 W_TRIAGE=0.7 W_ACTION=0.3 ./sutra-with-scout.sh
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SUTRA_SLEEP` | `20` | Seconds to sleep when no tasks available |
| `SUTRA_MAX_TURNS` | `50` | Max Claude Code turns per task |
| `SCOUT_BIN` | `./scout` | Path to the scout executable |
| `W_TRIAGE` | `0.6` | Weight for BV structural score |
| `W_ACTION` | `0.4` | Weight for scout actionability score |
