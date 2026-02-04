# Ralph Overnight Development Setup Guide

## For Claude Max 5x on Oracle Server

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Security: Docker Sandbox](#2-security-docker-sandbox)
3. [Session Persistence: tmux on Server](#3-session-persistence-tmux-on-server)
4. [Code Isolation: Git Worktree](#4-code-isolation-git-worktree)
5. [Database Isolation](#5-database-isolation)
6. [Token Management](#6-token-management)
7. [Task Selection via Beads](#7-task-selection-via-beads)
8. [Complete Setup](#8-complete-setup)
9. [Prompt Templates](#9-prompt-templates)
10. [Quick Reference](#10-quick-reference)

---

## 1. Architecture Overview

```
YOUR LAPTOP                     ORACLE SERVER (opc@oracle)
┌──────────────┐               ┌─────────────────────────────────────────────┐
│              │    SSH        │                                             │
│  Terminal    │─────────────▶ │  tmux session "ralph"                       │
│              │               │  ┌─────────────────────────────────────┐    │
└──────────────┘               │  │  DOCKER CONTAINER                   │    │
                               │  │  ┌───────────────────────────────┐  │    │
    ▼ Close laptop             │  │  │ Claude Code + Ralph           │  │    │
    ▼ Sleep                    │  │  │                               │  │    │
    ▼ Disconnect               │  │  │ Can ONLY access:              │  │    │
                               │  │  │ - /workspace (your code)      │  │    │
    Session continues! ────────│  │  │ - allowlisted network         │  │    │
                               │  │  │                               │  │    │
                               │  │  │ CANNOT access:                │  │    │
                               │  │  │ - ~/.ssh, ~/.aws, /etc        │  │    │
                               │  │  │ - production DB credentials   │  │    │
                               │  │  │ - anything outside container  │  │    │
                               │  │  └───────────────────────────────┘  │    │
                               │  └─────────────────────────────────────┘    │
                               │                                             │
                               │  ~/chippie/        (PRODUCTION - untouched) │
                               │  ~/chippie-dev/    (mounted into container) │
                               │  PostgreSQL :5433  (dev database)           │
                               └─────────────────────────────────────────────┘
```

**Security layers:**
1. **Docker container** - Process/filesystem/network isolation
2. **Git worktree** - Code separation from production
3. **Separate database** - Different port, different credentials
4. **Server-side tmux** - Survives SSH disconnection

---

## 2. Security: Docker Sandbox

Git worktrees are NOT security sandboxes. With `--dangerously-skip-permissions`, Claude can access your entire filesystem, SSH keys, production database credentials - everything.

Docker provides real isolation.

### How Docker Sandbox Works

```bash
docker sandbox run claude
```

This:
- Creates an isolated container from `docker/sandbox-templates:claude-code`
- Mounts ONLY your current working directory as `/workspace`
- Runs Claude with `--dangerously-skip-permissions` (safe inside container)
- Persists state between sessions (packages, files, etc.)
- Stores credentials in a Docker volume (not your filesystem)

**Claude inside the container CANNOT:**
- Read `~/.ssh/id_rsa`
- Access `~/.aws/credentials`
- Modify `/etc/` or system files
- Connect to non-allowlisted domains
- See files outside `/workspace`

### Install Docker on Oracle Server

```bash
# Install Docker
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

# Add your user to docker group (logout/login after)
sudo usermod -aG docker opc

# Verify
docker --version
docker run hello-world
```

### First Run - Authenticate

```bash
cd ~/chippie-dev
docker sandbox run claude
# First run prompts for Anthropic API key
# Stored in docker-claude-sandbox-data volume
# Persists across sessions
```

### Container Persistence

```bash
# Same directory = same container
cd ~/chippie-dev
docker sandbox run claude    # Creates container
# ... work ...
exit
docker sandbox run claude    # Reuses same container, state preserved

# Different directory = different container
cd ~/other-project
docker sandbox run claude    # New container

# List all sandboxes
docker sandbox ls

# Remove a sandbox
docker sandbox rm <sandbox-id>
```

### What's In The Container

The `docker/sandbox-templates:claude-code` image includes:
- Claude Code CLI
- Node.js, Python 3, Go
- Git, GitHub CLI
- ripgrep, jq
- Docker CLI (for nested containers if needed)

If you need additional tools, install them inside the container - they persist.

### Running Ralph Inside Docker Sandbox

Ralph needs to run INSIDE the container:

```bash
cd ~/chippie-dev

# Start sandbox interactively
docker sandbox run claude

# Inside container, install Ralph (first time only)
git clone https://github.com/frankbria/ralph-claude-code.git /tmp/ralph
cd /tmp/ralph && ./install.sh

# Run Ralph
cd /workspace
ralph --monitor --calls 30
```

Or create a wrapper script (see Section 8).

---

## 3. Session Persistence: tmux on Server

### Your Previous Problem

Your local tmux survived, but the SSH session inside it died when your laptop slept. Claude on the server lost its terminal and stopped.

### Solution: tmux ON THE SERVER

```
[Laptop] → [SSH] → [Server tmux] → [Docker container] → [Ralph + Claude]
              ↓
         SSH drops when laptop sleeps
              ↓
         Server tmux keeps running
              ↓
         Docker container keeps running
              ↓
         Ralph continues working ✓
```

### Setup

```bash
# SSH to server
ssh opc@oracle

# Create tmux session ON THE SERVER
tmux new-session -s ralph

# Inside tmux, start the Docker sandbox
cd ~/chippie-dev
docker sandbox run claude

# Inside container, run Ralph
ralph --monitor --calls 30

# DETACH from tmux (not exit!)
# Press: Ctrl+B, then D

# Close laptop, sleep. Ralph keeps running.

# Next morning:
ssh opc@oracle
tmux attach -t ralph
```

### tmux Config

Add to `~/.tmux.conf` on server:

```bash
set -g mouse on
set -g history-limit 50000
```

---

## 4. Code Isolation: Git Worktree

One worktree. Multiple branches. Switch branches for different features.

### Setup (Once)

```bash
cd ~/chippie                    # Production repo
git worktree add ~/chippie-dev -b ralph/dev origin/main
```

### Per-Feature Workflow

```bash
cd ~/chippie-dev

# Night 1: Invoice feature
git checkout -b ralph/invoice-pdf origin/main
# Ralph works...

# Morning: Review and merge
cd ~/chippie
git merge ralph/invoice-pdf

# Night 2: Quote feature (same worktree, new branch)
cd ~/chippie-dev
git checkout -b ralph/quote-templates origin/main
# Ralph works...
```

**No need for multiple worktrees** unless running multiple Ralph instances in parallel.

---

## 5. Database Isolation

### Option A: Separate PostgreSQL Instance

```bash
# Create dev cluster on port 5433
sudo pg_createcluster 15 dev --port 5433
sudo pg_ctlcluster 15 dev start

# Create database
sudo -u postgres psql -p 5433 -c "CREATE DATABASE chippie_dev;"
sudo -u postgres psql -p 5433 -c "CREATE USER chippie_dev WITH PASSWORD 'devpass';"
sudo -u postgres psql -p 5433 -c "GRANT ALL ON DATABASE chippie_dev TO chippie_dev;"

# Copy schema
pg_dump -p 5432 --schema-only chippie_prod | psql -p 5433 chippie_dev
```

### Option B: Same Instance, Different Database

```bash
sudo -u postgres psql -c "CREATE DATABASE chippie_dev;"
pg_dump --schema-only chippie_prod | psql chippie_dev
```

### Environment File

In `~/chippie-dev/.env`:

```bash
DATABASE_URL=postgresql://chippie_dev:devpass@host.docker.internal:5433/chippie_dev
```

Note: Use `host.docker.internal` to connect from inside Docker container to host PostgreSQL.

---

## 6. Token Management

### Max 5x Limits
- ~225+ messages per 5-hour window
- Fixed $100/month cost
- Risk: running out of quota, not money

### Conservative Rate Limiting

```bash
ralph --calls 30 --timeout 20 --monitor
```

- 30 calls/hour max
- 20-minute timeout per call
- Leaves quota for morning work

---

## 7. Task Selection via Beads

**Beads is the single source of truth.** No secondary task lists.

### How Ralph Selects Work

Ralph uses `bv --robot-triage` to get prioritized, unblocked issues:

```bash
# Inside the loop, Ralph runs:
bv --robot-triage | jq -r '.recommendations[0].id'
```

This returns issues sorted by triage score (PageRank, betweenness, priority, urgency). Ralph picks the top ready issue and works it.

### Controlling Tonight's Scope

Use **priority** and **labels** to control what Ralph works on:

```bash
# Set high priority for tonight's work
bd update Chippie-abc --priority 0
bd update Chippie-def --priority 1

# Or use a label to tag approved work
bd label add Chippie-abc tonight
bd label add Chippie-def tonight

# Ralph's prompt can filter:
# "Only work on issues with label 'tonight' or priority 0-1"
```

### Blocking Unapproved Work

For issues you don't want Ralph to touch:

```bash
# Lower priority (Ralph picks higher scores first)
bd update Chippie-xyz --priority 4

# Or explicitly defer
bd update Chippie-xyz --status deferred

# Or add a blocking dependency
bd dep add Chippie-xyz Chippie-human-review
```

### Pre-Flight Check

Before starting Ralph:

```bash
# See what's ready and how it's prioritized
bv --robot-triage | jq '.recommendations[:10] | .[] | {id, title, score: .triage_score}'

# Verify no cycles
bd dep cycles

# Sync beads state
bd sync
```

---

## 8. Complete Setup

### One-Time Server Setup

```bash
ssh opc@oracle

# Install dependencies
sudo apt update
sudo apt install -y tmux git docker.io
sudo systemctl enable docker
sudo usermod -aG docker opc

# Logout and login for docker group
exit
ssh opc@oracle

# Set up dev database (see Section 5)

# Create worktree
cd ~/chippie
git worktree add ~/chippie-dev -b ralph/dev origin/main

# Initialize beads if not already present
cd ~/chippie-dev
bd init                    # Creates .beads/ directory

# First Docker sandbox run (authenticates)
docker sandbox run claude
# Enter API key when prompted
# Then install Ralph and beads tools inside container:
git clone https://github.com/frankbria/ralph-claude-code.git /tmp/ralph
cd /tmp/ralph && ./install.sh
# Install beads (bd) and beads_viewer (bv) per their docs
exit
```

### Create Wrapper Script

Create `~/start-ralph.sh`:

```bash
#!/bin/bash
set -e

WORKDIR=${1:-~/chippie-dev}
CALLS=${2:-30}

cd "$WORKDIR"

# Start Docker sandbox and run Ralph
docker sandbox run claude bash -c "
  cd /workspace
  ralph --monitor --calls $CALLS
"
```

### Nightly Workflow

```bash
# Evening
ssh opc@oracle
cd ~/chippie-dev

# Review and prioritize beads for tonight
bd ready                              # See unblocked work
bv --robot-triage | jq '.recommendations[:5]'  # Check triage ranking

# Adjust priorities if needed
bd update Chippie-abc --priority 0    # Must do tonight
bd update Chippie-xyz --priority 4    # Not tonight

# Create feature branch
git checkout -b ralph/tonights-feature origin/main

# Sync beads before starting
bd sync

# Start in tmux
tmux new-session -s ralph
~/start-ralph.sh ~/chippie-dev 30

# Detach: Ctrl+B, D
# Close laptop


# Morning
ssh opc@oracle
tmux attach -t ralph

# Review verification queue
cd ~/chippie-dev
bnr                        # See what needs verification
# For each issue: read instructions in preview, test, then:
bV                         # Mark as verified

# Review code
git log --oneline -10
pytest

# Sync beads state
bd sync

# Merge if good
cd ~/chippie
git merge ralph/tonights-feature

# Stop
tmux kill-session -t ralph
```

---

## 9. Prompt Templates

### PROMPT.md

```markdown
# Ralph Instructions

## Project
Chippie: Business management for Australian tradies.
Flask + SQLAlchemy + HTMX.

## Task Selection
Use beads for all task tracking. Select work using:
```bash
bv --robot-triage | jq -r '.recommendations[0].id'
```
Work on issues with priority 0-2. Skip priority 3-4 unless nothing else is ready.

## Workflow Per Task
1. Claim: `bd update <id> --status in_progress`
2. Read details: `bd show <id>`
3. Implement and test
4. Commit with conventional format
5. Close and mark for verification:
   ```bash
   bd close <id>
   bd set-state <id> verified=needs-review --reason "VERIFICATION:
   1. [Steps to test]
   2. [Expected result]
   NOTES: [What changed]"
   ```
6. Pick next task or exit

## Rules
1. All tests must pass before closing an issue
2. Commit after each logical change
3. Always mark closed issues `verified=needs-review` with test instructions

## Exit When
- No ready issues with priority 0-2: `bd ready --priority 2` returns empty
- Blocked on external input (human decision needed)
- Same error 3+ times (circuit breaker)

## Status Block (Required)
\`\`\`
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
CURRENT_TASK: <beads-id>
EXIT_SIGNAL: false | true
---END_RALPH_STATUS---
\`\`\`
```

---

## 10. Quick Reference

### Commands

```bash
# SSH
ssh opc@oracle

# tmux (on server)
tmux new -s ralph           # Create
tmux attach -t ralph        # Attach
tmux ls                     # List
# Ctrl+B, D                 # Detach

# Docker sandbox
docker sandbox run claude   # Start/resume
docker sandbox ls           # List
docker sandbox rm <id>      # Remove

# Ralph (inside container)
ralph --monitor --calls 30
ralph --status
ralph --reset-circuit

# Beads (task tracking)
bd ready                    # Unblocked work
bd update <id> --priority N # Set priority (0=critical, 4=backlog)
bd update <id> --status in_progress
bd close <id>               # Complete issue
bd sync                     # Sync with git

# Beads Viewer (triage)
bv --robot-triage | jq '.recommendations[:5]'

# Verification (morning review)
bnr                         # Issues needing verification
bV                          # Mark as verified

# Git (in worktree)
git checkout -b ralph/feature origin/main
```

### Files

```
~/chippie/              # Production (untouched)
~/chippie-dev/          # Worktree (mounted in container)
├── .beads/
│   └── issues.jsonl    # Task tracking (single source of truth)
├── .ralph/
│   ├── PROMPT.md       # Instructions for Claude
│   └── logs/
└── .env
```

### Checklist

```
Evening:
□ bd ready               # Review unblocked work
□ Adjust priorities (bd update <id> --priority N)
□ bd sync                # Sync beads state
□ git checkout -b ralph/feature origin/main
□ tmux new -s ralph
□ docker sandbox run claude → ralph --monitor
□ Ctrl+B, D to detach
□ Close laptop

Morning:
□ tmux attach -t ralph
□ bnr                    # Review verification queue
□ Test each issue per verification instructions
□ bV                     # Mark verified issues
□ git log, pytest
□ bd sync                # Sync beads state
□ Merge if happy
□ tmux kill-session -t ralph
```

---

## Summary

**What makes this safe:**

| Layer | Protects Against |
|-------|-----------------|
| Docker container | Filesystem access, credential theft, system modification |
| Git worktree | Accidental changes to production code |
| Separate database | Production data corruption |
| Server-side tmux | Session loss when laptop sleeps |

**Without Docker sandbox**, `--dangerously-skip-permissions` lets Claude access your entire system. **With Docker sandbox**, Claude is jailed to `/workspace` and cannot escape.
