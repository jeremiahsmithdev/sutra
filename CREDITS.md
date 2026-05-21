# Credits

Sutra is a peer assembly built on two independent prior works. Both are credited
here as the foundations they are.

---

## beads — Steve Yegge

Beads is a git-backed, agent-native issue tracker. Issues are markdown files in
`.beads/` committed alongside code. There is no server, no database, no external
dependency. The tracker travels with the repository.

Steve Yegge designed beads to work *with* agentic tools rather than around them.
Agents read, write, and close beads with the same `br` CLI a human uses. The
audit trail is git history. The query interface is `br list`.

Sutra is built on top of beads. It reads beads to find tasks, claims them during
execution, and closes them on completion. The `.beads/` directory is the source
of truth for all work tracking in a sutra run.

Project: `beads_rust` (`br`) — the CLI sutra calls on every task loop.

---

## ralph — Geoffrey Huntley

Ralph is a bash outer loop pattern for running Claude Code autonomously overnight.
The core idea: write a for-loop in bash, pick the next task from a tracker, invoke
Claude Code as a subprocess, wait for it to finish, repeat.

Geoffrey Huntley articulated and published this pattern while most practitioners
were still trying to build elaborate multi-agent systems. His observation — that
a single Claude Code process with a good prompt beats complex orchestration — is
the founding insight that sutra inherits.

Sutra is not a fork of ralph. It is a separate implementation of the same pattern,
built from scratch, with a different library structure and a playlist-first design
that the original ralph did not have. The name changed because the scope expanded:
sutra adds playlist authoring, two-phase validation, quality gates, automatic gate
injection, and a harvest methodology that ralph did not ship.

Where this documentation describes "the original ralph pattern" or compares against
"ralph," it is describing Geoffrey Huntley's published work, not this codebase.

---

## Sutra

Sutra takes the ralph pattern and the beads substrate and adds:

- Playlist mode as the primary execution model (ordered task lists with quality gates)
- Two-phase playlist validation (bash syntax check + Claude semantic audit)
- Automatic gate injection during playlist authoring
- A harvest methodology for reviewing completed runs
- Per-session branch management
- A circuit breaker for detecting stuck loops
- Cost tracking and model auto-escalation on retry

The additions are practical, not theoretical. Each one existed because a real
overnight run produced a failure that a simpler system could not recover from.

Sutra is MIT-licensed and maintained at terminalworkflow.com.
