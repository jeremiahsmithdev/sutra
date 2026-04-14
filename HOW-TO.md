# How to Use Ralph

Ralph runs Claude Code in a loop over your task list. You write the tasks (beads), ralph feeds them to Claude one at a time and tracks progress. Think of it as autopilot for your backlog.

---

## Getting Started

### First-time setup

```bash
cd your-project
ralph --init
```

This creates `.ralph/config` where you can set project defaults (model, timeout, remote host, etc.).

### Prerequisites

Ralph needs these installed: `br` (beads_rust), `claude` (Claude Code CLI), `jq`, and `timeout` (or `gtimeout` on macOS).

---

## The Basics

### Let ralph pick what to work on

```bash
ralph
```

Ralph queries `br ready` for unblocked tasks, picks the top one, hands it to Claude, and repeats. It keeps going until all tasks are done, the loop limit is hit, or the circuit breaker trips.

### Preview what ralph would do

```bash
ralph --dry-run
```

Shows the next task without invoking Claude. Useful for sanity-checking before a long run.

### Limit how much ralph does

```bash
ralph --max-tasks 3          # Stop after 3 completed tasks
ralph --max-loops 10         # Stop after 10 Claude invocations
ralph --timeout 20           # 20 minutes per invocation (default: 10)
ralph --max-cost 5.00        # Stop after $5 spent
```

### Filter which tasks to work on

```bash
ralph --scope "auth"         # Only tasks matching "auth"
ralph --scope "api|routing"  # Regex — match "api" or "routing"
```

### Choose a model

```bash
ralph --model opus           # Use Opus for harder tasks
ralph --model sonnet         # Use Sonnet
ralph --model haiku          # Default — fast and cheap
```

---

## Playlists

Playlists let you control the exact order of execution. Instead of letting ralph pick tasks, you specify them in a file.

### Create a playlist from an epic

```bash
ralph playlist create --epic epic-abc123 -o plan.playlist
```

Ralph expands the epic's children, asks Claude to order them sensibly, and injects quality gates.

### Create from specific tasks

```bash
ralph playlist create task-1 task-2 task-3 -o plan.playlist
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
ralph playlist init plan.playlist
```

This checks that all bead IDs exist, validates gate density, and runs a semantic audit via Claude to fill in context for gate tags.

### Run a playlist

```bash
ralph --playlist plan.playlist
```

### Dry-run a playlist

```bash
ralph --dry-run --playlist plan.playlist
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

Gate tags are checkpoints that ralph expands into detailed prompts at runtime:

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

By default, ralph creates a branch named after the playlist file. Override it:

```bash
ralph --playlist plan.playlist --playlist-branch feature/auth-v2
```

Or put a directive at the top of the playlist file:

```
# branch: feature/auth-v2
abc123
def456
```

---

## Monitoring

### Watch ralph work in real-time

Open a second terminal:

```bash
ralph --monitor
```

Shows a live dashboard with current task, circuit breaker state, progress counters, and cost.

---

## Remote Execution

### Run on a remote server

```bash
ralph --remote oracle          # SSH host from config or argument
```

This pushes your branch, syncs ralph to the remote, and starts it in a tmux session. Detach with `Ctrl+B, D`, reattach with `tmux attach -t ralph`.

### Run in a local tmux session

```bash
ralph -t                       # or --tmux
```

Wraps ralph in a detachable tmux session so you can close your terminal and come back later.

---

## Checking State

### View current state

```bash
ralph --status
```

Shows circuit breaker status, loop count, and playlist position.

### Reset after a failure

```bash
ralph --reset
```

Clears the circuit breaker and all counters. Use this after ralph halts from repeated failures.

---

## Circuit Breaker

Ralph tracks whether Claude is making progress. If Claude finishes but the task isn't closed (no progress), ralph notices:

- **2 consecutive no-progress runs** — circuit goes to HALF_OPEN (warning state)
- **3 more no-progress runs** — circuit goes to OPEN (ralph halts)
- **Any progress at any time** — circuit resets to CLOSED

When the circuit opens, run `ralph --reset` and investigate why tasks aren't completing.

---

## Project Config

Edit `.ralph/config` to set defaults for your project:

```bash
# Model for all invocations
MODEL="sonnet"

# Kill invocations after 15 minutes
TIMEOUT_MINUTES=15

# Base branch for ralph's working branch
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
| Run the loop | `ralph` |
| Preview next task | `ralph --dry-run` |
| Run 3 tasks only | `ralph --max-tasks 3` |
| Filter by scope | `ralph --scope "auth"` |
| Use Opus | `ralph --model opus` |
| Run a playlist | `ralph --playlist plan.playlist` |
| Preview a playlist | `ralph --dry-run --playlist plan.playlist` |
| Validate a playlist | `ralph playlist init plan.playlist` |
| Generate a playlist | `ralph playlist create --epic ID -o file` |
| Live dashboard | `ralph --monitor` |
| Remote execution | `ralph --remote oracle` |
| Check state | `ralph --status` |
| Reset after halt | `ralph --reset` |
| Initialize project | `ralph --init` |
