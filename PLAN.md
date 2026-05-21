# Plan

Build order for the sutra framework.

See also: [[PHILOSOPHY.md]] | [[CLAUDE.md]]

---

## Checklist

- [ ] **Inner loop** — Claude Code execution with safety gates ([[outer-loop.md#Option A|reference]])
- [ ] **Outer loop** — Deterministic task selection using beads + bv ([[outer-loop.md]])
- [ ] **Metrics collection** — SQLite instrumentation at each stage ([[metrics.md]])
- [ ] **Scout integration** — Optional reconnaissance before execution ([[scout/]])
- [ ] **Harvest tooling** — Slash commands for morning review ([[Harvest.md]])

---

## Inner Loop

Wrap Claude Code invocation with:
- Timeout per task
- Exit detection (dual-gate: heuristic + explicit signal)
- Basic progress tracking (files changed, tests status)

Start minimal. The inner loop does not select tasks — it receives one task and works until done or blocked.

## Outer Loop

A bash while-loop that:
1. Queries `bv --robot-triage` for ranked tasks
2. Picks the top ready task (`bd ready` as fallback)
3. Marks in_progress, delegates to inner loop
4. On completion: closes bead, injects quality gate beads (review + test)
5. Repeats

No AI in the outer loop. Graph algorithms do the prioritisation. See [[outer-loop.md]] for the research — Option A (deterministic bash + bv) is the recommended path.

## Metrics Collection

Instrument the loops to write to `.sutra/metrics.db` at:
- Task selection (bv scores, timestamp)
- Task start (timestamp)
- Task completion (duration, files modified, exit reason)
- Harvest review (verdict)

Time-based metrics are primary — most tasks complete in one iteration, so duration matters more than iteration count. See [[metrics.md]] for schema and queries.

Only build after core loops work. Sutra functions without scouts.

## Scout Integration

Optional layer between task selection and execution. A **scout** is an LLM agent (Claude Haiku, headless) dispatched to investigate one bead issue.

**Reconnaissance** (deterministic):
- File existence, grep, git log, test coverage, WIP conflicts
- Packaged as JSON context for the scout

**Scout assessment** (LLM):
- Actionability score, difficulty, entry points, briefing
- Time prediction informed by competing baseline formulas

**Time prediction** ([[scout/prediction.md]]):
- 5 formulas compute baselines from historical data
- Baselines + raw metrics passed to scout
- Scout makes final prediction using qualitative judgment
- Track all formula predictions; compare accuracy at harvest; pick winner

**Parallel execution**: Up to `SCOUT_MAX_PARALLEL` scouts run concurrently via `claude --model haiku -p`.

## Harvest Tooling

Slash commands for the morning review:
- `/harvest-anomalies` — Surface issues where time predictions diverged from actuals
- `/harvest-formulas` — Compare prediction formula accuracy, identify winner
- `/harvest-analyse <issue_id>` — Point Claude at scout report + git diff + metrics
- `/harvest-record <issue_id> <verdict>` — Log review outcome to metrics.db

Updates base_minutes from historical averages. Refines formula selection over time. Keep tooling simple — harvest is a human checkpoint.

## Verification Workflow

Already implemented via beads state machine. See [[BEADS_VERIFICATION_WORKFLOW.md]].

Shell aliases (`bnr`, `bV`, `bmr`, `buv`) provide the interface. Core commands:

```bash
bd set-state <id> verified=needs-review --reason "..."  # Sutra sets on close
bd set-state <id> verified=yes --reason "..."           # Human sets after testing
bd state <id> verified                                   # View state + reason
```

The workflow ensures:
- Sutra marks all autonomous work for review with test instructions
- Humans verify using the provided instructions before trusting the work
- An audit trail records who verified what and when (event issues)
