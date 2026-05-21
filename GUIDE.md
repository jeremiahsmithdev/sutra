# The Sutra System: Autonomous AI Coding with Beads & BV

A practical guide for human-AI collaborative development using the day/night workflow pattern.

---

## Philosophy

> "Express constraints, not sequences. You're not following a plan; you're executing a constraint graph."
> — Steve Yegge, creator of beads

The Sutra System combines three Unix-philosophy tools that compose beautifully:

| Tool | Purpose | Operates On |
|------|---------|-------------|
| **beads (br)** | Git-backed issue tracking with dependencies | Constraint graphs |
| **beads_viewer (bv)** | Graph-theoretic triage and prioritization | Issue analysis |
| **sutra** | Autonomous execution loops with safety gates | Claude Code sessions |

Together they solve the "50 First Dates" problem—AI agents losing memory between sessions—through structured, queryable task graphs that persist across context compaction.

---

## The Day/Night Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                         DAYTIME (Human)                         │
│                                                                 │
│  1. Review overnight work: bd list --status closed --since 24h │
│  2. Triage new issues: bv --robot-triage                       │
│  3. Plan new work: bd create, bd dep add                       │
│  4. Set priorities: bd update <id> --priority 0                │
│  5. Clear blockers: bd update <id> --status open               │
│  6. Sync before leaving: bd sync && git push                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓ sunset
┌─────────────────────────────────────────────────────────────────┐
│                        NIGHTTIME (Sutra)                        │
│                                                                 │
│  sutra --monitor                                                │
│                                                                 │
│  Loop:                                                          │
│    1. bv --robot-triage → pick highest actionable issue        │
│    2. br update <id> --status in_progress                      │
│    3. Execute implementation                                    │
│    4. Run tests, verify                                         │
│    5. br close <id> + br label add <id> verified:needs-review  │
│    6. Check exit conditions → continue or complete             │
│                                                                 │
│  Safety: Circuit breakers, cost limits, dual-gate exit         │
└─────────────────────────────────────────────────────────────────┘
                              ↓ sunrise
┌─────────────────────────────────────────────────────────────────┐
│                      MORNING (Human Review)                     │
│                                                                 │
│  1. Check sutra logs: tail .sutra/logs/sutra.log               │
│  2. Verify closed work: bnr → test → bV                        │
│  3. Harvest learnings → update CLAUDE.md                       │
│  4. Plan next night's work                                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Part 1: Beads (bd) — The Constraint Graph

### Core Concepts

**Beads is an execution tool, not a planning tool.** It stores issues as a JSONL file (`.beads/issues.jsonl`) that's git-tracked, with SQLite as a local cache for fast queries.

**Issue Anatomy:**
```
ID:           bd-a3f8e9 (hash-based, collision-resistant)
Title:        Implement user authentication
Status:       open | in_progress | blocked | deferred | closed
Priority:     0-4 (P0=critical, P4=backlog)
Type:         bug | feature | task | epic | chore
Dependencies: blocks, blocked-by, parent-child, related
```

### Essential Commands

```bash
# Discovery
bd ready                    # Find unblocked work (THE key command)
bd ready --priority 0       # Only P0 issues
bd ready --limit 5          # Top 5 ready issues
bd blocked                  # Show blocked issues
bd list                     # All issues
bd show <id>                # Full details + audit trail

# Workflow
bd create --title "..." --type task --priority 2
bd update <id> --status in_progress
bd close <id> --reason "implemented"
bd reopen <id>

# Dependencies (the power feature)
bd dep add <child> <parent>         # child depends on parent
bd dep <blocker> --blocks <blocked> # explicit blocking
bd dep remove <id> <dep-id>
bd dep tree <id>                    # Visualize graph
bd dep cycles                       # Detect circular deps

# Maintenance
bd sync                     # Sync with git remote
bd compact --days 90        # Archive old closed issues
bd stats                    # Project health metrics
```

### Dependency Types

**Blocking (affects `bd ready`):**
- `blocks` — A blocks B, B cannot start until A closes
- `parent-child` — Hierarchical, child waits for parent
- `conditional-blocks` — B runs only if A fails
- `waits-for` — Fanout gate for dynamic children

**Associative (informational only):**
- `related` — Loose connection
- `discovered-from` — Provenance tracking
- `duplicates`, `supersedes` — Version chains

### Priority System

| Level | Meaning | Usage |
|-------|---------|-------|
| P0 | Critical | Production down, security issues |
| P1 | High | Major feature blockers |
| P2 | Medium | Standard work (default) |
| P3 | Low | Nice-to-have |
| P4 | Backlog | Someday/maybe |

**Rule:** Use numbers, not words: `--priority 0` not `--priority critical`

### Session Protocol (MANDATORY)

End every session with:
```bash
git status              # Check for unstaged changes
git add <files>         # Stage code changes
bd sync                 # Commit beads state
git commit -m "..."     # Commit code
git push                # Push to remote — work is NOT done until pushed
```

---

## Part 2: Beads Viewer (bv) — The Intelligence Layer

### The Triage Score

BV computes a **composite 0-1 score** from graph analysis:

```
TriageScore = BaseImpactScore × 0.70 + UnblockBoost × 0.15 + QuickWinBoost × 0.15
```

**BaseImpactScore Components (8 factors):**

| Component | Weight | What It Measures |
|-----------|--------|------------------|
| PageRank | **22%** | Node importance in dependency graph |
| Betweenness | **20%** | How often task sits on critical paths |
| BlockerRatio | 13% | Downstream tasks unblocked |
| Priority | 10% | Original P0-P4 designation |
| TimeToImpact | 10% | Critical path depth (70%) + time estimate (30%) |
| Urgency | 10% | Label signals + time decay (7-day half-life) |
| Risk | 10% | Volatility indicators |
| Staleness | 5% | Age-based surfacing |

**Score Interpretation:**
- `> 0.7` — Critical, address immediately
- `0.3-0.7` — Standard backlog
- `< 0.3` — Safe to defer

### Essential Commands

```bash
# For AI agents (machine-readable JSON)
bv --robot-triage           # Unified triage: recommendations, quick wins, blockers
bv --robot-insights         # Deep graph analysis: PageRank, betweenness, cycles
bv --robot-next             # Single top pick (minimal output)
bv --robot-triage-by-track  # Grouped by topological depth
bv --robot-triage-by-label  # Grouped by primary label

# Parsing triage output
bv --robot-triage | jq '.recommendations[:5]'    # Top 5 recommendations
bv --robot-triage | jq '.quick_wins'             # Easy high-impact items
bv --robot-triage | jq '.blockers_to_clear'      # Bottleneck issues
bv --robot-triage | jq '.project_health'         # Overall metrics

# Parsing insights output
bv --robot-insights | jq '.bottlenecks'          # High betweenness nodes
bv --robot-insights | jq '.cycles'               # Circular dependencies
bv --robot-insights | jq '.articulation_points'  # Cut vertices
bv --robot-insights | jq '.velocity'             # Closure rates
```

**CRITICAL WARNING:** Bare `bv` (no flags) launches an interactive TUI that **hangs AI agents**. Always use `--robot-*` flags for machine consumption.

### Quick Wins Detection

BV identifies quick wins through:

```
QuickWinScore = (unblocks × 0.4) + (simplicity × 0.4) + (priority × 0.2)

Where:
  unblocks = log₂(downstream_count + 1)  # Prevents huge fan-out domination
  simplicity = inverse of blocker ratio   # Low blockers = simple
  priority = P0/P1 bonus                  # High priority gets boost
```

Quick wins are issues that are:
- Low complexity (few/no blockers)
- High impact (unblock many downstream)
- Often high priority

### Graph Insights

```bash
# Find bottlenecks (high betweenness = critical path chokepoints)
bv --robot-insights | jq '.bottlenecks[:3]'

# Find keystones (high PageRank = foundational issues)
bv --robot-insights | jq '.keystones[:3]'

# Detect cycles (circular dependencies that must be broken)
bv --robot-insights | jq '.cycles'

# What-if analysis (which issues unblock the most work)
bv --robot-insights | jq '.top_what_ifs[:5]'
```

---

## Part 3: Sutra — The Autonomous Loop

### Core Architecture

Sutra is a bash loop that repeatedly invokes Claude Code with safety gates:

```
┌────────────────────────────────────────────────────────────────┐
│                     SUTRA MAIN LOOP                            │
│                                                                │
│  while true; do                                                │
│    1. Check circuit breaker (is it open?)                     │
│    2. Check cost limits                                       │
│    3. Build context (loop #, bead details, branch context)    │
│    4. Execute Claude Code with timeout                        │
│    5. Check bead status                                       │
│    6. Update circuit breaker                                  │
│    7. Check exit conditions                                   │
│  done                                                          │
└────────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
project/
├── .sutra/
│   ├── config              # Project defaults (model, timeout, etc.)
│   ├── state               # Loop state (circuit breaker, playlist pos)
│   ├── logs/
│   │   ├── sessions/       # Per-session logs
│   │   └── stream/         # Per-invocation stream-json
│   └── playlist-progress.md  # Progress snapshot
├── .beads/
│   └── issues.jsonl        # Persistent issue tracking
└── src/
```

### Essential Commands

```bash
# Per-project setup
sutra --init                # Creates .sutra/config from template
cd my-project

# Execution
sutra                       # Start autonomous loop
sutra --monitor             # Loop + live dashboard (tmux)
sutra --max-cost 5.00       # Stop at $5
sutra --timeout 20          # 20-minute timeout per loop

# Monitoring
sutra --status              # Current state

# Recovery
sutra --reset               # Clear circuit breaker and counters
```

### Circuit Breaker (Safety Mechanism)

Three-state machine protecting against stuck loops:

```
CLOSED ──[2 no-progress]──> HALF_OPEN
       
HALF_OPEN ──[3 no-progress]──> OPEN (halt)
          └──[progress]──> CLOSED (recovery)

OPEN ──[sutra --reset only]──> CLOSED
```

Progress means the bead status changed after an invocation. No-progress means Claude ran but the bead is still `in_progress`.

### Cost Limiting

`--max-cost USD` halts the loop when cumulative spend exceeds the limit. Cost is extracted from `stream-json` after each invocation and accumulated in `.sutra/state`.

---

## Part 4: Integrated Workflow

### Project Initialization

```bash
# 1. Initialize sutra config
sutra --init
cd my-project

# 2. Create initial issues
br create --title "Core authentication system" --type epic --priority 1
br create --title "User login endpoint" --type task --priority 1
br create --title "Session management" --type task --priority 2

# 3. Set up dependencies
br dep add <login-id> <auth-id>      # login depends on auth epic
br dep add <session-id> <login-id>   # session depends on login

# 4. Optionally create a playlist
sutra playlist create --epic <auth-id> -o plan.playlist
sutra playlist init plan.playlist
```

### Daily Human Workflow

**Morning (Review overnight work):**
```bash
# Check what sutra accomplished
tail -100 .sutra/logs/sessions/*.log

# Review verification queue (issues closed by sutra)
bnr                    # List issues needing verification
# For each: read instructions, test, then mark verified
bV                     # Opens picker → select → mark verified=yes

# Review any blocked or failed work
br blocked
bv --robot-insights | jq '.cycles'

# Check for unverified closed issues (legacy or missed)
buv                    # Shows closed issues without verification state

# Harvest learnings for CLAUDE.md
# (patterns, gotchas, new conventions discovered)
```

**Afternoon (Plan night's work):**
```bash
# Triage current state
bv --robot-triage | jq '.recommendations[:10]'

# Clear any blockers
br update <id> --status open

# Create new issues for discovered work
br create --title "..." --priority 2

# Set up dependencies
br dep add <new-issue> <parent>

# Verify graph is healthy
br dep cycles           # Should be empty
bv --robot-insights | jq '.project_health'

# Sync before leaving
br sync --flush-only && git add .beads/ && git commit -m "chore: sync beads" && git push
```

**Evening (Launch sutra):**
```bash
# Validate tonight's playlist
sutra playlist init plan.playlist

# Start autonomous execution
sutra --monitor

# Or for overnight: detach and leave running
sutra --tmux --playlist plan.playlist
# Then: Ctrl+B, D to detach tmux
```

### Sutra's Internal Loop (What Happens at Night)

```bash
# Each iteration (simplified — actual implementation is in lib/):

# 1. Get next ready task
NEXT=$(br ready --json | jq -r '.[0].id')

# 2. Claim the work
br update $NEXT --status in_progress

# 3. Execute implementation (Claude Code does the work)
# - Reads issue details: br show $NEXT
# - Implements changes
# - Runs tests
# - Sutra commits with conventional format

# 4. Complete the issue and mark for human verification
br close $NEXT --reason "implemented"
br label add $NEXT verified:needs-review

# 5. Check exit conditions (cost, loops, circuit breaker)
# update_circuit_breaker
# check_exit_conditions
```

**IMPORTANT:** All autonomous work must be marked `verified:needs-review` with clear test instructions. See [[BEADS_VERIFICATION_WORKFLOW.md]] for the full protocol.

### Beads + BV Integration Patterns

**Pattern 1: Score-Based Task Selection**
```bash
# Get top 3 by triage score
bv --robot-triage | jq '.recommendations[:3][] | {id, title, score: .triage_score}'

# Pick highest that's ready (sutra does this automatically in standard mode)
NEXT=$(bv --robot-triage | jq -r '.recommendations[0].id')
br update $NEXT --status in_progress
```

**Pattern 2: Quick Wins First**
```bash
# Clear quick wins to unblock downstream work
bv --robot-triage | jq '.quick_wins[] | {id, title, unblocks}'
```

**Pattern 3: Bottleneck Clearing**
```bash
# Find and prioritize bottlenecks
bv --robot-insights | jq '.bottlenecks[:3]'
```

**Pattern 4: Label-Based Batching**
```bash
# Work on one area at a time
bv --robot-triage-by-label | jq '.recommendations_by_label.auth'
```

---

## Part 5: Best Practices

### From Practitioner Community

**"Land the plane" protocol:** End every session by:
1. Updating beads issues with current state
2. Syncing the tracker (`br sync --flush-only`)
3. Cleaning git state (no uncommitted changes)
4. Removing debugging artifacts
5. Writing handoff notes for the next session

**One task, one session:** Sutra handles this automatically — each bead is one task. Context is kept short by design.

**File beads for any work exceeding two minutes:** If it takes longer than a quick fix, it deserves tracking. Creates audit trails and enables work discovery across sessions.

**Keep issue sets small:** Performance degrades beyond ~500 issues (~25k tokens). Use `bd compact --days 90` to archive old closed items.

**Five-iteration refinement:** When planning:
1. Discuss requirements with LLM
2. Demand plan improvements 5 times until convergence
3. Generate beads epics
4. Iterate on epics 5 times before execution

### Task Routing Heuristic

| Triage Score | Routing |
|--------------|---------|
| ≥ 0.7 | Full AI autonomy |
| 0.5-0.7 | AI execution with verification gate |
| 0.3-0.5 | Human clarification → AI attempt → review |
| < 0.3 | Human-led with AI assistance |

### Human Checkpoints

Insert human review at:
- Task assignment (confirm AI suitability)
- Plan approval (review approach before coding)
- Destructive operations
- External integrations
- Final review before merge

### Quality Gates

Before allowing autonomous execution:
- Static analysis tooling present
- Build system documented
- Testing infrastructure exists
- AGENTS.md or equivalent documentation
- Environment setup documented
- Security guardrails configured

---

## Part 6: Troubleshooting

### Common Issues

**Sutra circuit breaker opens repeatedly:**
```bash
# Check what's causing no progress
tail -50 .sutra/logs/sessions/*.log

# Common causes:
# - Tests failing (fix the tests)
# - Missing dependencies (install them)
# - Unclear task (improve issue description)
# Reset:
sutra --reset
```

**Beads sync conflicts:**
```bash
# Pull latest, resolve conflicts in issues.jsonl
git pull
# Edit .beads/issues.jsonl to resolve
bd sync
```

**BV reports cycles:**
```bash
# Find and break cycles
bv --robot-insights | jq '.cycles'

# Remove the weakest dependency
bd dep remove <issue-id> <blocking-dep-id>
```

**Sutra halts unexpectedly:**
- Check `.sutra/state` for circuit breaker status
- Review the session log for the last invocation
- Run `sutra --reset` to clear and retry

**Tasks not closing:**
- Verify bead descriptions are clear and actionable
- Check that the bead has no unresolved blockers (`br show <id>`)

### Recovery Commands

```bash
# Reset and start fresh
sutra --reset
br sync --flush-only
git add .beads/ && git commit -m "chore: sync beads"

# Force close stuck issues
br update <id> --status closed

# Compact old issues if performance degrades
br compact --days 60
```

---

## Part 7: Advanced Patterns

### Multi-Epic Orchestration with Playlists

```bash
# Create parent epic
br create --title "Q1 Auth Overhaul" --type epic --priority 1

# Create child epics
br create --title "OAuth Integration" --type epic --priority 1
br create --title "Session Management" --type epic --priority 2

# Link them
br dep add <oauth-id> <q1auth-id>
br dep add <session-id> <q1auth-id>

# Generate and run a playlist for the whole epic
sutra playlist create --epic <q1auth-id> -o q1-auth.playlist
sutra playlist init q1-auth.playlist
sutra --playlist q1-auth.playlist --monitor
```

### Remote Overnight Execution

```bash
# Run on a remote server
sutra --remote opc@oracle --playlist plan.playlist

# Or configure REMOTE_HOST in .sutra/config then:
sutra -r --playlist plan.playlist
```

---

## Quick Reference Card

### Beads (br)
```bash
br ready                    # Unblocked work
br create --title "..." --priority 2
br update <id> --status in_progress
br close <id> --reason "..."
br dep add <child> <parent>
br sync --flush-only        # ALWAYS before leaving
```

### Beads Viewer (bv)
```bash
bv --robot-triage           # Full triage JSON
bv --robot-insights         # Graph analysis JSON
bv --robot-next             # Single top pick
# NEVER run bare `bv` in automation
```

### Sutra
```bash
sutra --init                # Init project config
sutra --monitor             # Run with dashboard
sutra --reset               # Clear circuit breaker
sutra --status              # Check state
sutra playlist init FILE    # Validate playlist
sutra playlist create --epic ID -o FILE  # Author playlist
```

### Verification (Human Review)
```bash
bnr                         # List issues needing verification
bV                          # Mark selected issue as verified
bmr                         # Mark issue as needs-review
buv                         # List unverified closed issues
```

### The Golden Rule

> File beads for any work exceeding two minutes.
> Land the plane before leaving.
> Work is NOT done until pushed.

---

## Appendix: Tool Versions & Installation

### Requirements
- beads_rust (`br`)
- Rust (for beads_viewer)
- Bash 4+ (for sutra)
- Claude Code CLI
- jq (for JSON parsing)
- tmux (optional, for sutra --monitor)

### Installation
```bash
# Beads Viewer
cargo install beads_viewer

# Sutra
cd /path/to/sutra
# The binary is ./sutra
```

### Verification
```bash
br --version
bv --version
sutra --version
claude --version
```
