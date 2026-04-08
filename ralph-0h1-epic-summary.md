# Epic: Playlist Validation & Efficiency

**ID:** ralph-0h1 | **Tasks:** 18 (1 dropped) | **Status:** Open
**Prerequisite:** ralph-s4w (move .ralph_state → .ralph/state)

## Feature Overview

| # | Feature | What It Does |
|---|---------|-------------|
| 1 | Context handoff | Pass a summary of the previous task into the next task's prompt |
| 2 | Project file map | Include a path+purpose manifest of key files in every prompt |
| 3 | Selective agent use | Prompt rule: prefer direct tools over agent sub-processes |
| 4 | Playlist reload | Re-read playlist after `>` prompts so injected lines are picked up |
| 6 | Dry-run gate analysis | Report gate density and missing gate types during `--dry-run` |
| 7 | Loop counter | Prominent header showing loop number, task ID, and model |
| 8 | Per-line annotations | `@turns=N @timeout=M @model=X` per playlist line, first-attempt only |
| 9 | Gate template system | `#SMOKE_TEST`, `#COMPLETENESS_SCAN`, `#REVIEW` tags expanded at runtime like `@opus` |
| 10 | Gate injection | Auto-insert bare `#TAG` lines at authoring time based on bead count and epic boundaries |
| 11 | Validation marker | Warn on unvalidated playlists, offer inline `ralph playlist init` |
| 12 | Syntax validation | Phase 1 of `ralph playlist init` — deterministic line parsing + gate density check |
| 13 | Semantic validation | Phase 2 of `ralph playlist init` — Claude verifies endpoints, adds context to tags, adds marker |
| 14 | Playlist create | Generate playlist from epics/beads, pipe through init for verification |
| 15 | Cost tracking + cap | Running cost total in state, `MAX_COST_USD` halt threshold |
| 16 | Progress file | `.ralph/playlist-progress.md` updated per task |
| 17 | Project summary | Auto-generated `.ralph/project-context.md` included in prompts |
| 18 | Injection limit | Cap on injected beads per run; when hit, reload stops + gates go observation-only |
| 19 | Model escalation | Auto-escalate haiku→sonnet→opus after first failure |

---

## What Problem Are We Solving?

Ralph's first real playlist run (the Flutter pilot) revealed a fundamental gap: **ralph can execute tasks flawlessly but has no way to verify the work is actually correct.**

The pilot ran 39 tasks over 6 hours, produced 36 screens with clean architecture, passed every `flutter analyze` check — and the app couldn't even log in. Six critical bugs were found the moment a human tried it. Every one of them would have been caught by a single `curl` command.

The root causes are:

1. **No validation between tasks.** Ralph runs task after task but never checks if the accumulated work actually functions. It checks "does it compile?" but not "does it work?"

2. **Each task starts blind.** Every Claude invocation re-explores the codebase from scratch because it has no memory of what the previous task just did. This wasted ~$45 in redundant file reads and agent spawning across the pilot.

3. **Playlists have no quality process.** There's no way to validate a playlist before running it, no way to verify it contains the right checkpoints, and no tooling to create one properly.

4. **No observability.** You can't see how much a run is costing, what's done, or what's next without watching the terminal live.

This epic fixes all four.

---

## Prerequisite: Move State File (ralph-s4w)

Before starting the epic, the state file moves from `.ralph_state` (loose in project root) to `.ralph/state` (inside the ralph directory where it belongs). This is a simple rename with auto-migration — if the old file exists, ralph moves it on first run. All tasks in the epic reference `.ralph/state` as the location.

---

## What Are We Building?

The work breaks into six groups.

### Group 1: Stop Wasting Tokens (Tasks 1-3)

These three changes cut the cost of a playlist run roughly in half by eliminating redundant work that Claude does on every single task.

**Task 1 — Context Handoff** (`ralph-0h1.1`, P0)
When a task finishes, ralph captures a short summary of what changed (files modified, patterns established, decisions made). That summary gets injected into the *next* task's prompt. Instead of Claude spending 5-10 turns re-exploring the codebase, it starts with "here's what the last task did" and gets straight to work.

**Task 2 — Project File Map** (`ralph-0h1.2`, P0)
The pilot showed that `pubspec.yaml`, `main.dart`, `app_router.dart`, and a few other core files were each read 18-19 times across 40 invocations. Instead of dumping full file contents into the prompt (which would bloat it), ralph includes a **file manifest** — path + purpose for each configured file. This tells Claude *where things are* without making it discover them. You list the files in `.ralph/config`, ralph reads their first comment/docstring to generate the purpose line.

**Task 3 — Selective Agent Use** (`ralph-0h1.3`, P0)
80% of tasks in the pilot spawned "Explore agent" sub-processes that were 6x slower than just using Read/Grep directly. A prompt rule now steers Claude toward direct tool use while still allowing agents for genuinely exploratory work in unfamiliar parts of the codebase. Not a ban — a strong preference.

### Group 2: Make Playlists Smarter (Tasks 4, 6-8, 18)

These improve how ralph executes playlist files — better visibility, self-healing playlists, fine-grained control per task, and safety limits.

**Task 4 — Playlist Reload After Prompts** (`ralph-0h1.4`, P0)
This is the key enabler for self-healing playlists. When a `>` prompt line runs (e.g., an @opus review), it might discover problems and create fix beads, inserting their IDs into the playlist file. Currently ralph reads the playlist once at startup and caches it. This change makes ralph re-read the file after every prompt, so injected lines are picked up automatically. The playlist becomes a living document, not a static script.

Safety invariants:
- Ralph reads the playlist file **only after** `invoke_claude` returns — never during. No concurrent read/write.
- Before any reload that detects changes, the playlist is backed up to `.ralph/playlist-backup-{timestamp}`.
- Line position is tracked by content match, not just line number. If lines are inserted above the current position, ralph scans forward to find its place.

**Task 6 — Dry-Run Gate Density Analysis** (`ralph-0h1.6`, P1)
When you do `ralph --playlist FILE --dry-run`, it now shows a gate density report alongside the existing bead validation: counts `#TAG` markers, reports the bead-to-gate ratio, and warns if density is too low or required gate types are missing. Uses `gate_check_playlist()` from the gate template system (task 9). Non-blocking.

**Task 7 — Better Loop Counter** (`ralph-0h1.7`, P1)
The current "=== Loop 15 ===" header is dim and easy to miss. This replaces it with a prominent box showing loop number, task ID, and model — with blank lines before and after for breathing room.

**Task 8 — Per-Line Annotations** (`ralph-0h1.8`, P1)
Generalises the existing `@model` override to support `@turns=30`, `@timeout=15`, and `@model=sonnet` on any playlist line. Annotations set the budget for the **first attempt only** — if the task fails and retries, it falls back to global limits so a tight budget doesn't cause a failure loop.

**Task 18 — Hard Injection Limit** (`ralph-0h1.18`, P0)
Safety cap on self-healing. Limits how many beads can be injected into the playlist during a single run. Default: 25% of the playlist's bead count (minimum 5), or a hard limit configured in `.ralph/config`.

When the limit is reached, two things happen:
1. `playlist_reload()` becomes a no-op — it stops re-reading the playlist file entirely.
2. Gate template expansion switches to **observation-only mode** — the quality checks still run (Claude still curls, greps, reviews) but the self-healing instructions ("create beads, insert into playlist") are omitted from the prompt. Gates become read-only checkpoints.

Ralph does **not** halt, does **not** break the circuit, does **not** error. The playlist continues executing everything already loaded. Claude just stops being told to create fix beads or modify the playlist.

### Group 3: Quality Gate Templates (Tasks 9-10)

Quality checks vary by task — what API endpoints to curl, what schemas to verify, what patterns to scan for. The quality gate system uses **template tags** that ralph resolves at runtime, the same way `@opus` resolves the model.

#### How Gate Templates Work

**In the playlist file — tags are shorthand:**
```
>@opus #SMOKE_TEST curl every flutter api endpoint against localhost:8080
> #COMPLETENESS_SCAN scan flutter/lib/ for incomplete work
>@opus #REVIEW check architecture after Epic 1 completion
```

The `#TAG` is a marker, like `@opus` is a marker. The text after it is user-provided context specific to this checkpoint.

**At runtime — ralph expands tags when building the prompt:**

When ralph hits a `>` line in `playlist_execute_prompt()`, it parses the line the same way it already parses `@model`:
- `@opus` → sets MODEL=opus for this invocation
- `#SMOKE_TEST` → looks up the template, prepends its base text to the prompt
- `curl every flutter api...` → user context, appended after the template text

Claude receives the full expanded prompt. The playlist file is never modified by expansion.

**Example expansion:**

Playlist line:
```
>@opus #SMOKE_TEST curl every flutter api endpoint against localhost:8080
```

Ralph parses:
- `@opus` → model override
- `#SMOKE_TEST` → template lookup
- `curl every flutter api endpoint against localhost:8080` → user context

Template base text (from `GATE_TEMPLATES["SMOKE_TEST"]`):
```
Test API endpoints against live backend. curl each endpoint implemented in the
last batch of beads. Verify responses match expected schemas. If issues found:
create beads (type=bug only) with br create, insert IDs into the playlist file
after this line.
```

What Claude receives as the prompt:
```
Test API endpoints against live backend. curl each endpoint implemented in the
last batch of beads. Verify responses match expected schemas. If issues found:
create beads (type=bug only) with br create, insert IDs into the playlist file
after this line.
curl every flutter api endpoint against localhost:8080
```

The `#SMOKE_TEST` tag never reaches Claude — ralph resolved it, same as `@opus` never reaches Claude as a literal string.

**Tag syntax rules:**
- One tag per line. Multiple tags = parse error.
- Unknown tags (not in `GATE_TEMPLATES`) = hard error at parse time with helpful message.
- Tag-only lines with no user context are valid — expands to just the template text.
- Self-healing instructions in templates constrain injections to **bug-type beads only** — no new features, no scope expansion.

**For validation — ralph counts tags in the raw file:**

`gate_check_playlist()` scans the playlist for `#TAG` markers and reports density. Minimum rules (configurable via `GATE_DENSITY_RATIO` in `.ralph/config`, default 7):
- Zero gates in a playlist with >1 bead = ERROR
- Fewer than 1 gate per N beads = WARNING
- Missing `#COMPLETENESS_SCAN` (none per 10 beads) = WARNING
- Missing `#SMOKE_TEST` (none and >5 beads) = WARNING
- Missing `#REVIEW` (none at epic boundaries) = WARNING

These rules are enforced by syntax validation (task 12), dry-run (task 6), and playlist create (task 14).

#### The Two Tasks

**Task 9 — Gate Template System** (`ralph-0h1.9`, P0)
The core library (`lib/gates.sh`):
- `GATE_TEMPLATES` associative array — base prompt text per tag
- `gate_expand_tag()` — called at runtime to resolve `#TAG` into full prompt text
- `gate_is_valid_tag()` — validates tag exists (unknown tags are hard errors)
- `gate_check_playlist()` — counts `#TAG` markers, returns density analysis
- `gate_minimum_rules()` — configurable density requirements
- Runtime parsing in `playlist_next()` — detects `#TAG` alongside `@model`

**Task 10 — Gate Injection for Authoring** (`ralph-0h1.10`, P1)
`playlist_inject_gates()` — inserts bare `#TAG` shorthand lines into a playlist file at appropriate intervals:
- `> #COMPLETENESS_SCAN` every ~5 beads without a gate
- `>@opus #REVIEW` at epic boundaries
- `>@opus #SMOKE_TEST` after the first 5 beads if none exists

These are shorthand only — not expanded in the file. The user or Claude (during semantic validation, task 13) adds context afterward. Called by `ralph playlist init` and `ralph playlist create`.

### Group 4: Playlist Authoring (Tasks 11-14)

The pilot's playlist was hand-crafted in a single conversation with no validation. These tasks add tooling to create and validate playlists properly.

**Task 11 — Validation Marker Check** (`ralph-0h1.11`, P0)
When you run `ralph --playlist FILE`, ralph checks if the file contains a `# ✓ VALIDATED:` marker. If it does, proceed. If not, you get choices:
- **y** — continue without validation
- **n** — ralph offers to run `ralph playlist init` on the file (Phase 1 only until Phase 2 is implemented, full init after)
- Non-interactive (no TTY) — warns and continues automatically

**Task 12 — Syntax + Gate Density Validation (Phase 1 of `ralph playlist init`)** (`ralph-0h1.12`, P0)
`ralph playlist init foo.playlist` starts with a fast, deterministic check — Phase 1. Two sub-phases:

*Phase 1a — Line syntax:* Every line is parsed. Bead IDs verified against `br show`. Prompt lines validated. Typos and nonexistent beads flagged.

*Phase 1b — Gate density:* Calls `gate_check_playlist()` and `gate_minimum_rules()` from task 9. Counts `#TAG` markers, checks bead-to-gate ratio. Zero gates = ERROR (blocks). Low density = WARNING.

If Phase 1 passes, Phase 2 runs automatically (task 13). From the user's perspective, `ralph playlist init` is one command.

**Task 13 — Semantic Validation (Phase 2 of `ralph playlist init`)** (`ralph-0h1.13`, P1)
After Phase 1 passes:

*Step 1 — Deterministic gate injection:* `playlist_inject_gates()` (task 10) inserts bare `#TAG` shorthand lines where density analysis found gaps.

*Step 2 — Claude semantic audit:* Claude adds project-specific context to the bare `#TAG` lines, curls API endpoints referenced in bead descriptions to verify they exist, checks file paths, creates backend beads for missing dependencies, and adds the `✓ VALIDATED` marker. Review changes with `git diff`.

**Task 14 — Playlist Create** (`ralph-0h1.14`, P1)
`ralph playlist create --epic chippie-ogz3 -o flutter.playlist` generates a playlist from an epic's children. Claude handles ordering and `#TAG` placement, then the output is piped through `ralph playlist init` for verification — no duplication of curl/validation logic between create and init.

### Group 5: Safety & Resilience (Tasks 18-19)

**Task 18 — Hard Injection Limit** (described in Group 2 above)

**Task 19 — Auto-Escalate Model After Failure** (`ralph-0h1.19`, P1)
If a bead fails on its current model, escalate to a more capable model before retrying. Escalation chain: haiku → sonnet → opus → opus (ceiling). After one failure, the next attempt uses the next model up. The original model is restored after the task completes.

This gives retries a better chance of succeeding without wasting turns at the same capability level. Configurable: `AUTO_ESCALATE=true` (default on).

### Group 6: Observability (Tasks 15-17)

**Task 15 — Cost Tracking + Cost Cap** (`ralph-0h1.15`, P1)
Parse the cost from each Claude invocation's stream-json output and maintain a running total in `.ralph/state`. Show in the session summary. Also adds `MAX_COST_USD` — a configurable threshold that halts the run when exceeded. Especially important with self-healing injection loops and model escalation, both of which can increase cost.

**Task 16 — Progress File** (`ralph-0h1.16`, P2)
After each task completes, write `.ralph/playlist-progress.md` — a human-readable file showing what's done, what's next, and what's remaining.

**Task 17 — Project Summary** (`ralph-0h1.17`, P2)
On first run, ralph invokes Claude (haiku) to generate `.ralph/project-context.md`. Included in every subsequent prompt as a lightweight project overview. Regenerated when the file doesn't exist, is >24h old, or 10+ commits have been made since generation.

---

## Dropped Tasks

**Task 5 — Handle "done" Status** (`ralph-0h1.5`) — DROPPED
The "done" status isn't a legitimate beads_rust status. Fix belongs in `br`, not ralph.

---

## Dependency Order

```
ralph-0h1.9 (gate template system)
  ├── ralph-0h1.6 (dry-run — uses gate_check_playlist)
  ├── ralph-0h1.8 (annotations — shares playlist_next parsing)
  └── ralph-0h1.10 (gate injection — uses templates)
        ├── ralph-0h1.13 (semantic validation — calls playlist_inject_gates)
        └── ralph-0h1.14 (playlist create — calls playlist_inject_gates)

ralph-0h1.12 (syntax validation)
  ├── ralph-0h1.11 (marker check — offers inline init)
  ├── ralph-0h1.13 (semantic validation — runs after syntax passes)
  └── ralph-0h1.14 (playlist create — reuses syntax validation)
```

**Ready to start now (12 tasks):** .1, .2, .3, .4, .7, .9, .12, .15, .16, .17, .18, .19

**Blocked until dependencies close (6 tasks):** .6, .8, .10, .11, .13, .14

**Suggested execution order by priority:**
1. Prerequisite: ralph-s4w (move state file)
2. P0 first: .1, .2, .3, .4, .9, .12, .18 (foundation — efficiency + templates + syntax + safety)
3. P1 next: .6, .7, .8, .10, .11, .13, .14, .15, .19 (features that build on the foundation)
4. P2 last: .16, .17 (observability)

---

## Expected Impact

Based on the pilot's numbers ($76, 40 invocations, 6 hours):

| Change | Savings | How |
|--------|---------|-----|
| Context handoff (task 1) | ~$15/run | Eliminates 150-200 turns of re-exploration |
| File map (task 2) | ~$20/run | Eliminates 290 redundant file reads |
| Selective agent use (task 3) | ~$7.50/run | Reduces unnecessary agent spawns |
| Quality gate templates (tasks 9-10) | Prevents $76 wasted runs | Catches integration bugs during execution |
| Playlist validation (tasks 11-14) | Prevents planning bugs | Catches fabricated assumptions before execution |
| Model escalation (task 19) | Reduces failed retries | Better model on retry = higher success rate |
| Injection limit + cost cap (tasks 18, 15) | Prevents runaway spending | Hard limits on self-healing loops |
| **Total projected run cost** | **~$33** | **Down from $76 (-56%)** |

The bigger win isn't the cost savings — it's that the next playlist run produces an app that actually works against the real backend, because quality gate prompts verify it at every checkpoint. And if something goes wrong, the self-healing loop fixes it within bounded limits.
