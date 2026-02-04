# scout.conf — Configuration Reference

Copy this to `.scout.conf` in your project root and adjust for your codebase.

All values can also be set as environment variables (env vars take precedence).

```bash
# ===========================================================================
# scout.conf — Configuration for the scout issue triage tool
# ===========================================================================

# ---------------------------------------------------------------------------
# API Configuration
# ---------------------------------------------------------------------------

# Anthropic API key for AI analysis.
# Falls back to ANTHROPIC_API_KEY if not set.
# Required for AI-powered analysis. Without it, scout still runs mechanical
# recon but skips the synthesis step.
# SCOUT_API_KEY=""

# Model for AI analysis.
# Haiku is recommended for cost efficiency — it's doing synthesis, not coding.
# Options: claude-haiku-4-5-20251001, claude-sonnet-4-5-20250929
SCOUT_MODEL="claude-haiku-4-5-20251001"

# ---------------------------------------------------------------------------
# Codebase Configuration
# ---------------------------------------------------------------------------

# Source directories to scan during reconnaissance (space-separated).
# The scout greps these for functions, classes, and patterns mentioned in issues.
# Adjust to match your project structure.
SCOUT_SRC_DIRS="app src lib"

# Test directories to check for existing test coverage (space-separated).
SCOUT_TEST_DIRS="tests test spec"

# File extensions to look for during entity extraction (space-separated).
# These are matched against file paths mentioned in issue descriptions.
#
# For a Flask/Python project (like Chippie):
SCOUT_FILE_EXTS="py html js css"
#
# For a Node.js/TypeScript project:
# SCOUT_FILE_EXTS="ts tsx js jsx css html vue svelte"
#
# For a Go project:
# SCOUT_FILE_EXTS="go html css js"

# ---------------------------------------------------------------------------
# Scan Behaviour
# ---------------------------------------------------------------------------

# Hours before a scan is considered stale and eligible for re-priming.
# Default: 24 (re-prime daily)
# Set lower for fast-moving codebases, higher for stable ones.
SCOUT_SCAN_TTL=24

# Maximum issues to process in a single batch run.
# Safety limit to prevent runaway costs.
SCOUT_MAX_ISSUES=20

# Maximum concurrent scout agents.
# Each scout is a Claude Haiku instance investigating one issue.
# Higher = faster priming, more parallel API usage.
SCOUT_MAX_PARALLEL=3

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

# Where scout reports are stored.
# Default puts them inside .beads/ so they travel with the repo.
# Reports are JSON files — one per issue — safe to regenerate any time.
SCOUT_DATA_DIR=".beads/scout"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# Suppress terminal output. Set to "true" for agentic/scripted use.
# Can also be set per-invocation with --quiet flag.
SCOUT_QUIET="false"
```
