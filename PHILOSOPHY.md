# Philosophy

Founding principles of this system. Read this before building anything.

See also: [[CLAUDE.md]] | [[GUIDE.md]] | [[TOOLS.md]]

---

## The Bitter Lesson

General methods that scale with computation beat specialised approaches that encode human knowledge. The history of AI is littered with clever systems that were eventually surpassed by dumb methods running on better hardware. Chess engines, image recognition, language models — scale and simplicity win every time.

This lesson applies directly to agent orchestration. Do not build elaborate multi-agent systems with specialised roles, complex handoffs, and sophisticated state machines. Build a loop.

## Ralph Is a Bash Loop

A single process. A single repository. One task per iteration. The opposite of microservices — because non-deterministic microservices are a red hot mess.

The loop does not need to be smart. The model is smart. The loop just needs to keep feeding work to the model and getting out of the way. Consistent mediocrity scales better than occasional brilliance, and loops are how you get consistency.

If your orchestration layer requires its own debugging, it is too complex.

## Two Loops, Two Jobs

**The outer loop** selects what to work on. It is deterministic. It reads from beads, consults triage scores, picks the next task, and hands it off. It does not reason, deliberate, or improvise. It is a for-loop with a sort.

**The inner loop** is the agent. It takes a task, explores the codebase, implements a solution, runs tests, self-corrects, and iterates until the task is complete. All intelligence lives here. All complexity lives here. The model handles ambiguity — the orchestrator does not have to.

Do not move intelligence from the inner loop into the outer loop. The inner loop gets better every time the model improves. The outer loop does not.

## Structural Importance ≠ Actionability

BV's triage score tells you a task is important in the dependency graph. It does not tell you the task is ready to be worked on. A P0 issue with perfect PageRank might reference code that was deleted last week.

The scout bridges this gap. It runs bounded reconnaissance — file existence, grep, git history — and produces a structured assessment. Structural scoring says *what matters*. The scout says *what's ready*.

Combined, they produce better task selection than either alone.

## The Scout Is Reconnaissance, Not Implementation

The scout investigates. It does not build. It does not fix. It does not refactor. It collects evidence, synthesises a brief assessment, and stores it. Two minutes per issue, maximum.

The scout's output is a briefing for the implementing agent — entry points, blockers, a suggested approach. This is shift-left intelligence: cheap tokens now to save expensive tokens later. If the scout identifies the exact file and line, the inner loop might complete in 2 iterations instead of 8.

A bad scout assessment wastes a few inner loop iterations. This is the same cost as having no scout at all. The downside is bounded.

## Deterministic Where Possible

Quality gates do not need AI. "After implementing X, review X and test X" is a workflow rule, not a judgment call. Inject review and test beads deterministically after every completion.

Task selection does not need AI. BV's graph algorithms — PageRank, betweenness centrality, blocker analysis — are algorithmically sophisticated without being probabilistic. A composite score from a directed acyclic graph is more reliable than asking a language model to pick the next task.

Reserve AI for tasks that require judgment over evidence. The scout's synthesis step qualifies. The outer loop's routing decisions do not.

## Backpressure Over Direction

Do not tell the agent what to do. Engineer an environment where wrong outputs get rejected automatically. Tests gate incomplete work. Linters catch style violations. Type checkers enforce contracts. The agent hits these walls and self-corrects.

The skill shifts from "directing the agent step by step" to "writing constraints that make failure obvious and success unambiguous." Prompts define *what done looks like*. The environment enforces *whether it's actually done*.

## Beads Are the Source of Truth

All work is tracked in beads. The outer loop reads from beads. The inner loop updates beads. The scout enriches beads. Quality gates are beads.

Beads live in git. They travel with the code. They have dependencies, statuses, and notes. They do not require a separate service, a database, or a web interface. Everything the system needs to know about what work exists and what state it is in lives in the repository.

Do not introduce a second source of truth.

## Store Artefacts, Not Decisions

The scout stores a JSON report with evidence and an assessment. It does not store "I decided to work on this next." The outer loop reads scores and picks the highest. It does not store its reasoning.

Artefacts are reusable. Decisions are ephemeral. When the model improves or the scoring weights change, the artefacts still have value. The old decisions do not.

## Everything Is Configurable, Nothing Is Required

The system works with just beads and the inner loop — a bash while-loop that picks the next open bead and runs Claude. That is the minimum viable ralph.

BV triage improves task selection. The scout improves task preparation. Quality gates improve output reliability. Each layer adds value independently. None are prerequisites for the others.

If a component adds more operational complexity than it saves in agent efficiency, remove it.

## Fail Predictably

Deterministically bad in an undeterministic world. It is better to fail predictably than succeed unpredictably. When the loop fails, the failure is informative — a test didn't pass, a file wasn't found, a bead wasn't updated. These are debuggable.

When a clever orchestrator fails, the failure is opaque — the routing model hallucinated a task ID, the state machine entered an invalid transition, the agent handoff lost context. These are not debuggable at 3am while you are asleep.

Choose boring failures.
