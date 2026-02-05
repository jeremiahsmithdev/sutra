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

# Regex pattern to filter which beads issues to work on.
# Empty string means "work on everything ready".
SCOPE=""

# When true, ralph shows the next task and exits without invoking Claude.
DRY_RUN=false

# When true, wrap Claude invocation in bubblewrap for filesystem isolation.
# Linux only — requires bwrap installed.
SANDBOX_MODE=false

# When true, run ralph on a remote server via SSH+tmux.
REMOTE_MODE=false

# SSH target for remote execution (e.g. "opc@oracle").
# Used as default when --remote is given without a host argument.
REMOTE_HOST=""

# Working directory on the remote server.
# Empty means use the remote user's home directory.
REMOTE_DIR=""

# File in the project root that persists loop state between runs.
STATE_FILE=".ralph_state"

# Branch ralph creates its working branch from (e.g. "dev", "main").
# Typically set per-project in .ralph.conf. If unset, uses current branch.
# WORKING_BRANCH=""

# Suppress neovim hook in non-interactive claude -p mode.
export OPEN_NVIM=false

# Set before each exit point so the cleanup trap knows why we stopped.
EXIT_REASON="unknown"

# ── Per-project overrides ─────────────────────────────────────────────────
# A .ralph.conf in the project root can override any of the above defaults.
# CLI args (see args.sh) override both defaults and project config.
# shellcheck source=/dev/null
if [[ -f ".ralph.conf" ]]; then source ".ralph.conf"; fi
