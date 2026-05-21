# config.sh — Default configuration values for sutra.
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
MAX_TURNS=100

# Regex pattern to filter which beads issues to work on.
# Empty string means "work on everything ready".
SCOPE=""

# Path to a playlist file for ordered task execution.
# When set, sutra executes tasks in file order instead of using br ready.
# Mutually exclusive with --scope.
PLAYLIST=""

# Whether Claude should commit per-task. Default true in both standard and
# playlist modes — Claude commits each bead's code + .beads/ updates together
# (one commit per bead) per prompt rule 5 in templates/prompt_bead.txt.
# The outer loop does not commit on Claude's behalf in playlist mode.
AUTO_COMMIT=true

# When true, sutra shows the next task and exits without invoking Claude.
DRY_RUN=false

# Claude model to use for inner loop invocations.
MODEL="haiku"

# When true, wrap Claude invocation in bubblewrap for filesystem isolation.
# Linux only — requires bwrap installed.
SANDBOX_MODE=false

# When true, show live monitoring dashboard instead of running the loop.
MONITOR_MODE=false

# When true, run sutra on a remote server via SSH+tmux.
REMOTE_MODE=false

# When true, wrap sutra execution in a detachable tmux session.
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

# Comma-separated list of project files to include as a manifest in prompts.
# Each file's first comment/docstring line is extracted as a purpose summary.
# Set per-project in .sutra/config. Override with --context-files.
CONTEXT_FILES=""

# Minimum bead-to-gate ratio for playlist density warnings.
GATE_DENSITY_RATIO=7

# Advisory threshold: epic descriptions longer than this many lines trigger a
# warning in `playlist init` Phase 1. Long epic descriptions re-inject into
# every child invocation, burning tokens on irrelevant context.
# See CLAUDE.md §Epic description conventions.
EPIC_DESC_LINE_WARN=40

# Maximum number of "Remaining" items shown in the ## Playlist Progress prompt
# excerpt. Items beyond this cap are replaced with a "…plus N more" tail line.
# Tune down to 1 on token-constrained models; raise to 5+ for full visibility.
PLAYLIST_PROGRESS_LOOKAHEAD=3

# Auto-escalate model on retry (haiku→sonnet→opus).
AUTO_ESCALATE=true

# Maximum cost in USD before halting. 0 = no limit.
MAX_COST_USD=0

# Hard cap on injected beads per run. 0 = use ratio-based default.
MAX_INJECTED_BEADS=0

# If MAX_INJECTED_BEADS=0, limit = max(5, floor(total_beads * ratio)).
INJECTION_RATIO=0.25

# When true, a playlist missing the ✓ VALIDATED: marker will proceed in
# non-interactive mode (tmux, CI, remote) with a warning instead of halting.
# Set in .sutra/config for CI/CD environments that self-validate externally.
# Override with --yes on the CLI.
PLAYLIST_AUTO_CONTINUE=false

# YES=true is the internal flag set by --yes. It mirrors PLAYLIST_AUTO_CONTINUE
# for the validation-marker bypass only; prefer PLAYLIST_AUTO_CONTINUE in config.
YES=false

# Resolved playlist branch name. Empty = non-playlist mode.
PLAYLIST_BRANCH=""

# CLI input for --playlist-branch (feeds into resolution, not used directly).
PLAYLIST_BRANCH_CLI=""

# File in the project root that persists loop state between runs.
STATE_FILE=".sutra/state"

# Re-exec the queue runner between entries when sutra's own source tree
# moves to a new git SHA. Opt-in; off by default to avoid surprising
# scripted runs. Set via --auto-reload. Only fires at queue boundaries
# (not mid-playlist) — bash globals can't be safely re-sourced mid-flight.
AUTO_RELOAD=false

# Captured by the `sutra` top-level script before initialize(). Used by
# the queue runner to detect that sutra's own source has been updated
# since this process started.
SUTRA_START_SHA=""

# Branch sutra creates its working branch from (e.g. "dev", "main").
# Typically set per-project in .sutra/config. If unset, uses current branch.
# WORKING_BRANCH=""

# Suppress neovim hook in non-interactive claude -p mode.
export OPEN_NVIM=false

# Set before each exit point so the cleanup trap knows why we stopped.
EXIT_REASON="unknown"

# ── Per-project overrides ─────────────────────────────────────────────────
# A .sutra/config in the project root can override any of the above defaults.
# CLI args (see args.sh) override both defaults and project config.
# shellcheck source=/dev/null
if [[ -f ".sutra/config" ]]; then source ".sutra/config"; fi
