# Beads ecosystem: The emerging standard for AI agent task management

**Beads and its companion beads_viewer have become the de facto infrastructure for autonomous AI coding workflows**, addressing what Steve Yegge calls the "50 First Dates" problem—AI agents' inability to maintain memory between sessions. The ecosystem now supports **14,000+ GitHub stars** across projects and "tens of thousands" of daily users, with integration into ralph loops enabling truly unattended overnight coding. This report synthesizes best practices, scoring mechanisms, and workflow patterns validated by practitioners.

The core insight driving adoption: structured task graphs outperform markdown plans because they're queryable, dependency-aware, and don't require LLMs to waste cycles parsing text. Multiple practitioners—including Simon Willison and noted framework authors—confirm beads "just works" because LLMs are already trained on issue tracker patterns.

---

## What beads actually solves: agent amnesia and markdown chaos

Steve Yegge built beads after observing that AI agents "simply cannot keep track of work using Markdown files." The problems compound: markdown is text rather than structured data, requiring parsing that steals GPU cycles; plans aren't queryable, making work queues nearly impossible; and agents rarely update plans, causing rapid bit-rot.

Beads replaces this with a **three-part architecture**: a SQLite database for fast local queries, a JSONL file (`.beads/issues.jsonl`) as the git-tracked source of truth, and a daemon handling synchronization. The JSONL format stores one issue per line with hash-based IDs (e.g., `bd-a3f8e9`) that prevent merge collisions in multi-agent workflows.

The system supports **four dependency types**—blocks/blocked-by for task ordering, discovered-from for provenance tracking, parent/child for hierarchy, and related for loose connections. This graph structure enables agents to run `bd ready` to find unblocked work and make autonomous decisions based on priority and readiness rather than following rigid sequences.

Yegge emphasizes that beads is an "execution tool, not a planning tool." The philosophy: express constraints, not sequences. You're not following a plan; you're executing a constraint graph.

---

## The triage_score: graph theory meets task prioritization

Jeffrey Emanuel's beads_viewer (bv) adds an intelligence layer that transforms raw beads data into actionable recommendations. The **triage_score is a composite ranking from 0 to 1** computed from eight weighted components:

| Component | Weight | What it measures |
|-----------|--------|------------------|
| PageRank | **22%** | Node importance in dependency graph |
| Betweenness | **20%** | How often the task sits on critical paths |
| Blockers | 13% | Direct count of downstream tasks unblocked |
| Priority | 10% | Original P0-P4 designation |
| Time factors | 10% | Duration-based signals |
| Urgency | 10% | Urgency indicators |
| Risk | 10% | Risk assessment |
| Staleness | 5% | How long issue has been open |

The heaviest weights—PageRank and betweenness—reflect a key insight: foundational tasks that unblock many others matter more than their stated priority suggests. High PageRank tasks are "the bedrock of your project... often schemas, core libraries, or architectural decisions." A task with high betweenness is a "choke point" whose completion accelerates everything downstream.

**Score interpretation** follows predictable bands: above 0.7 indicates critical issues for immediate attention, 0.3-0.7 represents standard backlog items, and below 0.3 can be safely deferred.

The system exposes recommendations via `bv --robot-triage`, returning structured JSON with quick wins (high impact, low complexity), blockers to clear first, and commands for immediate execution. A critical warning: bare `bv` launches an interactive TUI that hangs AI agents—only `--robot-*` flags produce machine-consumable output.

---

## Quick wins versus issues needing clarification

beads_viewer provides deterministic categorization that removes ambiguity from task selection:

**Quick wins** are identified through graph analysis—issues that are high impact (unblock many downstream tasks), low complexity (no unresolved blockers), and immediately workable. Access them via `bv --robot-triage | jq '.quick_wins'` or the built-in recipe `bv --recipe actionable`.

**Blockers to clear** surface issues whose completion maximally unblocks the dependency graph. The formula prioritizes tasks where (completion impact × downstream task count) is highest.

**Issues requiring human clarification** appear through several detection mechanisms:
- Cycle detection (`bv --robot-insights | jq '.Cycles'`) identifies circular dependencies that must be resolved before any progress
- Blocked status filtering (`bv --recipe blocked`) shows tasks waiting on dependencies  
- Staleness detection (`bv --recipe stale`) flags issues untouched for 30+ days that may need review or abandonment

The recommended workflow follows a clear state machine: **triage → pick based on score → work → resolution check**. If resolved, close with reason; if blocked or unclear, update status and add comments for human review. This pattern emerged independently across multiple practitioners.

---

## Ralph loops: the mechanics of autonomous overnight coding

Ralph loops—named after Ralph Wiggum and created by Geoffrey Huntley—provide the iteration mechanism for unattended AI execution. The core concept is elegantly simple: a while-true bash loop that repeatedly feeds Claude Code a prompt file, with a stop hook blocking premature exits.

The official implementation uses a **dual-condition exit gate** requiring both completion indicators AND explicit EXIT_SIGNAL confirmation. This prevents false positives from phrases like "feature done, moving to tests" when more work remains. The pattern ensures Claude doesn't exit until it genuinely believes the task is complete.

**Circuit breakers** protect against runaway loops:
- `CB_NO_PROGRESS_THRESHOLD=3`: Opens circuit after 3 iterations with no file changes
- `CB_SAME_ERROR_THRESHOLD=5`: Opens circuit after 5 repeated errors
- `CB_OUTPUT_DECLINE_THRESHOLD=70%`: Opens circuit if output quality drops sharply
- `CB_PERMISSION_DENIAL_THRESHOLD=2`: Opens circuit after 2 permission denials

Safety is paramount. Ralph runs Claude with `--dangerously-skip-permissions`, and practitioners universally recommend running in Docker containers or VMs, starting with small, low-risk tasks until trust is established.

---

## Beads + ralph integration: three validated patterns

Multiple implementations have emerged for connecting beads task management with ralph execution:

**Pattern 1: Ralph-TUI with beads tracker.** The ralph-tui tool directly integrates beads as a task source:
```bash
ralph-tui run --tracker beads --epic my-epic-id
ralph-tui run --tracker beads-bv --epic beads-xyz  # With intelligent scoring
```
Configuration lives in `.ralph-tui/config.toml` specifying tracker type and beads directory.

**Pattern 2: Choo Choo Ralph's structured phases.** This Claude Code plugin implements a five-phase workflow: Plan (human) → Spec (human + AI) → Pour into beads (AI) → Ralph execution (AI) → Harvest learnings (human + AI). Each task passes through internal stages: bearings (health checks), implement, verify, commit.

**Pattern 3: Basic outer-loop polling.** From Josh Chisholm's ralph-kit, the outer loop simply polls beads for available work:
```bash
READY_COUNT=$(bd count --status open)
IN_PROGRESS=$(bd count --status in_progress)
if [ "$READY_COUNT" = "0" ] && [ "$IN_PROGRESS" = "0" ]; then
    sleep 20; continue  # Wait for new work
fi
```

The post-completion **harvest phase** extracts discovered patterns, gotchas, and new skills for CLAUDE.md, creating a compounding knowledge flywheel where each iteration makes future agents smarter.

---

## Pre-flight checklists and quality gates

Before allowing autonomous execution, validated practitioners apply multiple verification layers:

**Task readiness criteria** from Factory.ai's agent readiness model span nine pillars: static analysis tooling, documented build systems, testing infrastructure, AGENTS.md documentation, environment setup, observability, security guardrails, issue templates, and analytics capability.

**Quality gates for AI code** (from SonarQube's framework) enforce:
- Zero security vulnerabilities
- Reliability and maintainability thresholds
- Code coverage requirements
- Duplication limits
- Security hotspot review

**Human-in-the-loop checkpoints** should occur at: task assignment (confirm AI suitability), plan approval (review approach before coding), destructive operations, external integrations, and final review before merge. IBM's HITL research emphasizes that these checkpoints provide error correction, accountability, ethical reasoning capability, and audit trails.

The emerging consensus uses a **scoring heuristic for task routing**:
- Score ≥20: Full AI autonomy
- Score 15-19: AI execution with verification gate
- Score 10-14: Human clarification → AI attempt → review
- Score <10: Human-led with AI assistance

---

## Convergent wisdom from the practitioner community

Multiple independent sources have landed on remarkably similar approaches:

**"Land the plane" protocol**: End every session by updating beads issues, syncing the tracker, cleaning git state, removing debugging artifacts, and generating a prompt for the next session. Yegge notes that agents' "reward function biases them for checklists and acceptance criteria"—they execute landing procedures well even with depleted context.

**One task, one session**: Kill the process after completing each task and start fresh. This saves money (shorter contexts), improves model performance (no accumulated confusion), and maintains clean state. Beads provides continuity between sessions.

**File beads for any work exceeding two minutes**: If it takes longer than a quick fix, it deserves tracking. This creates audit trails and enables work discovery across sessions.

**Keep issue sets small**: Performance degrades beyond ~500 issues (~25k tokens). Use `bd admin compact --days 90` to archive old closed items.

**Five-iteration refinement**: When planning, discuss requirements with the LLM, demand plan improvements five times until convergence, then generate beads epics. Iterate on epics five times before execution. This front-loading prevents downstream confusion.

Simon Willison's endorsement captures the core insight: "Giving [LLMs] somewhere to jot down notes is a surprisingly effective way of working around [the memory] limitation... It works well partly because LLM training data makes them familiar with the issue/bug tracker style of working already."

---

## Concrete setup: overnight autonomous coding

A validated project structure for beads + ralph integration:

```
my-project/
├── .beads/
│   └── beads.jsonl           # Git-tracked task database
├── .ralph-tui/
│   └── config.toml           # Tracker configuration
├── ralph.sh                  # Main loop script
├── CLAUDE.md                 # Persistent project memory
├── prd.json                  # Task definitions with passes: boolean
└── progress.txt              # Session progress tracking
```

The `.ralphrc` configuration specifies session parameters:
```bash
PROJECT_NAME="my-project"
MAX_CALLS_PER_HOUR=100
CLAUDE_TIMEOUT_MINUTES=15
SESSION_CONTINUITY=true
ALLOWED_TOOLS="Write,Read,Edit,Bash(git *),Bash(npm *)"
```

For overnight batch work, practitioners use scripts that iterate through projects:
```bash
cd /path/to/project1
claude -p "/ralph-loop 'Complete epic bd-a3f8e9' --max-iterations 50"
cd /path/to/project2
claude -p "/ralph-loop 'Implement feature bd-xyz789' --max-iterations 50"
```

Each iteration ends with explicit RALPH_DONE signaling combined with mandatory git push, ensuring work is never stranded locally.

---

## The broader methodology: progressive automation

Beyond beads-specific practices, the AI coding community has converged on a framework for task categorization:

**Anthropic's workflow distinction** separates orchestrated systems (predefined code paths) from true agents (dynamic process control). Routing works best when "distinct categories are better handled separately, and classification can be handled accurately."

**Task suitability scoring** evaluates five dimensions:
1. Process complexity—simpler, rule-based processes score higher
2. Repetitiveness—high-frequency tasks score higher
3. Data structure—structured inputs score higher
4. Business impact—high-value tasks prioritize early
5. Human judgment required—lower judgment = higher suitability

**The Explore-Plan-Code-Commit pattern** from Anthropic's Claude Code documentation: ask the agent to read relevant files without coding (research phase), make a plan using "think" to trigger extended thinking, implement with explicit verification, then commit. Steps 1-2 are "crucial—without them, Claude tends to jump straight to coding a solution."

Cursor's scaling research reveals a similar architecture: **Planners** continuously explore and create tasks, spawning sub-planners for specific areas; **Workers** pick up tasks and focus entirely on completion. This separation prevents the context pollution that occurs when single agents handle everything.

---

## Conclusion

The beads ecosystem represents a maturation point in autonomous AI coding infrastructure. The convergent patterns are clear: **structured task graphs over markdown**, **graph-theoretic scoring for prioritization**, **simple iteration loops with safety gates**, and **human checkpoints at critical junctures**.

The triage_score's PageRank + betweenness weighting reflects a non-obvious insight—graph position matters more than stated priority for maximizing development velocity. The dual-condition exit gate in ralph loops solves premature termination. The harvest phase creates compounding knowledge.

What distinguishes successful practitioners is not sophisticated tooling but disciplined application of simple principles: one task per session, land the plane religiously, file beads for anything substantial, keep issue sets bounded, and verify before trusting. The infrastructure exists; the methodology is documented; the community has validated the patterns. The remaining work is execution.
