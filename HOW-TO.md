# How to Use Sutra

Sutra runs Claude Code in a loop over your task list. You write the tasks (beads), sutra feeds them to Claude one at a time and tracks progress. Think of it as autopilot for your backlog.

---

## Getting Started

### First-time setup

```bash
cd your-project
sutra --init
```

This creates `.sutra/config` where you can set project defaults (model, timeout, remote host, etc.).

### Prerequisites

Sutra needs these installed: `br` (beads_rust), `claude` (Claude Code CLI), `jq`, and `timeout` (or `gtimeout` on macOS).

---

## The Basics

### Let sutra pick what to work on

```bash
sutra
```

Sutra queries `br ready` for unblocked tasks, picks the top one, hands it to Claude, and repeats. It keeps going until all tasks are done, the loop limit is hit, or the circuit breaker trips.

### Preview what sutra would do

```bash
sutra --dry-run
```

Shows the next task without invoking Claude. Useful for sanity-checking before a long run.

### Limit how much sutra does

```bash
sutra --max-tasks 3          # Stop after 3 completed tasks
sutra --max-loops 10         # Stop after 10 Claude invocations
sutra --timeout 20           # 20 minutes per invocation (default: 10)
sutra --max-cost 5.00        # Stop after $5 spent
```

### Filter which tasks to work on

```bash
sutra --scope "auth"         # Only tasks matching "auth"
sutra --scope "api|routing"  # Regex — match "api" or "routing"
```

### Choose a model

```bash
sutra --model opus           # Use Opus for harder tasks
sutra --model sonnet         # Use Sonnet
sutra --model haiku          # Default — fast and cheap
```

---

## Playlists

Playlists let you control the exact order of execution. Instead of letting sutra pick tasks, you specify them in a file.

### Create a playlist from an epic

```bash
sutra playlist create --epic epic-abc123 -o plan.playlist
```

Sutra expands the epic's children, asks Claude to order them sensibly, and injects quality gates.

### Create from specific tasks

```bash
sutra playlist create task-1 task-2 task-3 -o plan.playlist
```

### Write a playlist by hand

A playlist file is just a text file. Each line is one of:

```
# This is a comment
abc123                       # A bead ID — run as a normal task
> Run the tests              # A raw prompt — sent to Claude as-is
>@opus Review the auth flow  # A raw prompt using Opus for this line
```

### Validate before running

```bash
sutra playlist init plan.playlist
```

This checks that all bead IDs exist, validates gate density, and runs a semantic audit via Claude to fill in context for gate tags.

### Run a playlist

```bash
sutra --playlist plan.playlist
```

### Dry-run a playlist

```bash
sutra --dry-run --playlist plan.playlist
```

Shows every line, resolves bead titles, flags closed tasks, and reports gate density — without invoking Claude.

### Playlist annotations

You can override settings per-line with `@` annotations:

```
abc123 @model=opus @timeout=20     # This bead gets Opus and 20min timeout
> Quick check @turns=30            # This prompt gets max 30 turns
>@haiku Lightweight review         # Shorthand — just the model name
```

Available annotations: `@model`, `@turns`, `@timeout`.

### Quality gates

Gate tags are checkpoints that sutra expands into detailed prompts at runtime:

```
abc123
def456
ghi789
> @opus #SMOKE_TEST              # Tests the endpoints from the last few tasks
jkl012
mno345
> #COMPLETENESS_SCAN             # Scans for TODOs, stubs, incomplete work
> @opus #REVIEW                  # Architecture and test coverage review
```

Available gates: `#SMOKE_TEST`, `#COMPLETENESS_SCAN`, `#REVIEW`.

You can add context after the tag:

```
> @opus #SMOKE_TEST curl POST /api/login, verify token in response
```

### Custom branch per playlist

By default, sutra creates a branch named after the playlist file. Override it:

```bash
sutra --playlist plan.playlist --playlist-branch feature/auth-v2
```

Or put a directive at the top of the playlist file:

```
# branch: feature/auth-v2
abc123
def456
```

---

## Monitoring

### Watch sutra work in real-time

Open a second terminal:

```bash
sutra --monitor
```

Shows a live dashboard with current task, circuit breaker state, progress counters, and cost.

---

## Remote Execution

### Run on a remote server

```bash
sutra --remote oracle          # SSH host from config or argument
```

This pushes your branch, syncs sutra to the remote, and starts it in a tmux session. Detach with `Ctrl+B, D`, reattach with `tmux attach -t sutra`.

### Run in a local tmux session

```bash
sutra -t                       # or --tmux
```

Wraps sutra in a detachable tmux session so you can close your terminal and come back later.

---

## Checking State

### View current state

```bash
sutra --status
```

Shows circuit breaker status, loop count, and playlist position.

### Reset after a failure

```bash
sutra --reset
```

Clears the circuit breaker and all counters. Use this after sutra halts from repeated failures.

---

## Circuit Breaker

Sutra tracks whether Claude is making progress. If Claude finishes but the task isn't closed (no progress), sutra notices:

- **2 consecutive no-progress runs** — circuit goes to HALF_OPEN (warning state)
- **3 more no-progress runs** — circuit goes to OPEN (sutra halts)
- **Any progress at any time** — circuit resets to CLOSED

When the circuit opens, run `sutra --reset` and investigate why tasks aren't completing.

---

## Project Config

Edit `.sutra/config` to set defaults for your project:

```bash
# Model for all invocations
MODEL="sonnet"

# Kill invocations after 15 minutes
TIMEOUT_MINUTES=15

# Base branch for sutra's working branch
WORKING_BRANCH="main"

# Remote execution target
REMOTE_HOST="opc@oracle"

# Files to include in every prompt as a project map
CONTEXT_FILES="pubspec.yaml,lib/main.dart,lib/core/routing/app_router.dart"
```

CLI flags always override config values.

---

## Quick Reference

| What you want | Command |
|---|---|
| Run the loop | `sutra` |
| Preview next task | `sutra --dry-run` |
| Run 3 tasks only | `sutra --max-tasks 3` |
| Filter by scope | `sutra --scope "auth"` |
| Use Opus | `sutra --model opus` |
| Run a playlist | `sutra --playlist plan.playlist` |
| Preview a playlist | `sutra --dry-run --playlist plan.playlist` |
| Validate a playlist | `sutra playlist init plan.playlist` |
| Generate a playlist | `sutra playlist create --epic ID -o file` |
| Live dashboard | `sutra --monitor` |
| Remote execution | `sutra --remote oracle` |
| Check state | `sutra --status` |
| Reset after halt | `sutra --reset` |
| Initialize project | `sutra --init` |
