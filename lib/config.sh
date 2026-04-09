# config.sh — Default configuration values for ralph.
#
# These globals are the starting state before argument parsing overrides them.
# Every variable here can be changed via CLI flags (see args.sh).

# How many tasks to complete before stopping. 0 means unlimited.
MAX_TASKS=0

# Maximum number of Claude invocations before stopping.
MAX_LOOPS=50

# Minutes before a single Claude invocation is killed.
TIMEOUT_MINUTES=10

# Maximum turns per Claude invocation.
MAX_TURNS=500

# Regex pattern to filter which beads issues to work on.
# Empty string means "work on everything ready".
SCOPE=""

# Path to a playlist file for ordered task execution.
# When set, ralph executes tasks in file order instead of using br ready.
# Mutually exclusive with --scope.
PLAYLIST=""

# Whether Claude should commit per-task. Default true for normal mode.
# In playlist mode, defaults to false (commits at checkpoint prompts instead).
AUTO_COMMIT=true

# When true, ralph shows the next task and exits without invoking Claude.
DRY_RUN=false

# Claude model to use for inner loop invocations.
MODEL="haiku"

# When true, wrap Claude invocation in bubblewrap for filesystem isolation.
# Linux only — requires bwrap installed.
SANDBOX_MODE=false

# When true, show live monitoring dashboard instead of running the loop.
MONITOR_MODE=false

# When true, run ralph on a remote server via SSH+tmux.
REMOTE_MODE=false

# When true, wrap ralph execution in a detachable tmux session.
# Used standalone (manual SSH) or triggered by --remote.
TMUX_MODE=false

# Git clone URL for the project repo. Populated by run_remote() from
# `git remote get-url origin` and passed to the remote via env var.
CLONE_URL=""

# SSH target for remote execution (e.g. "opc@oracle").
# Used as default when --remote is given without a host argument.
REMOTE_HOST=""

# Working directory on the remote server.
# Empty means use the remote user's home directory.
REMOTE_DIR=""

# File in the project root that persists loop state between runs.
STATE_FILE=".ralph/state"

# Branch ralph creates its working branch from (e.g. "dev", "main").
# Typically set per-project in .ralph/config. If unset, uses current branch.
# WORKING_BRANCH=""

# Suppress neovim hook in non-interactive claude -p mode.
export OPEN_NVIM=false

# Set before each exit point so the cleanup trap knows why we stopped.
EXIT_REASON="unknown"

# ── Per-project overrides ─────────────────────────────────────────────────
# A .ralph/config in the project root can override any of the above defaults.
# CLI args (see args.sh) override both defaults and project config.
# shellcheck source=/dev/null
if [[ -f ".ralph/config" ]]; then source ".ralph/config"; fi
