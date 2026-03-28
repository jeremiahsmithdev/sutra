# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Ralph is an autonomous AI coding system — a bash outer loop that feeds beads issues to Claude Code one at a time. ~1,300 lines of bash across 16 library files implementing the core loop, circuit breaker, monitoring dashboard, remote execution, and branch management.

**Philosophy:** Read [[PHILOSOPHY.md]] first. The bitter lesson applies: simple deterministic orchestration + a smart model beats clever multi-agent systems. The outer loop is a for-loop with a sort. All intelligence lives in the inner loop (Claude).

## Running Ralph

```bash
./ralph                          # Run the loop (picks tasks from br ready)
./ralph --dry-run                # Show next task without executing
./ralph --max-tasks 3            # Stop after 3 completed tasks
./ralph --max-loops 10           # Stop after 10 Claude invocations
./ralph --timeout 20             # 20 minutes per invocation (default: 10)
./ralph --scope "auth"           # Only work issues matching regex
./ralph --model sonnet           # Override model (default: haiku)
./ralph --sandbox                # Bubblewrap isolation (Linux only)
./ralph --monitor                # Live dashboard (run in separate terminal)
./ralph --remote oracle          # Run on remote server via SSH+tmux
./ralph --status                 # Print current .ralph_state
./ralph --reset                  # Clear circuit breaker and counters
```

Per-project overrides go in `.ralph.conf` (sourced by `config.sh`). CLI flags override both defaults and `.ralph.conf`.

## Prerequisites

Ralph requires: `br` (beads_rust), `claude` (Claude Code CLI), `jq`, `timeout`/`gtimeout`. Checked by `lib/prereqs.sh`.

## Architecture

### The Main Loop (45 lines)

`ralph` sources `lib/loader.sh` which loads all 16 library files. The entire loop is:

```
while true:
    check_exit_conditions  →  max tasks/loops/circuit breaker
    select_task            →  br ready --json, skip epics, apply --scope
    claim_task             →  br update --status in_progress
    build_prompt           →  task details + branch instructions + rules
    invoke_claude          →  claude -p with timeout, stream-json output
    check_bead_status      →  query br for current status
    update_circuit_breaker →  track no-progress streaks
    handle_task_outcome    →  closed → bump counter; epic auto-close
    save_state             →  persist to .ralph_state
```

### Library Files (`lib/`)

Load order matters — defined in `loader.sh`:

| File | Responsibility |
|------|---------------|
| `config.sh` | Default globals (MAX_LOOPS=50, TIMEOUT_MINUTES=10, MODEL=haiku, etc.) |
| `utils.sh` | `log()`, `save_state()`/`load_state()`, ANSI colors, `commit_beads_if_dirty()` |
| `args.sh` | CLI parsing → globals. Handles --help/--status/--reset early exits |
| `prereqs.sh` | Dependency checks, `ensure_ralph_branch()` |
| `tasks.sh` | `pick_next_task()`, `claim_task()`, `get_task_details()`, `get_branch_context()`, `slugify()` |
| `prompt.sh` | `build_prompt()` — constructs the Claude prompt with task + branch + rules |
| `invoke.sh` | `invoke_claude()` — runs `claude -p` with timeout, captures exit code |
| `circuit_breaker.sh` | 3-state machine: CLOSED →(2 no-progress)→ HALF_OPEN →(3)→ OPEN (halt) |
| `task_outcome.sh` | `handle_task_outcome()`, `mark_needs_review()`, `maybe_close_epic()` |
| `monitor.sh` | Live dashboard — double-buffered, 1s refresh, reads .ralph_state + br queries |
| `remote.sh` | `run_remote()` — rsync + SSH + tmux session management |
| `sandbox.sh` | Bubblewrap filesystem isolation wrapper |
| `format_stream.sh` | jq filter: stream-json → human-readable (text, tool uses, cost) |
| `splash.sh` | ASCII art |
| `cleanup.sh` | Exit trap — session summary |

### Key Global Variables

State flows through globals (set in `config.sh`, modified by `args.sh`, persisted via `save_state()`):

- `circuit` / `no_progress_count` — circuit breaker state
- `total_tasks_completed` / `total_loops` — progress counters
- `current_task` — retry tracking (non-empty = retrying same task)
- `tid` / `task_details` — current task being worked
- `CLAUDE_PID` — for interrupt handling

### Branch Strategy

`get_branch_context()` in `tasks.sh` determines where Claude works:
- **Standalone task** → `ralph` branch
- **Task in epic** → `ralph-<epic-slug>` branch (from `ralph`)
- **Task in epic that depends on another epic** → `ralph-<epic-slug>` (from `ralph-<dep-epic-slug>`)

### Circuit Breaker

Progress = bead status changed (closed or reopened). No progress = still in_progress after Claude finishes.

```
CLOSED ──[2 no-progress]──► HALF_OPEN ──[3 no-progress]──► OPEN (halt)
  ▲ progress                    ▲ progress
  └─────────────────────────────┘
```

Recovery: `ralph --reset` only. No automatic recovery from OPEN.

### Verification Workflow

On task close, ralph adds `verified:needs-review` label. Human reviews with `bnr` (list needing review) and `bV` (mark verified). Epic auto-closes when all children are closed.

## Reference Projects

Under `reference-projects/` — read for context, don't modify:

| Directory | What It Is |
|-----------|-----------|
| `beads/` | bd source — git-backed issue tracker (legacy reference) |
| `beads_viewer/` | bv source — graph scoring (PageRank, betweenness) |
| `ralph-claude-code/` | Reference autonomous loop implementation |
| `gastown/` | Enterprise multi-agent orchestration |
| `choo-choo-ralph/` | 5-phase workflow with knowledge harvesting |

## Key Tool Commands

**beads_rust (br):** `br ready`, `br show <id> --json`, `br update <id> --status in_progress`, `br close <id> --reason "..."`, `br dep add <child> <parent>`

**beads_viewer (bv):** Always use robot flags. **Never run bare `bv`** — it launches a TUI that hangs agents.
```bash
bv --robot-triage    # Full triage JSON
bv --robot-next      # Single top pick
bv --robot-insights  # Graph analysis
```

## Not Yet Implemented

From [[PLAN.md]] — designed but not coded:
- **BV integration** for task selection (currently just `br ready`)
- **Metrics collection** to `.ralph/metrics.db` (schema in [[metrics.md]])
- **Scout system** — pre-execution reconnaissance (design in [[scout/]])
- **Harvest tooling** — slash commands for morning review
- **Quality gate injection** — auto-create review/test beads after completion

## Document Map

| Document | Purpose |
|----------|---------|
| [[PHILOSOPHY.md]] | Founding principles — read first |
| [[PLAN.md]] | Build order checklist |
| [[GUIDE.md]] | Complete operational guide (756 lines) |
| [[TOOLS.md]] | Ecosystem tool catalog |
| [[outer-loop.md]] | Research on orchestrator options |
| [[AI-TRIAGE.md]] | Semantic actionability scoring concept |
| [[metrics.md]] | SQLite instrumentation schema |
| [[Harvest.md]] | Morning review process |
| [[BEADS_VERIFICATION_WORKFLOW.md]] | Human verification tracking |
| [[scout/]] | Reconnaissance system design |
