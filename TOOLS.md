# Tools Catalog

A comprehensive catalog of the autonomous AI coding ecosystem.

---

## Overview

The ecosystem has evolved into a layered stack with clear responsibilities:

```
┌─────────────────────────────────────────────────────────────────┐
│                    ORCHESTRATION LAYER                          │
│  gastown        Multi-agent coordination, attribution, routing  │
│  choo-choo-ralph  Structured 5-phase workflow with harvesting  │
│  ralph-tui      GUI for task selection and ralph control        │
└─────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────┐
│                    EXECUTION LAYER                              │
│  ralph-claude-code   Core autonomous loop with safety gates    │
│  ralph-kit           Minimal polling loop (educational)         │
└─────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────┐
│                    INTELLIGENCE LAYER                           │
│  beads_viewer (bv)   Graph-theoretic triage and scoring        │
└─────────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────────┐
│                    FOUNDATION LAYER                             │
│  beads (bd)          Git-backed issue tracking with deps       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Essential Tools

### beads (bd)

**The foundation.** Git-backed issue tracker designed for AI agents.

| | |
|---|---|
| **Purpose** | Persistent task tracking with dependencies |
| **GitHub** | [github.com/anthropics/beads](https://github.com/anthropics/beads) |
| **Local** | `/Users/admin/dev/beads` |
| **Language** | Go |
| **Install** | `go install github.com/anthropics/beads/cmd/bd@latest` |

**Key Features:**
- JSONL storage (`.beads/issues.jsonl`) — git-friendly, merge-resistant
- SQLite cache for fast queries
- Dependency graph with 4 blocking types (`blocks`, `parent-child`, `conditional-blocks`, `waits-for`)
- `bd ready` — find unblocked work (the killer feature)
- Molecules — multi-step workflow templates
- Compaction — semantic summarization of old issues

**Core Commands:**
```bash
bd ready                    # Unblocked work
bd create --title "..." --priority 2
bd update <id> --status in_progress
bd close <id> --reason "..."
bd dep add <child> <parent>
bd sync                     # Sync with git
```

**Use When:** Always. This is the foundation for all other tools.

---

### beads_viewer (bv)

**The intelligence layer.** Graph-theoretic analysis and triage scoring.

| | |
|---|---|
| **Purpose** | Prioritization through graph analysis |
| **GitHub** | [github.com/anthropics/beads_viewer](https://github.com/anthropics/beads_viewer) |
| **Local** | `/Users/admin/dev/beads_viewer` |
| **Language** | Rust |
| **Install** | `cargo install beads_viewer` |

**Key Features:**
- **Triage Score** — composite 0-1 ranking from 8 weighted factors:
  - PageRank (22%) — node importance
  - Betweenness (20%) — bottleneck detection
  - BlockerRatio (13%) — downstream impact
  - Priority/Urgency/Risk/Time/Staleness (35% combined)
- Quick wins detection
- Bottleneck identification
- Cycle detection
- Machine-readable JSON output (`--robot-*` flags)

**Core Commands:**
```bash
bv --robot-triage           # Full triage JSON (recommendations, quick wins, blockers)
bv --robot-insights         # Deep graph analysis (PageRank, betweenness, cycles)
bv --robot-next             # Single top pick
bv --robot-triage | jq '.quick_wins'
```

**Warning:** Bare `bv` launches interactive TUI — **will hang AI agents**. Always use `--robot-*` flags.

**Use When:** Selecting which issue to work on next. Essential for automated task selection.

---

## Ralph Implementations

"Ralph" is a concept — autonomous AI execution loops — with multiple implementations.

### ralph-claude-code ⭐ RECOMMENDED

**Our primary choice.** Production-ready autonomous loop with comprehensive safety.

| | |
|---|---|
| **Purpose** | Core autonomous execution loop |
| **GitHub** | [github.com/anthropics/ralph-claude-code](https://github.com/anthropics/ralph-claude-code) |
| **Local** | `/Users/admin/dev/ralph-claude-code` |
| **Language** | Bash |
| **Install** | `./install.sh` → `~/.local/bin/ralph` |

**Key Features:**
- **Circuit Breaker** — 3-state machine (CLOSED/HALF_OPEN/OPEN)
  - Opens after 3 loops with no progress
  - Opens after 5 identical errors
  - Opens on 70% output decline
- **Dual-Gate Exit** — requires BOTH heuristic detection AND explicit `EXIT_SIGNAL: true`
- **Rate Limiting** — 100 calls/hour with automatic reset
- **Session Management** — 24-hour expiry, crash recovery
- **RALPH_STATUS Block** — structured signaling from Claude
- **tmux Integration** — `ralph --monitor` for live dashboard

**Core Commands:**
```bash
ralph-setup my-project      # Initialize project structure
ralph --monitor             # Run with live dashboard
ralph --calls 50            # Limit API calls
ralph --reset-circuit       # Clear circuit breaker
ralph --status              # Check current state
```

**Use When:** Overnight autonomous coding. This is the battle-tested choice.

---

### choo-choo-ralph

**Structured workflow system.** Five-phase process with knowledge harvesting.

| | |
|---|---|
| **Purpose** | Specification-driven autonomous coding |
| **GitHub** | [github.com/mj-meyer/choo-choo-ralph](https://github.com/mj-meyer/choo-choo-ralph) |
| **Local** | `/Users/admin/dev/choo-choo-ralph` |
| **Type** | Claude Code plugin |
| **Install** | `/plugin marketplace add mj-meyer/choo-choo-ralph` |

**Key Features:**
- **Five-Phase Workflow:**
  1. **Plan** (Human) — Write requirements
  2. **Spec** (Human+AI) — Generate structured task spec with `<review>` tags
  3. **Pour** (AI) — Granularize into beads (~80 tasks per feature)
  4. **Ralph** (AI) — Execute with bearings → implement → verify → commit
  5. **Harvest** (Human+AI) — Extract learnings → update CLAUDE.md, create skills
- **Formula System** — TOML templates defining multi-step workflows
- **Verification Loops** — Max 3 retries before marking blocked
- **Parallel Execution** — Multiple agents on different tasks
- **Knowledge Flywheel** — Learnings compound across sessions

**Core Commands:**
```bash
/choo-choo-ralph:install    # Set up project files
/choo-choo-ralph:spec       # Generate structured spec
/choo-choo-ralph:pour       # Granularize into beads
./ralph.sh                  # Run autonomous loop
/choo-choo-ralph:harvest    # Extract and apply learnings
```

**Use When:**
- You want maximum structure and verification
- Knowledge harvesting matters (team projects, long-term codebases)
- You prefer spec-first development

**vs ralph-claude-code:**
- More structured (5 phases vs 1 loop)
- Built-in learning extraction
- Requires more upfront planning
- Better for teams, larger features

---

### ralph-tui

**GUI for ralph.** Terminal UI for task selection and loop control.

| | |
|---|---|
| **Purpose** | Interactive ralph management |
| **GitHub** | [github.com/anthropics/ralph-tui](https://github.com/anthropics/ralph-tui) |
| **Local** | Check if cloned |
| **Language** | Go |

**Key Features:**
- Visual task selection from beads
- Integration with bv scoring (`--tracker beads-bv`)
- Epic-based execution (`--epic <id>`)
- Configuration via `.ralph-tui/config.toml`

**Core Commands:**
```bash
ralph-tui run --tracker beads --epic my-epic-id
ralph-tui run --tracker beads-bv --epic bd-xyz    # With bv scoring
```

**Use When:** You prefer GUI over CLI for task management.

---

### ralph-kit

**Educational minimal loop.** Basic polling pattern from Josh Chisholm.

| | |
|---|---|
| **Purpose** | Learning/reference implementation |
| **Source** | Referenced in beads-analysis.md |

**Pattern:**
```bash
READY_COUNT=$(bd count --status open)
IN_PROGRESS=$(bd count --status in_progress)
if [ "$READY_COUNT" = "0" ] && [ "$IN_PROGRESS" = "0" ]; then
    sleep 20; continue  # Wait for new work
fi
```

**Use When:** Learning how ralph loops work. Not for production.

---

## Advanced Orchestration

### gastown (Gas Town)

**Enterprise multi-agent orchestration.** Coordinates 4-30+ agents across multiple repositories.

| | |
|---|---|
| **Purpose** | Multi-agent coordination with full attribution |
| **GitHub** | [github.com/anthropics/gastown](https://github.com/anthropics/gastown) |
| **Local** | `/Users/admin/dev/gastown` |
| **Language** | Go |
| **Install** | `go install github.com/anthropics/gastown/cmd/gt@latest` |

**Key Concepts:**
- **Town** — Management headquarters (`~/gt/`)
- **Rigs** — Project repositories under management
- **Mayor** — Cross-rig coordinator agent
- **Deacon** — Watchdog daemon with health checks
- **Polecats** — Ephemeral worker agents
- **Refinery** — Intelligent merge queue processor
- **Witness** — Agent lifecycle monitor
- **Crew** — Long-lived named agents
- **Convoys** — Cross-rig batch tracking
- **Hooks** — Git worktree-based persistent work queues

**Key Features:**
- **Full Attribution** — Every action tracked to specific agent
- **Capability Routing** — Route work based on proven skills
- **Cross-Rig Federation** — Unified visibility across repos
- **30+ Built-in Formulas** — Automations for common workflows
- **Propulsion Principle** — "If it's on your hook, YOU RUN IT"
- **Watchdog Chain** — Deacon → Boot → recovery

**Core Commands:**
```bash
gt install ~/gt --git               # Initialize workspace
gt rig add myproject <repo>         # Add project
gt sling gt-abc gastown             # Dispatch work to polecat
gt convoy create "Feature" issues   # Track batch work
gt agents                           # List active agents
gt prime                            # Context recovery
gt doctor                           # Diagnose issues
```

**Use When:**
- Managing multiple repositories
- Need attribution and audit trails
- Running 4+ agents simultaneously
- Enterprise compliance requirements
- Cross-team coordination

**vs ralph-claude-code:**
- Far more complex (enterprise-grade)
- Multi-repo, multi-agent native
- Full attribution and routing
- Significant learning curve
- Overkill for single-project work

---

## Tool Selection Guide

### By Use Case

| Scenario | Recommended Stack |
|----------|-------------------|
| **Single project, overnight coding** | beads + bv + ralph-claude-code |
| **Structured feature development** | beads + bv + choo-choo-ralph |
| **Multi-repo enterprise** | beads + bv + gastown |
| **Learning/experimenting** | beads + ralph-kit |
| **GUI preference** | beads + bv + ralph-tui |

### By Complexity

```
Simple ──────────────────────────────────────────────── Complex

ralph-kit → ralph-claude-code → choo-choo-ralph → gastown
(learning)    (production)       (structured)     (enterprise)
```

### Compatibility Matrix

| Tool | Requires beads | Uses bv | Standalone |
|------|---------------|---------|------------|
| beads | — | No | Yes |
| beads_viewer | Yes | — | No |
| ralph-claude-code | Recommended | Optional | Yes |
| choo-choo-ralph | **Required** | Optional | No |
| ralph-tui | **Required** | Optional | No |
| gastown | **Required** | Optional | No |

---

## Related Tools (Mentioned in Research)

### Factory.ai Agent Readiness Model

Not a tool — a framework for evaluating task suitability for AI agents.

**Nine Pillars:**
1. Static analysis tooling
2. Documented build systems
3. Testing infrastructure
4. AGENTS.md documentation
5. Environment setup
6. Observability
7. Security guardrails
8. Issue templates
9. Analytics capability

**Use:** Checklist before enabling autonomous execution.

### SonarQube Quality Gates

Standard code quality tool. Recommended gates for AI code:
- Zero security vulnerabilities
- Reliability/maintainability thresholds
- Code coverage requirements
- Duplication limits
- Security hotspot review

---

## Quick Reference

### Installation Order

```bash
# 1. Foundation
go install github.com/anthropics/beads/cmd/bd@latest

# 2. Intelligence (optional but recommended)
cargo install beads_viewer

# 3. Execution (pick one)
cd ~/dev/ralph-claude-code && ./install.sh  # Recommended

# 4. Advanced (optional)
go install github.com/anthropics/gastown/cmd/gt@latest
```

### Verification

```bash
bd --version
bv --version
ralph --version
gt --version  # if installed
```

### The Golden Stack

For most users, this is the recommended combination:

```
beads (bd)           → Track work
beads_viewer (bv)    → Prioritize work
ralph-claude-code    → Execute work
```

Simple. Composable. Battle-tested.

---

## Links

| Tool | GitHub | Documentation |
|------|--------|---------------|
| beads | [anthropics/beads](https://github.com/anthropics/beads) | README + `/docs` |
| beads_viewer | [anthropics/beads_viewer](https://github.com/anthropics/beads_viewer) | README |
| ralph-claude-code | [anthropics/ralph-claude-code](https://github.com/anthropics/ralph-claude-code) | README + templates |
| choo-choo-ralph | [mj-meyer/choo-choo-ralph](https://github.com/mj-meyer/choo-choo-ralph) | `/docs/workflow.md` |
| gastown | [anthropics/gastown](https://github.com/anthropics/gastown) | `/docs/` (extensive) |
| ralph-tui | [anthropics/ralph-tui](https://github.com/anthropics/ralph-tui) | README |
