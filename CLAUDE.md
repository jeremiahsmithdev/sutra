# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

This is an **early-stage research and documentation workspace** for a personal ralph framework — an autonomous AI coding system built on beads, beads_viewer, and Claude Code.

**Current state:** Theory, tooling options, and architectural decision drafts. No primary implementation exists yet.

**Goal:** Build ralph loops (inner and outer) using beads as the foundation.

**Sub-repositories** (`beads/`, `beads_viewer/`, `ralph-claude-code/`, `gastown/`, `choo-choo-ralph/`) are **reference tools**, not active development targets. Read their docs for context but don't modify them unless explicitly instructed.

## Philosophy — Read [[PHILOSOPHY.md]] First

The bitter lesson applies: general methods that scale with computation beat specialised approaches. Do not build elaborate multi-agent systems. Build a loop.

### Two Loops, Two Jobs

**Outer loop** — Deterministic. Selects what to work on. Reads from beads, consults triage scores, picks the next task. It is a for-loop with a sort. It does not reason, deliberate, or improvise.

**Inner loop** — The agent (Claude). Takes a task, explores, implements, tests, self-corrects. All intelligence lives here. All complexity lives here.

**Do not move intelligence from the inner loop into the outer loop.** The inner loop gets better every time the model improves. The outer loop does not.

### Key Principles

- **Beads are the source of truth** — All work tracked in beads. No second source of truth.
- **Deterministic where possible** — Quality gates don't need AI. Task selection uses graph algorithms (PageRank, betweenness), not LLM judgment.
- **Backpressure over direction** — Engineer an environment where wrong outputs get rejected automatically (tests, linters, type checkers).
- **Store artefacts, not decisions** — Store evidence and assessments, not routing logic.
- **Fail predictably** — Boring failures are debuggable. Clever failures are not.

## Document Map

| Document | Purpose |
|----------|---------|
| [[PHILOSOPHY.md]] | Founding principles — read first |
| [[PLAN.md]] | Build order checklist |
| [[GUIDE.md]] | Complete operational guide for beads + bv + ralph |
| [[TOOLS.md]] | Catalog of all ecosystem tools with recommendations |
| [[outer-loop.md]] | Research on outer loop orchestrator options |
| [[AI-TRIAGE.md]] | Concept: layering semantic investigation on structural scoring |
| [[metrics.md]] | Data-driven workflow calibration (SQLite schema, bottleneck queries) |
| [[Harvest.md]] | The morning review process |
| [[BEADS_VERIFICATION_WORKFLOW.md]] | Human verification tracking for autonomous work |
| [[ralph-overnight-guide.md]] | Technical setup for overnight development |
| [[beads-analysis.md]] | Research synthesis on the beads ecosystem |
| [[scout/]] | Reconnaissance scouts — optional pre-execution investigation |
| [[scout/prediction.md]] | Time prediction: deterministic baseline + scout judgment |

## The Stack (Target Architecture)

```
┌─────────────────────────────────────────────────────────────────┐
│                    ORCHESTRATION (optional)                      │
│  gastown, choo-choo-ralph, ralph-tui                            │
└─────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────┐
│                    OUTER LOOP (to be built)                      │
│  Deterministic task selection using beads + bv                  │
└─────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────┐
│                    INNER LOOP (to be built)                      │
│  Claude Code execution with safety gates                        │
└─────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────┐
│                    INTELLIGENCE                                  │
│  beads_viewer (bv) — PageRank + betweenness scoring             │
└─────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────┐
│                    FOUNDATION                                    │
│  beads (bd) — Git-backed issue tracking + dependencies          │
└─────────────────────────────────────────────────────────────────┘
```

## Reference Tools

### beads (bd) — Foundation

Git-backed issue tracking with dependencies. The killer feature is `bd ready` — find unblocked work.

```bash
bd ready                    # Find unblocked work
bd create --title "..." --priority 2
bd update <id> --status in_progress
bd close <id> --reason "..."
bd dep add <child> <parent>
bd sync                     # Always before leaving
```

### beads_viewer (bv) — Intelligence Layer

Graph-theoretic triage scoring. **Never run bare `bv`** — it launches a TUI that hangs agents.

```bash
bv --robot-triage           # Full triage JSON
bv --robot-insights         # Graph analysis (PageRank, betweenness, cycles)
bv --robot-next             # Single top pick
```

### ralph-claude-code — Reference Execution Layer

The reference autonomous loop with circuit breakers, dual-gate exit, and rate limiting.

```bash
ralph --monitor             # Run with dashboard
ralph --reset-circuit       # Clear circuit breaker
```

## Session Protocol

End every session with:

```bash
git status              # Check for unstaged changes
git add <files>         # Stage code changes
bd sync                 # Commit beads state (if using beads)
git commit -m "..."     # Commit code
git push                # Work is NOT done until pushed
```

## The Harvest

After overnight runs, review in the morning. See [[Harvest.md]] for the full routine.

**Data-driven phase:** Query [[metrics.md]] to surface anomalies — where predictions diverged from actuals, where tasks failed unexpectedly, where scores didn't correlate with outcomes.

**Qualitative phase:** Point AI at the flagged anomalies to identify root causes and suggest fixes to scout logic, prompts, or workflow configuration.

**Code review phase:** Merge or revert (don't "fix it up"), groom backlog, update guidance.
