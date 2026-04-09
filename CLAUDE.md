# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Ralph is an autonomous AI coding system — a bash outer loop that feeds beads issues to Claude Code one at a time. ~1,800 lines of bash across 17 library files implementing the core loop, playlist execution, circuit breaker, monitoring dashboard, remote execution, and branch management.

**Philosophy:** Read [[PHILOSOPHY.md]] first. The bitter lesson applies: simple deterministic orchestration + a smart model beats clever multi-agent systems. The outer loop is a for-loop with a sort. All intelligence lives in the inner loop (Claude).

## Coding Style: Functional Decomposition

**Prefer linear sequences of descriptive function calls over nested logic, inline code, or deep conditionals.**

Every function should do one thing, named so the caller reads like prose. The main loop is the model — each line is a verb phrase describing what happens next:

```bash
# GOOD — linear, self-documenting
validate_environment
load_configuration
select_next_task
claim_task "$tid"
build_prompt "$task_details"
invoke_claude "$prompt"
evaluate_outcome "$tid"
update_circuit_breaker
save_state

# BAD — inline logic, nested conditionals, unclear intent
if [[ -n "$tid" ]]; then
  result=$(br show "$tid" --json)
  if [[ $? -eq 0 ]]; then
    status=$(echo "$result" | jq -r '.status')
    if [[ "$status" == "closed" ]]; then
      # ... 20 more lines of nested logic
```

### Rules

1. **Name functions as verb phrases** — `pick_next_task()`, `ensure_ralph_branch()`, `commit_beads_if_dirty()`. The name IS the documentation.
2. **Keep callers linear** — a function body should read top-to-bottom as a sequence of function calls, not a tree of conditionals. Extract branches into named functions.
3. **One level of abstraction per function** — don't mix high-level orchestration (`run_main_loop`) with low-level details (`jq -r '.status'`). Push details down into well-named helpers.
4. **Avoid deep nesting** — if you're 3+ levels deep in `if/for/while`, extract the inner block into a function with a descriptive name.
5. **Guard clauses over nesting** — return/exit early for error cases at the top, keep the happy path unindented.
6. **Functions over comments** — if you need a comment to explain a block, extract it into a function whose name provides that explanation.
7. **Regenerate ctags after adding/renaming functions** — run `ctags -R .` from the project root. Neovim's `gd` uses the `tags` file for cross-file navigation (bashls can't do this). The `.ctags.d/ralph.ctags` config excludes non-source directories.

### Size Limits

Hard limits. No exceptions without explicit approval.

| Unit | Max Lines | Action When Exceeded |
|------|-----------|---------------------|
| **File** | 200 | Split into focused files. A file does one thing. |
| **Function** | 50 | Extract sub-functions with descriptive names. |
| **Case branch** | 10 | Extract the branch body into a named function. |
| **Inline string** | 5 | Extract to a variable, or a file under `templates/`. |

### String & Template Extraction

Long inline strings destroy readability. Extract them.

1. **Multi-line heredocs >5 lines** → move to a file under `templates/` and `cat` it in. Prompt templates, config scaffolds, help text — none of these belong inline.
2. **Complex jq expressions >3 lines** → extract to a named function (e.g., `extract_epic_blocker()` instead of inline `jq -r '[.[0].dependencies // ...`). The function name documents what the query does.
3. **printf chains for display** → extract each logical section into a `render_*()` or `build_*()` function. A dashboard frame builder should read as a sequence of section calls, not 60 lines of printf.
4. **Prompt construction** → assemble from named variables, not one giant string. Each section (task details, branch instructions, rules, closure protocol) should be its own variable or function return.
5. **Repeated query patterns** → if the same `br show ... | jq ...` pattern appears in multiple files, extract to a shared helper in `utils_beads.sh`. Naming convention matters for performance:
   - **`get_*`** — spawns a subprocess (e.g., `get_bead_status <id>` calls `br show`).
   - **`extract_*`** — operates on pre-fetched JSON passed as an argument (e.g., `extract_epic_blocker <epic_json>`).

   A caller that already has JSON in hand should use the `extract_*` variant — calling `get_*` would spawn a redundant subprocess. A caller that only has an ID uses `get_*`.

```bash
# BAD — 20-line heredoc inline
prompt="You are executing a single task...
## Your Task
ID: $task_id
$details
## Branch
$branch_section
## Rules
1. Implement this ONE task completely...
..."

# GOOD — assembled from named parts
local task_section branch_section rules_section closing_section
task_section=$(format_task_section "$task_id" "$details")
branch_section=$(format_branch_instructions "$branch_ctx")
rules_section=$(format_execution_rules)
closing_section=$(format_closure_protocol "$task_id")
prompt="${task_section}

${branch_section}

${rules_section}

${closing_section}"
```

```bash
# BAD — complex jq inline
dep_epic_id=$(echo "$epic_json" | jq -r '
    [.[0].dependencies // [] | .[] | select(.dependency_type == "blocks")
     | select(.issue_type == "epic")] | .[0].id // empty
' 2>/dev/null)

# GOOD — named function
dep_epic_id=$(extract_epic_blocker "$epic_json")
```

**When inline jq is acceptable:** complex jq is OK when it operates on locally-scoped data with no reuse elsewhere. For example, `playlist_dry_run` validates beads against pre-fetched JSON in a single call site — extracting the inline jq to a helper would add indirection without eliminating duplication. The rule targets *repeated* or *subprocess-spawning* complex jq, not all complex jq.

### File Splitting Guidelines

When a file exceeds 200 lines, split by responsibility:

- **One concern per file** — parsing, rendering, validation, and execution are separate concerns even if they operate on the same data.
- **Name the new file `<parent>_<concern>.sh`** — `monitor_render.sh`, `playlist_validate.sh`, `invoke_retry.sh`, `utils_beads.sh`. Keeping the parent stem as a prefix makes the relationship obvious in `loader.sh` and in file listings. The concern should be a noun/verb describing what's inside — `validate_playlist.sh` not `playlist_helpers.sh`.
- **Source new files next to their parent in `loader.sh`** — extracted files belong immediately after the file they came from, preserving load-order intuition.
- **Keep the original file as the orchestrator** — it calls into the extracted files, reading like a table of contents.

### Template System

Templates under `templates/` are pure data — no shell logic. Render them with the `render_template` helper from `utils.sh`:

```bash
# render_template <template_file> [KEY=value ...]
prompt=$(render_template "$TEMPLATES_DIR/prompt_bead.txt" \
    "TASK_ID=$tid" \
    "DETAILS=$details" \
    "BRANCH_SECTION=$branch_section")
```

Templates use `{{KEY}}` placeholders. `render_template` is pure bash (no `envsubst` or `sed` dependency) and handles multi-line values cleanly — the substitution works even when a value itself contains newlines.

**File extensions:**
- **`.txt`** — content rendered to stdout or captured into a variable (prompts, help text, ASCII art).
- **`.template`** — scaffolds copied verbatim to a project directory (e.g., `config.template` → `.ralph/config` via `cat` in `init_project()`).
- **`.jq`** — jq filter files loaded via `jq -f "$TEMPLATES_DIR/foo.jq"` when the filter is more than ~3 lines. Gives you syntax highlighting in editors and lets you test the filter standalone (`jq -f templates/foo.jq < some.jsonl`).

**`TEMPLATES_DIR` lives in `loader.sh`** alongside `LIB_DIR`, not in a late-loaded module. Top-level constants that every module needs to see belong in `loader.sh` so they're defined before any `source` statement references them. Functions resolve variables lazily (at call time), but `set -u` at the top of a file would trip on a missing constant referenced outside a function body.

### Module-Scoped Globals

Bash has no real modules — all globals are global. To make module boundaries visible, prefix module-scoped state with the module's abbreviation:

- **`DB_*`** — dashboard state (`monitor_render.sh`): `DB_circuit`, `DB_cur_title`, `DB_ready`, `DB_blocked`, etc.
- **`_dry_run_*`** — playlist validation accumulators (`playlist_validate.sh`): `_dry_run_count`, `_dry_run_warnings`, `_dry_run_seen_beads`.

The prefix signals "this belongs to module X — don't read or write it from outside." Without this convention, split modules will accidentally collide on common names like `count`, `status`, or `warnings`. Pick a 2-4 letter prefix or a leading-underscore noun; the exact scheme matters less than consistency within a module.

## Running Ralph

```bash
./ralph                          # Run the loop (picks tasks from br ready)
./ralph --dry-run                # Show next task without executing
./ralph --max-tasks 3            # Stop after 3 completed tasks
./ralph --max-loops 10           # Stop after 10 Claude invocations
./ralph --max-turns 200          # Max turns per Claude invocation (default: 500)
./ralph --timeout 20             # 20 minutes per invocation (default: 10)
./ralph --scope "auth"           # Only work issues matching regex
./ralph --playlist plan.playlist # Execute tasks in file order (see Playlist Mode)
./ralph --auto-commit false      # Disable per-task commits (playlist default)
./ralph --model sonnet           # Override model (default: haiku)
./ralph --sandbox                # Bubblewrap isolation (Linux only)
./ralph --monitor                # Live dashboard (run in separate terminal)
./ralph --remote oracle          # Run on remote server via SSH+tmux
./ralph --status                 # Print current .ralph/state
./ralph --reset                  # Clear circuit breaker and counters
```

Per-project overrides go in `.ralph/config` (sourced by `config.sh`). CLI flags override both defaults and `.ralph/config`.

### Navigation

`ctags -R .` regenerates the `tags` file for cross-file function navigation in Neovim (`gd`). The `.ctags.d/ralph.ctags` config scopes to Sh files and excludes `.git`, `.beads`, `.history`, `reference-projects`, and `output`. `.shellcheckrc` doubles as a root marker for bash-language-server.

## Prerequisites

Ralph requires: `br` (beads_rust), `claude` (Claude Code CLI), `jq`, `timeout`/`gtimeout`. Checked by `lib/prereqs.sh`.

## Architecture

### The Main Loop (45 lines)

`ralph` sources `lib/loader.sh` which loads all 17 library files. The main script has two execution modes:

**Standard mode** (`br ready`):
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
    save_state             →  persist to .ralph/state
```

**Playlist mode** (`--playlist FILE`):
```
while true:
    check_exit_conditions  →  same as standard
    playlist_next          →  advance to next actionable line
    playlist_execute       →  dispatch: bead task or raw prompt
    save_state             →  persist + advance playlist position
```

On exit, playlist mode generates a completion report via one final Claude invocation.

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
| `monitor.sh` | Live dashboard — double-buffered, 1s refresh, reads .ralph/state + br queries |
| `remote.sh` | `run_remote()` — rsync + SSH + tmux session management |
| `sandbox.sh` | Bubblewrap filesystem isolation wrapper |
| `format_stream.sh` | jq filter: stream-json → human-readable (text, tool uses, cost) |
| `splash.sh` | ASCII art |
| `playlist.sh` | Playlist parsing, line classification, dry-run validation, execution dispatch |
| `lifecycle.sh` | Session lifecycle — `initialize()`, exit `cleanup()`, playlist completion reports |

### Key Global Variables

State flows through globals (set in `config.sh`, modified by `args.sh`, persisted via `save_state()`):

- `circuit` / `no_progress_count` — circuit breaker state
- `total_tasks_completed` / `total_loops` — progress counters
- `current_task` — retry tracking (non-empty = retrying same task)
- `tid` / `task_details` — current task being worked
- `CLAUDE_PID` — for interrupt handling

### Playlist Mode

A playlist is a text file where each line is one of:
- `<bead-id>` — executed as a normal bead task (claim → build prompt → invoke → close)
- `> <prompt>` — executed as a free-form Claude prompt (no bead to claim/close)
- `>@opus <prompt>` — free-form prompt with per-line model override
- `# comment` or blank — skipped

```bash
# Example playlist
abc123
def456
> Review the changes so far and fix any test failures
>@opus Refactor the auth module for clarity
ghi789
```

Playlist state is crash-safe: `playlist_line` in `.ralph/state` only advances after successful execution, so a crash mid-task resumes at the same line. Dry-run (`--dry-run --playlist`) validates all bead IDs, checks statuses, and warns about dependency ordering.

### Invocation Retry Logic

`invoke_claude()` retries up to 3 times on failure (configurable via `MAX_RETRIES` in `invoke.sh`). Each retry augments the prompt with failure context — the exit code diagnosis and the last 10 lines of stream-json output — so Claude can adapt its approach. Exit codes are mapped to human-readable diagnoses (124=timeout, 137=OOM/kill, etc.).

### Logging

All output is captured to `.ralph/logs/`:
- **Session logs** (`sessions/<project>-<branch>-<timestamp>.log`) — full stdout+stderr via `tee`
- **Stream logs** (`stream/<session>-<NNN>.jsonl`) — raw `stream-json` output per invocation, useful for diagnosis and replay

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
