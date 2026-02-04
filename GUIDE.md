# The Ralph System: Autonomous AI Coding with Beads & BV

A practical guide for human-AI collaborative development using the day/night workflow pattern.

---

## Philosophy

> "Express constraints, not sequences. You're not following a plan; you're executing a constraint graph."
> — Steve Yegge, creator of beads

The Ralph System combines three Unix-philosophy tools that compose beautifully:

| Tool | Purpose | Operates On |
|------|---------|-------------|
| **beads (bd)** | Git-backed issue tracking with dependencies | Constraint graphs |
| **beads_viewer (bv)** | Graph-theoretic triage and prioritization | Issue analysis |
| **ralph-claude-code** | Autonomous execution loops with safety gates | Claude Code sessions |

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
│                        NIGHTTIME (Ralph)                        │
│                                                                 │
│  ralph --monitor                                                │
│                                                                 │
│  Loop:                                                          │
│    1. bv --robot-triage → pick highest actionable issue        │
│    2. bd update <id> --status in_progress                      │
│    3. Execute implementation                                    │
│    4. Run tests, verify                                         │
│    5. bd close <id> + bd set-state <id> verified=needs-review  │
│    6. Check exit conditions → continue or complete             │
│                                                                 │
│  Safety: Circuit breakers, rate limits, dual-gate exit         │
└─────────────────────────────────────────────────────────────────┘
                              ↓ sunrise
┌─────────────────────────────────────────────────────────────────┐
│                      MORNING (Human Review)                     │
│                                                                 │
│  1. Check ralph logs: tail .ralph/logs/ralph.log               │
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

## Part 3: Ralph — The Autonomous Loop

### Core Architecture

Ralph is a bash loop that repeatedly invokes Claude Code with safety gates:

```
┌────────────────────────────────────────────────────────────────┐
│                     RALPH MAIN LOOP                            │
│                                                                │
│  while true; do                                                │
│    1. Check circuit breaker (is it open?)                     │
│    2. Check rate limits (calls remaining?)                    │
│    3. Build context (loop #, previous summary, circuit state) │
│    4. Execute Claude Code with timeout                        │
│    5. Analyze response for signals                            │
│    6. Update progress tracking                                │
│    7. Check exit conditions (dual-gate)                       │
│  done                                                          │
└────────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
project/
├── .ralph/
│   ├── PROMPT.md           # Development instructions (Claude reads this)
│   ├── @fix_plan.md        # Prioritized task checklist
│   ├── @AGENT.md           # Build/run/test instructions
│   ├── specs/              # Technical specifications
│   ├── logs/
│   │   ├── ralph.log       # Execution log
│   │   └── claude_output_*.log
│   ├── status.json         # Current loop status
│   ├── progress.json       # Real-time progress
│   └── [state files]       # Session, circuit breaker, signals
├── .beads/
│   └── issues.jsonl        # Persistent issue tracking
└── src/
```

### Essential Commands

```bash
# Setup (one-time global)
./install.sh                # Installs to ~/.ralph and ~/.local/bin

# Per-project setup
ralph-setup my-project      # Creates .ralph/ structure
cd my-project

# Execution
ralph                       # Start autonomous loop
ralph --monitor             # Loop + live dashboard (tmux)
ralph --calls 50            # Limit to 50 API calls/hour
ralph --timeout 20          # 20-minute timeout per loop

# Monitoring
ralph --status              # Current state
ralph-monitor               # Live dashboard
tail -f .ralph/logs/ralph.log

# Recovery
ralph --reset-circuit       # Clear circuit breaker
ralph --reset-session       # Start fresh session
```

### Circuit Breaker (Safety Mechanism)

Three-state machine protecting against runaway loops:

```
CLOSED ──[no progress ≥3 OR errors ≥5]──> OPEN (halt)
       └──[no progress ≥2]──> HALF_OPEN (monitoring)

HALF_OPEN ──[progress detected]──> CLOSED (recovery)
          └──[no progress ≥3]──> OPEN (fail)

OPEN ──[manual reset only]──> CLOSED
```

**Thresholds:**
- `CB_NO_PROGRESS_THRESHOLD=3` — Opens after 3 loops with no file changes
- `CB_SAME_ERROR_THRESHOLD=5` — Opens after 5 identical errors
- `CB_OUTPUT_DECLINE_THRESHOLD=70` — Opens if output drops 70%

### Dual-Gate Exit (Prevents False Exits)

Ralph exits ONLY when BOTH conditions are met:

1. **Heuristic detection:** ≥2 completion indicators (natural language patterns)
2. **Explicit signal:** `EXIT_SIGNAL: true` in RALPH_STATUS block

**Why?** Prevents exit on "feature done, moving to tests" when more work remains.

### RALPH_STATUS Block (Claude Must Output)

```
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: 2
FILES_MODIFIED: 5
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING
EXIT_SIGNAL: false | true
RECOMMENDATION: <next steps>
---END_RALPH_STATUS---
```

### Rate Limiting

- Default: 100 API calls/hour
- Automatic hourly reset with countdown
- Configurable via `--calls NUM`

---

## Part 4: Integrated Workflow

### Project Initialization

```bash
# 1. Create project with ralph structure
ralph-setup my-project
cd my-project

# 2. Initialize beads
bd init

# 3. Create initial issues from PRD or manual entry
bd create --title "Core authentication system" --type epic --priority 1
bd create --title "User login endpoint" --type task --priority 1
bd create --title "Session management" --type task --priority 2

# 4. Set up dependencies
bd dep add bd-login bd-auth      # login depends on auth epic
bd dep add bd-session bd-login   # session depends on login

# 5. Configure PROMPT.md with objectives
edit .ralph/PROMPT.md
```

### Daily Human Workflow

**Morning (Review overnight work):**
```bash
# Check what ralph accomplished
tail -100 .ralph/logs/ralph.log

# Review verification queue (issues closed by Ralph)
bnr                    # List issues needing verification
# For each: read instructions, test, then mark verified
bV                     # Opens picker → select → mark verified=yes

# Review any blocked or failed work
bd blocked
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
bd update bd-xyz --status open --comment "Dependency resolved"

# Create new issues for discovered work
bd create --title "..." --priority 2

# Set up dependencies
bd dep add <new-issue> <parent>

# Verify graph is healthy
bd dep cycles           # Should be empty
bv --robot-insights | jq '.project_health'

# Sync before leaving
bd sync && git push
```

**Evening (Launch ralph):**
```bash
# Update PROMPT.md with tonight's focus
edit .ralph/PROMPT.md

# Start autonomous execution
ralph --monitor

# Or for overnight: detach and leave running
ralph --monitor
# Then: Ctrl+B, D to detach tmux
```

### Ralph's Internal Loop (What Happens at Night)

```bash
# Each iteration:

# 1. Get top actionable issue
TOP_ISSUE=$(bv --robot-triage | jq -r '.recommendations[0].id')

# 2. Claim the work
bd update $TOP_ISSUE --status in_progress

# 3. Execute implementation (Claude Code does the work)
# - Reads issue details: bd show $TOP_ISSUE
# - Implements changes
# - Runs tests
# - Commits with conventional format

# 4. Complete the issue and mark for human verification
bd close $TOP_ISSUE
bd set-state $TOP_ISSUE verified=needs-review --reason "VERIFICATION INSTRUCTIONS:
1. [Step to test]
2. [Expected behavior]

NOTES: [What was changed]"

# 5. Check for next work or exit
REMAINING=$(bd count --status open)
if [ "$REMAINING" = "0" ]; then
    # Signal completion
    EXIT_SIGNAL=true
fi
```

**IMPORTANT:** All autonomous work must be marked `verified=needs-review` with clear test instructions. See [[BEADS_VERIFICATION_WORKFLOW.md]] for the full protocol.

### Beads + BV Integration Patterns

**Pattern 1: Score-Based Task Selection**
```bash
# Get top 3 by triage score
bv --robot-triage | jq '.recommendations[:3][] | {id, title, score: .triage_score}'

# Pick highest that's ready
NEXT=$(bv --robot-triage | jq -r '.recommendations[0].id')
bd update $NEXT --status in_progress
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
2. Syncing the tracker (`bd sync`)
3. Cleaning git state (no uncommitted changes)
4. Removing debugging artifacts
5. Generating a prompt for the next session

**One task, one session:** Kill the process after completing each task and start fresh. This:
- Saves money (shorter contexts)
- Improves model performance (no accumulated confusion)
- Maintains clean state
- Beads provides continuity between sessions

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

**Ralph circuit breaker opens repeatedly:**
```bash
# Check what's causing no progress
tail -50 .ralph/logs/ralph.log
cat .ralph/.circuit_breaker_history | jq '.[-5:]'

# Common causes:
# - Tests failing (fix the tests)
# - Missing dependencies (install them)
# - Permission issues (check .ralph/PROMPT.md allowed tools)
# - Unclear task (improve issue description)
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

**Ralph exits too early:**
- Ensure PROMPT.md requires RALPH_STATUS block
- Check for false completion keywords in output
- Increase `MAX_CONSECUTIVE_DONE_SIGNALS` if needed

**Ralph never exits:**
- Verify tasks are being marked complete
- Check for infinite test loops (test-only work)
- Ensure EXIT_SIGNAL: true is being output

### Recovery Commands

```bash
# Reset everything and start fresh
ralph --reset-circuit
ralph --reset-session
bd sync
git stash  # if needed

# Force close stuck issues
bd update <id> --status closed --reason "abandoned"

# Compact old issues if performance degrades
bd compact --days 60
```

---

## Part 7: Advanced Patterns

### Multi-Epic Orchestration

```bash
# Create parent epic
bd create --title "Q1 Auth Overhaul" --type epic --priority 1

# Create child epics
bd create --title "OAuth Integration" --type epic --priority 1
bd create --title "Session Management" --type epic --priority 2

# Link them
bd dep add bd-oauth bd-q1auth
bd dep add bd-session bd-q1auth

# Work proceeds bottom-up through the graph
```

### Molecule Templates

Beads supports reusable work templates (molecules):
```bash
bd mol list                    # Show catalog
bd mol show <mol-id>          # Template details
bd mol seed <mol-id>          # Instantiate template
```

### Overnight Batch Processing

For multiple projects:
```bash
#!/bin/bash
for project in /path/to/project1 /path/to/project2; do
    cd "$project"
    ralph --calls 50 --timeout 30
done
```

### Monitoring Multiple Projects

```bash
# Check status across projects
for project in */; do
    if [ -f "$project/.ralph/status.json" ]; then
        echo "=== $project ==="
        cat "$project/.ralph/status.json" | jq '{status, loop_count}'
    fi
done
```

---

## Quick Reference Card

### Beads (bd)
```bash
bd ready                    # Unblocked work
bd create --title "..." --priority 2
bd update <id> --status in_progress
bd close <id> --reason "..."
bd dep add <child> <parent>
bd sync                     # ALWAYS before leaving
```

### Beads Viewer (bv)
```bash
bv --robot-triage           # Full triage JSON
bv --robot-insights         # Graph analysis JSON
bv --robot-next             # Single top pick
# NEVER run bare `bv` in automation
```

### Ralph
```bash
ralph-setup <project>       # Init project
ralph --monitor             # Run with dashboard
ralph --reset-circuit       # Clear circuit breaker
ralph --status              # Check state
```

### Verification (Human Review)
```bash
bnr                         # List issues needing verification
bV                          # Mark selected issue as verified
bmr                         # Mark issue as needs-review
buv                         # List unverified closed issues
bd set-state <id> verified=needs-review --reason "..."
bd state <id> verified      # View current state and reason
```

### The Golden Rule

> File beads for any work exceeding two minutes.
> One task, one session.
> Land the plane before leaving.
> Work is NOT done until pushed.

---

## Appendix: Tool Versions & Installation

### Requirements
- Go 1.21+ (for beads)
- Rust (for beads_viewer)
- Bash 4+ (for ralph)
- Claude Code CLI 2.0.76+
- jq (for JSON parsing)
- tmux (optional, for ralph --monitor)

### Installation
```bash
# Beads
go install github.com/anthropics/beads/cmd/bd@latest

# Beads Viewer
cargo install beads_viewer

# Ralph
cd /path/to/ralph-claude-code
./install.sh
```

### Verification
```bash
bd --version
bv --version
ralph --version
claude --version
```
