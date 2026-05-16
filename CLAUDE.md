# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Ralph is an autonomous AI coding system — a bash outer loop that feeds tasks to Claude Code one at a time. ~4,200 lines of bash across ~35 library files in `lib/`. Two execution modes share one main loop:

- **Playlist mode** (`--playlist FILE`, now the primary mode) — execute a hand-authored or Claude-authored list of beads + free-form prompts + quality gates in order.
- **Standard `br ready` mode** — pull the next unblocked bead and work it. Kept for ad-hoc use.

Read [[PHILOSOPHY.md]] first. The bitter lesson: simple deterministic orchestration + a smart model beats clever multi-agent systems. All intelligence lives in Claude (inner loop); the outer loop is a for-loop with a sort.

## Coding Style: Functional Decomposition

**Prefer linear sequences of descriptive function calls over nested logic, inline code, or deep conditionals.** Every function does one thing; the caller reads like prose. See the main script (`ralph`) and `lifecycle.sh` for the pattern.

### Rules

1. **Name functions as verb phrases** (`pick_next_task`, `playlist_next`, `ensure_ralph_branch`). The name IS the documentation.
2. **Keep callers linear** — a function body is a sequence of function calls, not a tree of conditionals. Extract branches.
3. **One level of abstraction per function** — don't mix orchestration with `jq -r '.status'`.
4. **Guard clauses over nesting** — return/exit early; keep the happy path unindented.
5. **Functions over comments** — if you need a comment to explain a block, extract it.
6. **Regenerate ctags after adding/renaming functions** — `ctags -R .` from project root (Neovim `gd` uses `tags`).

### Size Limits (hard, no exceptions without approval)

| Unit | Max | Action |
|------|-----|--------|
| File | 200 | Split by responsibility. Name new file `<parent>_<concern>.sh` (e.g. `playlist_validate.sh`). Source next to parent in `loader.sh`. |
| Function | 50 | Extract sub-functions. |
| Case branch | 10 | Extract branch body to a named function. |
| Inline string | 5 | Extract to variable, or a file under `templates/`. |

### Template System

Templates under `templates/` are pure data — no shell logic. Render with `render_template` from `utils.sh` using `{{KEY}}` placeholders:

```bash
prompt=$(render_template "$TEMPLATES_DIR/prompt_bead.txt" \
    "TASK_ID=$tid" "DETAILS=$details")
```

File extensions:
- `.txt` — content rendered to stdout/captured (prompts, help, ASCII art).
- `.template` — scaffolds copied verbatim (e.g. `config.template` → `.ralph/config`).
- `.jq` — filter files loaded with `jq -f` when the filter exceeds ~3 lines.

`TEMPLATES_DIR` lives in `loader.sh` alongside `LIB_DIR` — top-level constants every module needs belong there.

### Naming conventions for helpers

- `get_*` — spawns a subprocess (e.g. `get_bead_status <id>` calls `br show`).
- `extract_*` — operates on pre-fetched JSON passed as an argument.

If a caller already has JSON in hand, using `get_*` would spawn a redundant subprocess.

### Module-Scoped Globals

Bash has no modules, so prefix module-local globals visibly: `DB_*` (dashboard state), `_dry_run_*` (playlist validation accumulators), `playlist_*` (playlist runtime state). Collisions on generic names like `count`/`status` are otherwise inevitable after a split.

### Don't write tracker IDs in source

Never put bead IDs (`ralph-0h1.11`, `br-xxx`), JIRA, or GitHub issue numbers into code — comments, docstrings, logs, or names. Only commit subjects and PR descriptions.

## Running Ralph

```bash
./ralph                          # Standard mode: pull from br ready
./ralph --playlist plan.playlist # Playlist mode (primary)
./ralph --dry-run [--playlist F] # Validate without executing
./ralph --max-tasks N            # Stop after N completed
./ralph --max-loops N            # Stop after N invocations (default 50)
./ralph --max-turns N            # Per-invocation turn cap (default 100)
./ralph --timeout M              # Per-invocation minutes (default 10)
./ralph --max-cost USD           # Halt if cumulative cost exceeds (0 = unlimited)
./ralph --model {haiku|sonnet|opus|glm-...}  # Inner-loop model (default haiku)
./ralph --scope REGEX            # Filter beads by title regex (standard mode)
./ralph --no-commit / --commit   # Override per-task commit default
./ralph --context-files a,b,c    # File manifest injected into prompts
./ralph --playlist-branch NAME   # Override one-branch-per-session name
./ralph --sandbox                # Bubblewrap isolation (Linux)
./ralph --monitor                # Live dashboard (separate terminal)
./ralph --tmux / -t              # Wrap in detachable tmux session
./ralph --remote [HOST] / -r     # Rsync + SSH + tmux to remote
./ralph --status                 # Print .ralph/state
./ralph --reset                  # Clear circuit breaker / counters
./ralph --init                   # Scaffold .ralph/config from template
./ralph playlist init  FILE      # Two-phase validation (syntax + Claude semantic)
./ralph playlist create [IDS...] [--epic EID] [-o FILE]   # Claude-authored playlist
```

Per-project defaults: `.ralph/config` (sourced by `config.sh`). CLI flags override both defaults and project config.

## Prerequisites

`br` (beads_rust), `claude` CLI, `jq`, `timeout`/`gtimeout`. Checked by `lib/prereqs.sh`.

## Architecture

### Main Loop (`ralph`)

Top-level script sources `lib/loader.sh`, calls `initialize "$@"`, then runs one of two loops:

**Playlist mode** (primary):
```
while true:
    check_exit_conditions
    playlist_next            # advance past comments/blanks, parse annotations + gate tags
    playlist_handle_dry_run  # skip execution when --dry-run
    playlist_execute         # dispatch: bead → claim+invoke+close, prompt → raw invoke
    save_state
```
On exit, playlist mode generates a completion report via one final Claude invocation.

**Standard mode** (`br ready`):
```
while true:
    check_exit_conditions
    select_task              # br ready --json, skip epics, apply --scope
    handle_dry_run           # exit after showing next
    claim_task
    build_prompt             # task + branch + rules + (optional) playlist progress
    invoke_claude            # claude -p, timeout, stream-json, retry with failure context
    check_bead_status
    update_circuit_breaker
    handle_task_outcome      # close → bump counter, epic auto-close
    save_state
```

### Library Layout (load order in `loader.sh` matters)

Config / core:
- `config.sh` — defaults (MAX_LOOPS=50, MODEL=haiku, GATE_DENSITY_RATIO=7, INJECTION_RATIO=0.25, …). Sources `.ralph/config` at the bottom.
- `utils.sh` — `log`, `save_state`/`load_state`, ANSI colors, `render_template`, `commit_beads_if_dirty`.
- `utils_beads.sh` — shared `br` query helpers (`get_*` spawning / `extract_*` pure).
- `glm.sh` — GLM z.ai model provider integration (alternate Anthropic-compatible endpoint).
- `args.sh` — CLI parsing into globals; handles early-exit actions (`--status`, `--reset`, `--init`, `playlist init`, `playlist create`, `--help`).
- `prereqs.sh` — dependency checks, `ensure_ralph_branch`.
- `sandbox.sh`, `remote.sh` — isolation / remote execution wrappers.

Monitoring:
- `monitor.sh` + `monitor_render.sh` — live dashboard, double-buffered, reads `.ralph/state` + `br`.

Task selection (standard mode):
- `tasks.sh` — `pick_next_task`, `claim_task`, `get_task_details`, `get_branch_context`, `slugify`.

Quality gates:
- `gates.sh` — loads `templates/gate_*.txt` into `GATE_TEMPLATES[]`, expands `#SMOKE_TEST`/`#COMPLETENESS_SCAN`/`#REVIEW`/`#REFACTOR`/`#DOCUMENT` tags inline. Strips self-healing bead-creation lines when injection is capped.
- `gates_inject.sh` — automatic gate insertion during playlist authoring (density-based, epic-boundary, tail-only).

Playlist (the big surface area):
- `playlist.sh` — parse, navigate, execute (`playlist_next`, `playlist_execute`, `read_playlist_file`).
- `playlist_annotations.sh` — `@model=…`, `@turns=…`, `@timeout=…`, and gate tag parsing.
- `playlist_branch.sh` — one-branch-per-session resolution (`ralph-<playlist-slug>`).
- `playlist_reload.sh` — reload playlist after a `>` prompt modifies it (checksum-based).
- `playlist_validate.sh` — Phase 1 dry-run: syntax, bead existence/status, dependency ordering, density warnings.
- `playlist_init.sh` — `ralph playlist init FILE`: Phase 1 + Phase 2 semantic validation driver.
- `playlist_semantic.sh` — Phase 2: auto-inject gates, spawn Claude for semantic audit, stamp marker.
- `playlist_create.sh` — `ralph playlist create`: spawn Claude to author a playlist from bead/epic IDs.
- `playlist_marker.sh` — `✓ VALIDATED:` marker check/insertion in playlist header.
- `playlist_progress.sh` — writes `.ralph/playlist-progress.md` snapshot; feeds completion report.

Prompt assembly:
- `prompt_context.sh` — per-project file manifest (from `CONTEXT_FILES`), cross-task handoff notes.
- `prompt.sh` — `build_prompt`: assembles bead/prompt text from `templates/prompt_*.txt` and branch-context templates.

Invocation:
- `format_stream.sh` — jq filter: `stream-json` → human-readable (text, tool uses, cost).
- `invoke.sh` — `invoke_claude`: `claude -p` with timeout, stream capture, cost tracking, auto-escalation (haiku→sonnet→opus) on retry.
- `invoke_retry.sh` — retry logic (up to 3 attempts), augments prompt with failure context from `templates/failure_tail.jq`.
- `circuit_breaker.sh` — 3-state machine: CLOSED →(2 no-progress)→ HALF_OPEN →(3)→ OPEN. Reset only via `--reset`.
- `task_outcome.sh` — `handle_task_outcome`, `mark_needs_review`, `maybe_close_epic`.

Lifecycle:
- `lifecycle.sh` — `initialize`, exit `cleanup`, playlist completion report generation.

### Playlist File Format

A playlist line is one of:

```
abc123                           # bead: claim → invoke → close
abc123 @opus @turns=30           # per-line annotations (first attempt only)
def456 @model=sonnet @timeout=15
> Review the changes so far       # free-form prompt (no bead to close)
>@opus Refactor the auth module   # prompt with per-line model
#SMOKE_TEST <optional context>    # quality gate tag, expanded from gate_smoke_test.txt
#COMPLETENESS_SCAN
#REVIEW
#REFACTOR
#DOCUMENT
# comment / blank line            # skipped
✓ VALIDATED: 2026-04-15           # marker (first 5 lines) — inserted by `playlist init`
```

Playlist state is crash-safe: `playlist_line` in `.ralph/state` only advances **after** successful execution, so a crash mid-task resumes at the same line. `playlist_reload.sh` re-reads the file after each `>` prompt so Claude can edit the playlist mid-run.

Gate tags are shorthand — ralph expands them at runtime from `templates/gate_*.txt`. The playlist file is **never modified** by expansion. `gates_inject.sh` *can* edit the file, but only during authoring (`playlist init` / `playlist create`).

### Epic description conventions

**Link, don't inline.** Epic descriptions that paste long spec prose are re-injected into every child invocation, burning tokens on irrelevant context. Instead, put the spec in a file and reference it.

**Bad** (80 lines of inline spec):
```
## Scope
* OAuth 2.0 with PKCE …
* ONE-WAY contact sync …
…80 lines of spec prose…
```

**Good** (3–5 line summary + path link):
```
Xero accounting integration for Chippie tenants (AU/GB/IE).
Specification: docs/technical/features/XERO_SPEC.md
Branch: xero-integration.playlist — cherry-picked from xero@65021d1 in task .1
```

- **Where spec files should live:** `docs/technical/features/<epic-slug>_SPEC.md`, or project-local equivalent.
- **What the epic description SHOULD contain:** 3–5 line summary + path to spec file + branch/provenance notes.
- **What bead descriptions SHOULD contain:** task-specific scope only — no re-pasting of epic context.

`ralph playlist init` warns when an epic in the playlist has a description exceeding `EPIC_DESC_LINE_WARN` lines (default 40). The Phase 2 semantic audit also flags ≥20-line blocks that appear verbatim across multiple children.

### The Two-Phase `playlist init` Workflow

`ralph playlist init FILE`:
1. **Phase 1** — pure-bash: syntax check, bead existence (`br show`), status, dependency ordering, gate-density warnings.
2. **Phase 2** — Claude-assisted: `playlist_inject_gates` inserts missing `#SMOKE_TEST`/`#COMPLETENESS_SCAN`/`#REVIEW`/`#REFACTOR`/`#DOCUMENT` lines at density-based intervals and epic boundaries, then Claude audits descriptions and adds the `✓ VALIDATED:` marker.

Startup (`playlist_init.sh` → `check_validation_marker`) checks for the marker. If absent in non-interactive mode (tmux, CI, SSH, detached agents), ralph **halts with an error** rather than proceeding silently. To override:

- Set `PLAYLIST_AUTO_CONTINUE=true` in `.ralph/config` (for CI environments that validate externally).
- Pass `--yes` (or `-y`) on the CLI for a one-shot override.

Interactive runs still prompt `[y/N]` as before.

### Injection / Self-Healing Limits

Gate templates contain "create beads (type=bug only) …" self-healing instructions. To prevent runaway bead creation, `MAX_INJECTED_BEADS` (or derived `INJECTION_RATIO * total_beads`, floor 5) caps total injections. Once capped, `gates.sh:strip_injection_instructions` removes the self-healing line from expanded gates.

### Cost Tracking & Auto-Escalation

`invoke.sh` accumulates cost from stream-json. `MAX_COST_USD` halts the loop via the circuit breaker when exceeded. `AUTO_ESCALATE=true` bumps model tier on retry (haiku → sonnet → opus) to get past tasks that failed on a cheap model.

### Branch Strategy

`get_branch_context()` in `tasks.sh`:
- Standalone task → `ralph` branch.
- Task in epic → `ralph-<epic-slug>` (from `ralph`).
- Task in epic blocked by another epic → `ralph-<epic-slug>` from `ralph-<dep-epic-slug>`.
- Playlist mode → one branch per playlist session (`playlist_branch.sh`), resolved from playlist filename or `--playlist-branch`.

### Circuit Breaker

Progress = bead status changed (closed or reopened). No-progress = Claude returned but bead still `in_progress`.

```
CLOSED ──[2 no-progress]──► HALF_OPEN ──[3 no-progress]──► OPEN (halt)
  ▲ progress                    ▲ progress
  └─────────────────────────────┘
```

Only `ralph --reset` clears OPEN. Also trips on `MAX_COST_USD`.

### Verification Workflow

On close, ralph adds the `verified:needs-review` label. Humans review with `bnr` (needing review) and `bV` (mark verified). Epic auto-closes when all children are closed.

### Logging

Everything is captured to `.ralph/logs/`:
- `sessions/<project>-<branch>-<timestamp>.log` — full stdout+stderr via `tee`.
- `stream/<session>-<NNN>.jsonl` — raw `stream-json` per invocation, for diagnosis and replay.
- `queue-<timestamp>.log` — `--queue` runs only: one high-level roll-up of all
  playlists (branch, status, beads closed, commits, report path, cost).
  Written by the parent process (`queue_log.sh`), which has no session log.

Playlist progress snapshot: `.ralph/playlist-progress.md`.

## Reference Projects

Under `reference-projects/` — read for context, don't modify: `beads/` (bd, legacy), `beads_viewer/` (bv graph scoring), `ralph-claude-code/`, `gastown/`, `choo-choo-ralph/`.

## Key Tool Commands

**beads_rust (br):** `br ready`, `br show <id> --json`, `br update <id> --status in_progress`, `br close <id> --reason "…"`, `br dep add <child> <parent>`. Ralph itself calls these from `utils_beads.sh` / `tasks.sh` / `task_outcome.sh`.

**beads_viewer (bv):** Always use robot flags. **Never run bare `bv`** — it launches a TUI that hangs agents.
```bash
bv --robot-triage    # Full triage JSON
bv --robot-next      # Single top pick
bv --robot-insights  # Graph analysis
```

## Not Yet Implemented

From [[PLAN.md]]: BV integration for task selection, `.ralph/metrics.db` instrumentation ([[metrics.md]]), scout system ([[scout/]]), harvest tooling ([[Harvest.md]]).

## Document Map

| Document | Purpose |
|----------|---------|
| [[PHILOSOPHY.md]] | Founding principles — read first |
| [[PLAN.md]] | Build order checklist |
| [[GUIDE.md]] | Complete operational guide |
| [[TOOLS.md]] | Ecosystem tool catalog |
| [[outer-loop.md]] | Orchestrator research |
| [[AI-TRIAGE.md]] | Semantic actionability scoring |
| [[metrics.md]] | SQLite instrumentation schema |
| [[Harvest.md]] | Morning review process |
| [[BEADS_VERIFICATION_WORKFLOW.md]] | Human verification tracking |
| [[scout/]] | Reconnaissance system design |
