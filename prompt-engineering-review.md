# Ralph Prompt Engineering Review

This document catalogues every prompt that ralph passes to Claude Code (the inner loop), the algorithm that governs when and how each prompt is assembled, and the runtime parameters that shape invocation. It is intended for external review and optimisation of the prompt engineering strategy.

---

## Table of Contents

1. [System Architecture](#1-system-architecture)
2. [Invocation Parameters](#2-invocation-parameters)
3. [Prompt Type 1: Bead Task Execution](#3-prompt-type-1-bead-task-execution)
4. [Prompt Type 2: Raw Playlist Prompt](#4-prompt-type-2-raw-playlist-prompt)
5. [Prompt Type 3: Quality Gate Expansion](#5-prompt-type-3-quality-gate-expansion)
6. [Prompt Type 4: Retry Context Injection](#6-prompt-type-4-retry-context-injection)
7. [Prompt Type 5: Playlist Completion Report](#7-prompt-type-5-playlist-completion-report)
8. [Prompt Type 6: Project Summary Generation](#8-prompt-type-6-project-summary-generation)
9. [Prompt Type 7: Playlist Creation](#9-prompt-type-7-playlist-creation)
10. [Prompt Type 8: Playlist Semantic Validation](#10-prompt-type-8-playlist-semantic-validation)
11. [Conditional Prompt Sections](#11-conditional-prompt-sections)
12. [Cross-Bead Handoff Protocol](#12-cross-bead-handoff-protocol)
13. [Prompt Assembly Algorithm](#13-prompt-assembly-algorithm)
14. [External Review Prompt](#14-external-review-prompt)

---

## 1. System Architecture

Ralph is a bash outer loop that feeds tasks to Claude Code one at a time. The outer loop is deterministic — it selects work, constructs a prompt, invokes Claude, and evaluates the outcome. All intelligence lives in Claude (the inner loop).

**Invocation flow:**

```
select_task → build_prompt → invoke_claude → check_outcome → repeat
```

Claude receives a single string via `claude -p "$prompt"`. There is no system prompt, no multi-turn conversation, no message history between invocations. Each invocation is a fresh session. Cross-invocation context is passed explicitly through the prompt text.

There are **8 distinct prompt types**, each built from templates with `{{KEY}}` placeholder substitution. The prompt type depends on what the outer loop is doing at that moment.

---

## 2. Invocation Parameters

Every Claude invocation uses these CLI flags:

```bash
claude \
    -p "$prompt" \                          # The assembled prompt string
    --dangerously-skip-permissions \         # No interactive approval for tool use
    --model "$MODEL" \                       # haiku | sonnet | opus
    --output-format stream-json \            # Structured output for parsing
    --max-turns "$MAX_TURNS" \               # Default: 500
    --verbose                                # Full tool-use logging
```

Wrapped in a timeout (`gtimeout ${TIMEOUT_SECS}s`) and optionally a bubblewrap sandbox.

**Key parameters:**
- `MODEL`: default `haiku`, overridable via `--model`, per-line `@model` annotation, or auto-escalation after failure
- `MAX_TURNS`: default 500 per invocation
- `TIMEOUT_MINUTES`: default 10 minutes per invocation
- `MAX_RETRIES`: 3 attempts before giving up on a single invocation

**Model escalation on failure:** After a failed invocation, if the model is below the ceiling, it escalates: `haiku → sonnet → opus`. The escalated model applies to the retry, not permanently.

---

## 3. Prompt Type 1: Bead Task Execution

**When used:** Standard mode (one task from `br ready`) and playlist mode (bead-type lines).

**Source template:** `templates/prompt_bead.txt`

**Full template text:**

```
You are executing a single task from a beads issue tracker as part of an automated ralph loop.

## Your Task
ID: {{TASK_ID}}
{{DETAILS}}
{{PRIOR_TASK_CONTEXT}}
## Orientation
Before implementing, orient yourself to what the previous bead left behind:

1. Run `git status` to see if the working tree is dirty.
   * If dirty: run `git diff` — this is the previous bead's uncommitted work in playlist mode (AUTO_COMMIT=false by default). Read it before making changes so you understand what's in flight.
   * If clean: run `git log --oneline -5` and `git show HEAD` — the previous bead's work is in the most recent commit(s). Read the diff to see what changed.
2. If a `## Prior Task Context` section appears above, treat it as the previous agent's CLAIM about what it did. Use `git diff` / `git show HEAD` to verify that claim against ground truth before trusting it.
3. Do not re-explore files that the orientation already showed you changed. Start from the established state.

## Branch
{{BRANCH_SECTION}}

## Rules
1. Implement this ONE task completely. Do not work on other tasks.
2. Search the codebase before assuming anything about structure.
3. Run tests or manual verification after implementation.
{{COMMIT_RULE}}
5. If you are blocked and cannot complete the task, say so clearly.
6. Do NOT touch .beads/ files — never commit, stash, or modify them. Do NOT run `br sync`. The outer loop handles beads state automatically.
7. Prefer Read, Grep, and Glob tools for file operations. Only spawn Agent sub-tasks when exploring unfamiliar parts of the codebase that are not described in this task or the project context. Direct tool use is faster and cheaper.
{{FILE_MAP}}
{{PROJECT_SUMMARY}}
## When Done
Close the issue with a reason that a human reviewer can use to verify your work:
  br close {{TASK_ID}} --reason "VERIFY: [how to test] NOTES: [what changed]"

If you are BLOCKED and cannot complete the task, release it:
  br update {{TASK_ID}} --status open
```

### Substitution Values

| Placeholder | Source | Example |
|---|---|---|
| `{{TASK_ID}}` | Bead ID from `br ready` or playlist line | `ralph-yys.2` |
| `{{DETAILS}}` | `get_task_details()` — title, description, notes, acceptance criteria, design | Multi-line labelled text |
| `{{PRIOR_TASK_CONTEXT}}` | Conditional. See [Cross-Bead Handoff](#12-cross-bead-handoff-protocol) | Previous agent's claimed summary |
| `{{BRANCH_SECTION}}` | One of 4 branch templates (see below) | Branch checkout instructions |
| `{{COMMIT_RULE}}` | Conditional on `AUTO_COMMIT` | Commit or don't-commit instruction |
| `{{FILE_MAP}}` | Conditional on `CONTEXT_FILES` config | Path+purpose list of key project files |
| `{{PROJECT_SUMMARY}}` | Conditional on `.ralph/project-context.md` | Cached project overview (truncated to 100 lines) |

### `{{DETAILS}}` Format

Produced by `get_task_details()` from `br show --json`. Each non-empty field is rendered:

```
Title: <title>
Description: <full description text>
Notes: <session handoff notes>
Acceptance Criteria: <criteria>
Design: <design notes>
```

### `{{COMMIT_RULE}}` Variants

When `AUTO_COMMIT=true` (standard mode default):
```
4. Commit your changes with a conventional commit message.
```

When `AUTO_COMMIT=false` (playlist mode default):
```
4. Do NOT commit. Leave changes staged or unstaged — commits are handled externally.
```

### Branch Section Variants

**Standalone task** (no epic, no playlist):
```
Work on the `ralph` branch.
Ensure you are on it before starting:
  git checkout ralph
Do NOT create feature branches for standalone tasks. Commit directly to `ralph`.
```

**Epic task, branched from ralph:**
```
This task belongs to an epic. Work on branch `ralph-<epic-slug>`.
If the branch does not exist, create it from `ralph`:
  git checkout ralph && git checkout -b ralph-<epic-slug>
If it already exists:
  git checkout ralph-<epic-slug>
Commit all work to `ralph-<epic-slug>`. Do NOT merge — merging happens at harvest.
```

**Epic task, branched from a dependency epic:**
```
This task belongs to an epic that depends on a prior epic.
Work on branch `ralph-<epic-slug>`.
If the branch does not exist, create it from `ralph-<dep-slug>` (the dependency):
  git checkout ralph-<dep-slug> && git checkout -b ralph-<epic-slug>
If it already exists:
  git checkout ralph-<epic-slug>
Commit all work to `ralph-<epic-slug>`. Do NOT merge — merging happens at harvest.
```

**Playlist mode:**
```
You are working on branch `<playlist-branch>`. This is the single branch for this entire playlist session.
Do NOT create feature branches. Do NOT run `git checkout` to any other branch.
Commit directly on `<playlist-branch>`. Merging is a separate manual step.
```

---

## 4. Prompt Type 2: Raw Playlist Prompt

**When used:** Playlist lines prefixed with `>` (free-form prompts, not bead tasks).

**Source template:** `templates/prompt_raw.txt`

**Full template text:**

```
You are performing a maintenance task between automated bead implementations
in the ralph autonomous loop.

## Task
{{PROMPT_TEXT}}
{{PRIOR_TASK_CONTEXT}}
## Context
* Working directory: {{WORKING_DIR}}
* Branch: {{CURRENT_BRANCH}}
* Recent commits:
{{RECENT_COMMITS}}

## Rules
1. Search the codebase before assuming anything about structure.
2. Make targeted fixes and commit with conventional commit messages.
3. You may update beads using br update/br create/br close as needed.
4. Do NOT touch .beads/ files directly — use br commands only.
5. Do NOT run br sync — the outer loop handles that.
6. When done, just exit. There is no bead to close for this task.
7. Prefer Read, Grep, and Glob tools for file operations. Only spawn Agent sub-tasks when exploring unfamiliar parts of the codebase that are not described in this task or the project context. Direct tool use is faster and cheaper.
{{FILE_MAP}}
```

### Substitution Values

| Placeholder | Source | Example |
|---|---|---|
| `{{PROMPT_TEXT}}` | Literal text after `>` in playlist, or expanded gate template | `Review the auth changes` |
| `{{PRIOR_TASK_CONTEXT}}` | Same as bead prompt | Previous agent's claimed summary |
| `{{WORKING_DIR}}` | `$(pwd)` | `/Users/admin/dev/myproject` |
| `{{CURRENT_BRANCH}}` | `git branch --show-current` | `ralph-auth-epic.playlist` |
| `{{RECENT_COMMITS}}` | `git log --oneline -5` | 5 most recent commit subjects |
| `{{FILE_MAP}}` | Same as bead prompt | Path+purpose list |

---

## 5. Prompt Type 3: Quality Gate Expansion

**When used:** Playlist lines containing `#TAG` after the `>` prefix (e.g., `>@opus #SMOKE_TEST context`).

The gate tag is expanded into full instructions at runtime and injected as the `{{PROMPT_TEXT}}` in the raw prompt template (Type 2). The `#TAG` never reaches Claude — it is resolved to the corresponding template text before invocation.

### Gate Templates

**`#SMOKE_TEST`** (from `templates/gate_smoke_test.txt`):
```
Test API endpoints against live backend. curl each endpoint implemented in the last batch of beads. Verify responses match expected schemas.
If issues found: create beads (type=bug only) with br create, insert IDs into the playlist file after this line.
```

**`#COMPLETENESS_SCAN`** (from `templates/gate_completeness_scan.txt`):
```
Scan for incomplete work: grep -rn 'TODO|FIXME|HACK|STUB|placeholder|not yet|not implemented' in the project source. For each match in code written during this playlist, implement it fully or remove it with justification.
If issues require separate tasks: create beads (type=bug only) and inject into playlist.
```

**`#REVIEW`** (from `templates/gate_review.txt`):
```
Review the work completed in the last epic. Check architecture, patterns, test coverage. Flag issues.
If significant work needed: create beads (type=bug only) and inject into playlist.
```

**`#REFACTOR`** (from `templates/gate_refactor.txt`):
```
You are performing a systematic refactor of code developed during this playlist session. The features work but need cleanup before the playlist continues.

## Review Mindset
Adopt the perspective of a skeptical senior developer reviewing code from a junior developer.
- Assume the code has problems until proven otherwise
- Question every decision: "Why was it done this way? Is there a better way?"
- Look for what's missing, not just what's wrong
- Be suspicious of complexity — simpler is almost always better
- Ask: "Does this already exist somewhere in the codebase?"

## Refactoring Process

### Phase 1: Analysis
1. Identify scope from git (session changes, not just uncommitted):
   - Run `git diff --stat` from the session branch point to see all modified/added files
   - Run `git diff` from the session branch point to review actual code changes
2. Read all modified files in full to understand current state
3. Check test coverage: note which areas have tests vs gaps
4. Map dependencies: understand how files relate to each other
5. Search for existing patterns — look beyond the changed files:
   - Search codebase for similar functionality that already exists
   - Check for utilities, helpers, or base classes that could have been extended
   - Look for established patterns the new code should follow but doesn't
   - Identify if a new module should have been an extension of an existing one
6. Identify structural violations:
   - Files > 200 lines (candidates for splitting)
   - Functions > 50 lines (candidates for extraction)
   - Mixed responsibilities (SRP violations)
   - Business logic in infrastructure layers
   - Duplicated code (DRY violations - Rule of Three)
   - Dead code from iteration pivots
   - Unclear naming from rapid development
7. Critical code review — scrutinize for real issues:
   - Reinventing the wheel: new code duplicating existing codebase functionality
   - Logic errors: off-by-one, wrong conditions, incorrect operators
   - Edge cases: null/empty handling, boundary conditions, error paths
   - Security: input validation, injection risks, exposed secrets, auth gaps
   - Error handling: swallowed exceptions, missing try/catch, unclear error messages
   - Performance: N+1 queries, unnecessary loops, missing indexes, memory leaks
   - Type safety: implicit any, unsafe casts, missing null checks
   - Incomplete implementations: TODOs, FIXMEs, placeholder code, stubbed functions

### Phase 2: Plan
Write a detailed plan to SCRATCHPAD.md with:
- **Must Fix**: security vulnerabilities, logic errors, broken error handling
- **Should Fix**: performance problems, type safety, edge cases
- **Consider**: minor improvements, naming, style
- **Reuse Opportunities**: new code duplicating existing codebase functionality
- **Structural Changes**: in order of execution with rationale
- **Deletions**: dead code to remove
- **Risk Assessment**: test coverage, estimated scope

### Phase 3: Execute
For each change:
1. Make one logical refactoring at a time
2. Run relevant tests to verify no regressions
3. Checkpoint after each logical unit

### Refactoring Priorities (in order)
1. Fix critical issues — security vulnerabilities, logic errors, broken error handling
2. Fix secondary issues — performance problems, type safety, edge cases
3. Replace reinvented code — swap custom implementations for existing codebase utilities/patterns
4. Delete dead code — remove unused functions, commented code, abandoned approaches
5. Extract duplicates — apply DRY where Rule of Three is met
6. Split monoliths — break large files by responsibility
7. Rename for clarity — improve naming from iteration artifacts
8. Align architecture — ensure clean architecture layer compliance
9. Simplify — remove over-engineering, unnecessary abstractions

## Rules
- Preserve intended functionality: bug fixes improve correctness, structural changes don't alter behavior
- No new features: only cleanup, no "while we're here" additions
- No premature abstraction: don't add patterns "for flexibility"
- Keep it boring: simple working code over clever patterns
- Note test gaps: if no tests exist for an area, flag the risk
- Prefer existing over new: if functionality exists in the codebase, use it
- If issues require separate work: create beads (type=bug only) with br create, insert IDs into the playlist file after this line
- Delete SCRATCHPAD.md when done
```

**`#DOCUMENT`** (from `templates/gate_document.txt`):
```
You are documenting completed features from this playlist session. Create or update documentation in the docs/ directory, maintaining docs/INDEX.md as the central navigation file.

## Documentation Process

### Phase 1: Analyze Current State
1. Identify scope from git (session changes):
   - Run `git diff --stat` from the session branch point to see all modified/added files
   - Run `git diff` from the session branch point to review actual code changes
2. Check docs/INDEX.md (if exists) — understand current doc structure
3. Scan docs/*.md — detect orphaned files not in INDEX.md
4. Read the implementation files identified from git to understand each feature

### Phase 2: Plan Documentation
Write a plan to SCRATCHPAD.md with:
- Current state: INDEX.md exists? Existing docs? Orphaned files?
- Actions: which docs to create, update, or consolidate
- ADR candidates: significant design decisions worth capturing
- Sections to write for each doc
- Implementation files to reference

### Phase 3: Write Documentation
Execute in order:
1. Create/update feature documentation files
2. Update docs/INDEX.md
3. Create architecture decision records (if significant decisions were made)

## INDEX.md Structure

The docs/INDEX.md is the central directory. Create if missing, always update.

### Quick Reference Table
| Feature | Doc | Last Updated | Status |
|---------|-----|--------------|--------|
| Feature Name | [feature.md](./feature.md) | YYYY-MM-DD | current |

### Categories
Organize by: Core Features, Integrations, Utilities, Architecture, Decisions

### Maintenance Log
Record each documentation change with date and description.

### Status Values
- current — up-to-date, maintained documentation
- needs-review — implementation may have changed
- outdated — known to be out of sync
- deprecated — feature removed/replaced, kept for reference

## Feature Documentation Template

Each feature doc (docs/<feature-name>.md) must include:

### Frontmatter
```
---
last_updated: YYYY-MM-DD
status: current
tracks:
  - path/to/primary_file
  - path/to/related_file
---
```

### Required Sections
- **Overview**: purpose, behavior, key concepts
- **How It Works**: high-level explanation, diagrams for complex flows
- **Implementation**:
  - Architecture: layers/modules involved, data flow
  - Key Components table: file path + purpose
  - Key Functions: function_name() — what it does
- **Configuration**: settings, environment variables, options
- **Usage Examples**: code examples
- **Related Docs**: links to related features, ADRs
- **Edge Cases & Limitations**: known limitations, assumptions

## Architecture Decision Records

Create ADRs (docs/decisions/NNN-<title>.md) when:
- Chose between multiple valid approaches
- Made tradeoffs future developers should understand
- Deviated from common patterns for a reason
- Decision affects multiple features or system architecture

ADR structure: Status, Context, Decision, Alternatives Considered, Consequences (positive/negative/neutral)

## Orphan Detection

Scan for .md files in docs/ not listed in INDEX.md. For each orphan, recommend:
- Index: add to INDEX.md (valid, just unlisted)
- Consolidate: merge into existing doc (duplicate content)
- Delete: remove (outdated, superseded)

## Rules
- INDEX.md is mandatory — create if missing, always update
- Consolidate over create — update existing docs rather than making duplicates
- Practical focus — document what developers need to know
- Code references — include file paths and key function names
- No filler — every sentence should add value
- Bidirectional links — feature docs link to INDEX.md, INDEX.md links to docs
- ADRs for decisions — capture why not just what for significant choices
- If issues require separate work: create beads (type=bug only) with br create, insert IDs into the playlist file after this line
- Delete SCRATCHPAD.md when done
```

### Gate Injection Capping

When the injection cap is reached (too many beads created during a session), the self-healing instruction line is stripped from gate templates at runtime. The capped variants remove the "create beads... inject into playlist" line, leaving only the observation/report instruction. This is done by `strip_injection_instructions()` applied to the template text before rendering.

### Context Appending

If the playlist line has user-provided context after the `#TAG`, it is appended after the template text:

```
<gate template text>
<user context from playlist line>
```

---

## 6. Prompt Type 4: Retry Context Injection

**When used:** When `invoke_claude` fails and retries. Appended to the existing prompt (not a replacement).

**Source template:** `templates/retry_context.txt`

**Full template text:**

```


## RETRY CONTEXT (attempt {{ATTEMPT}}/{{MAX_RETRIES}})
The previous attempt FAILED. Here is what happened:
* Exit code: {{EXIT_CODE}}
* Diagnosis: {{DIAGNOSIS}}

### Last output before failure
{{LAST_OUTPUT}}

IMPORTANT — adapt your approach:
* If the issue was a timeout: work in smaller steps, do less per invocation.
* If the issue was context overflow: produce shorter output, avoid large file reads.
* If the issue was an API error: this may be transient, try the same approach.
* If the issue was a tool error: try an alternative approach to achieve the same goal.
* Do NOT repeat the exact same sequence of actions that failed.
```

### Substitution Values

| Placeholder | Source | Example |
|---|---|---|
| `{{ATTEMPT}}` | Current retry number (2 or 3) | `2` |
| `{{MAX_RETRIES}}` | Always 3 | `3` |
| `{{EXIT_CODE}}` | Process exit code from failed invocation | `124` |
| `{{DIAGNOSIS}}` | Human-readable from `diagnose_exit_code()` | `Timeout — invocation exceeded 10m limit` |
| `{{LAST_OUTPUT}}` | Last 10 lines of stream-json, parsed via jq | Tool output or error text |

### Exit Code Diagnosis Table

| Code | Diagnosis |
|---|---|
| 124 | Timeout — invocation exceeded Nm limit |
| 137 | Killed (SIGKILL) — likely OOM or external signal |
| 1 | General error — possibly API failure, auth issue, or tool crash |
| 2 | Misuse — bad arguments or configuration |
| * | Unknown failure (exit code N) |

### Model Escalation

Before the retry prompt is built, the model may be escalated:
- `haiku → sonnet` on first failure
- `sonnet → opus` on second failure
- `opus` stays at `opus`

This happens independently of the retry context injection.

---

## 7. Prompt Type 5: Playlist Completion Report

**When used:** On exit from a playlist session where at least 1 task was completed. Invoked from the `cleanup()` trap.

**Source template:** `templates/prompt_report.txt`

**Full template text:**

```
You are generating a completion report for a ralph playlist run.

## Instructions
Write a markdown report to: {{REPORT_FILE}}
Create the directory {{REPORT_DIR}} if it does not exist (mkdir -p).

## Report Template

# Ralph Playlist Report: {{PLAYLIST_NAME}}
**Date:** {{TIMESTAMP}} **Model:** {{MODEL}}
**Exit reason:** {{EXIT_REASON}} **Circuit breaker:** {{CIRCUIT}}

## Summary
- Tasks completed: {{TASKS_COMPLETED}}
- Total loops: {{TOTAL_LOOPS}}
- Playlist: {{PLAYLIST_PATH}} ({{PLAYLIST_TOTAL}} items)
- Processed: {{PROCESSED}} / {{PLAYLIST_TOTAL}}

## Task Results
{{PLAYLIST_DATA}}

## Commits This Session
{{GIT_LOG}}

## Notes
Add any observations about the run: blocked tasks, patterns, issues discovered.

## Rules
1. Write the report file directly using the template above. Fill in the Notes section with useful observations.
2. Commit the report: git add {{REPORT_DIR}} && git commit -m 'docs(ralph): playlist completion report'
3. Do NOT modify any other files. Do NOT run br commands.
4. When done, just exit.
```

---

## 8. Prompt Type 6: Project Summary Generation

**When used:** At session start when `.ralph/project-context.md` is missing or stale (>24h or >10 commits since generation). Uses haiku regardless of session model.

**Prompt text (inline, not templated):**

```
Analyze this project and write a concise project summary to .ralph/project-context.md.
Include: directory structure (tree -L 2), key files and their purposes, dependency versions
(from package.json/pubspec.yaml/requirements.txt/Cargo.toml/go.mod), architecture patterns
observed, and any conventions (naming, testing, etc). Keep it under 300 lines.
Add <!-- generated-at: <COMMIT_HASH> --> as the FIRST line.
Output ONLY the file — no commentary.
```

The generated file is then injected into all subsequent bead and raw prompts as a `## Project Summary` section (truncated to 100 lines).

---

## 9. Prompt Type 7: Playlist Creation

**When used:** `ralph playlist create --epic <id> -o <file>` — generates a new playlist file.

**Source template:** `templates/prompt_playlist_create.txt`

**Full template text:**

```
Generate a ralph playlist file. Order the beads logically and insert quality gate lines.

RULES:
1. Order by dependency: foundational work before dependent work.
2. Insert gate lines at intervals:
   - After ~5 beads: >@opus #SMOKE_TEST <what to test based on preceding beads>
   - Every ~5 beads without a gate: > #COMPLETENESS_SCAN <what to scan>
   - At epic boundaries: >@opus #REVIEW <what to review>
3. Gate context must be SPECIFIC to the surrounding beads — not generic.
4. Do NOT add branch directives, comments, or blank lines.
5. Do NOT duplicate or invent bead IDs — only reorder the ones given.

OUTPUT: A single code block containing one bead ID or > prompt per line. Nothing else.

BEADS:
{{BEAD_DETAILS}}
{{EPIC_NOTES}}
```

### Substitution Values

| Placeholder | Source | Example |
|---|---|---|
| `{{BEAD_DETAILS}}` | Title + parent + dependencies per bead (no full description) | `ralph-yys.1 — Harness (parent: ralph-yys) [depends: ralph-yys]` |
| `{{EPIC_NOTES}}` | Only when multiple epics | `Multiple epics included. Mark epic boundaries with #REVIEW gates.` |

---

## 10. Prompt Type 8: Playlist Semantic Validation

**When used:** `ralph playlist init <file>` — Phase 2 after syntax validation passes.

**Source template:** `templates/prompt_playlist_validate.txt`

**Full template text:**

```
Audit this playlist for semantic correctness.

For each bead ID listed:
1. Check dependency ordering: does a bead depend on work that comes later in the playlist?
2. Flag any beads whose dependencies are missing from the playlist entirely.

For each gate line (> prefix with #TAG):
1. Check if the context is specific to the surrounding beads (not generic).
2. If a gate has no context after the #TAG, suggest specific context based on the surrounding beads.

Do NOT add a validation marker — the outer loop handles that.
Do NOT create or modify any files. Report findings as plain text only.

Print a short summary of findings when done.

PLAYLIST:
{{PLAYLIST_CONTENT}}

BEADS:
{{BEAD_DETAILS}}
```

---

## 11. Conditional Prompt Sections

These sections are injected into bead and raw prompts only when their source data exists. When absent, the `{{PLACEHOLDER}}` collapses to an empty string.

### Prior Task Context

**Condition:** Previous bead in the session was closed successfully.

**Source template:** `templates/prior_task_context.txt`

```

## Prior Task Context
The previous bead ({{LAST_TASK_ID}}) closed with this summary from its own final output:

{{LAST_TASK_SUMMARY}}

Treat this as a CLAIM, not ground truth — verify with `git diff` / `git show HEAD` (see Orientation below).
```

`LAST_TASK_SUMMARY` is the last assistant text block from the previous invocation's stream-json log, collapsed to ~200 words.

### Project File Map

**Condition:** `CONTEXT_FILES` is set in `.ralph/config` (e.g., `CONTEXT_FILES="pubspec.yaml,lib/main.dart"`).

Rendered as:

```

## Project File Map
* pubspec.yaml — Flutter project configuration
* lib/main.dart — Application entry point and routing setup
* lib/core/routing/app_router.dart — GoRouter configuration with auth guards
```

Each file's purpose is extracted from its first comment line (supports `#`, `//`, `/*`, `--` comment styles).

### Project Summary

**Condition:** `.ralph/project-context.md` exists and was generated by Prompt Type 6.

Rendered as `## Project Summary` followed by the first 100 lines of the cached file.

---

## 12. Cross-Bead Handoff Protocol

When a bead closes successfully, ralph captures context for the next invocation:

1. **Capture:** `capture_task_handoff()` extracts the last assistant text block from the stream-json log of the just-completed invocation. This is Claude's own summary of what it did.

2. **Truncate:** The text is collapsed to ~200 words via `truncate_to_word_limit()`.

3. **Store:** Saved in globals `LAST_TASK_ID` and `LAST_TASK_SUMMARY`.

4. **Inject:** When the next bead's prompt is built, `format_prior_task_context()` renders the `## Prior Task Context` section using `templates/prior_task_context.txt`.

5. **Clear:** After injection, `clear_task_handoff()` resets the globals so a retry of the same task doesn't re-inject stale data.

**Trust model:** The prompt explicitly tells Claude to treat the prior context as a "CLAIM, not ground truth" and verify against `git diff` / `git show HEAD`. This accounts for the possibility that the previous agent hallucinated its summary.

---

## 13. Prompt Assembly Algorithm

### Standard Mode (one task at a time from `br ready`)

```
LOOP:
  1. select_task()           → pick highest-priority unblocked task (skip epics)
  2. claim_task(tid)         → br update --status in_progress
  3. get_task_details(tid)   → title, description, notes, acceptance_criteria, design
  4. get_branch_context(tid) → standalone | epic:<branch>:<base> | playlist:<branch>
  5. format_branch_instructions(ctx)  → resolve to one of 4 branch templates
  6. format_commit_rule()             → commit or don't-commit based on AUTO_COMMIT
  7. format_prior_task_context()      → prior bead summary or empty
  8. format_file_map()                → CONTEXT_FILES manifest or empty
  9. format_project_summary()         → cached project overview or empty
  10. render_template(prompt_bead.txt, ...) → assemble final prompt
  11. invoke_claude(prompt)
      a. On failure: augment_prompt_with_failure_context() + model escalation → retry
      b. On success: check_bead_status() → update_circuit_breaker() → handle_task_outcome()
  12. If closed: capture_task_handoff() → save for next iteration
  13. save_state() → persist progress to disk
  REPEAT
```

### Playlist Mode

```
LOOP:
  1. playlist_next()         → advance past comments/blanks to next actionable line
  2. Classify line:
     a. BEAD line  → same as standard mode steps 2-13
     b. PROMPT line:
        i.  Check for @model annotation → apply model override
        ii. Check for #TAG gate tag → expand via gate_expand_tag()
        iii. build_raw_prompt(text) using prompt_raw.txt template
        iv. invoke_claude(prompt)
        v.  On success: reset circuit breaker (prompts always count as progress)
  3. save_state() → persist + advance playlist position
  REPEAT

ON EXIT (if tasks completed > 0):
  4. build_report_prompt() → invoke Claude to write completion report
```

### Playlist Creation (`ralph playlist create`)

```
1. Expand --epic arguments via br ready --parent=<id> -r
2. For each bead: extract title, parent, dependencies (NOT full description)
3. render_template(prompt_playlist_create.txt, BEAD_DETAILS, EPIC_NOTES)
4. invoke_claude(prompt) → Claude outputs a code block with ordered playlist
5. extract_playlist_from_log(INVOKE_LOG) → parse code block from stream-json
6. Write extracted content to output file
7. Pipe through run_playlist_init() for validation:
   a. Phase 1: Syntax validation (bead IDs exist, gate density)
   b. Phase 2: Semantic validation via prompt_playlist_validate.txt
8. Add validation marker to output file
```

### Project Summary Generation (session start)

```
1. Check if .ralph/project-context.md exists and is fresh:
   - File age < 24 hours
   - < 10 commits since the stored generation hash
2. If stale or missing:
   a. Temporarily set MODEL=haiku
   b. invoke_claude(inline prompt) → Claude writes the file
   c. Restore original MODEL
3. On subsequent prompts: format_project_summary() injects first 100 lines
```

---

## 14. External Review Prompt

The following prompt is designed to be passed to an external agent for comprehensive review and optimisation of the ralph prompt engineering system described above.

---

```
You are reviewing the prompt engineering strategy of an autonomous coding system called ralph. Ralph is a deterministic bash outer loop that feeds tasks to Claude Code one invocation at a time. Each invocation is a fresh session — no message history, no system prompt, no multi-turn conversation. All context must be in the single prompt string passed via `claude -p`.

The full catalogue of prompts, their templates, conditional sections, assembly algorithms, and runtime parameters is provided in the document above this prompt.

## Your Task

Perform a thorough review of the prompt engineering strategy. Your analysis should cover:

### 1. Prompt Structure and Clarity
- Are the prompts clear, unambiguous, and efficiently structured?
- Is there unnecessary verbosity or redundancy across templates?
- Are instructions actionable or vague?
- Is the ordering of sections within each prompt optimal for Claude's attention?
  (e.g., does critical information appear where Claude is most likely to weight it?)

### 2. Cross-Prompt Consistency
- Are the rules consistent across prompt types (bead, raw, gate, report)?
- Are there contradictions between what one prompt type says and another assumes?
- Is the trust model for cross-bead handoff coherent and well-enforced?

### 3. Instruction Effectiveness
- Do the "Rules" sections actually constrain Claude's behavior as intended?
- Are there instructions that Claude is likely to ignore or misinterpret?
- Are there missing constraints that would prevent known failure modes?
- Is the "Orientation" section (git status/diff before implementation) effective, or does it waste tokens/turns?

### 4. Context Efficiency
- Is the right amount of context being provided? Too much? Too little?
- Are the conditional sections (file map, project summary, prior task context) worth their token cost?
- Should any context be moved from the prompt to CLAUDE.md or system instructions?
- At what bead count does the project summary become stale enough to mislead rather than help?

### 5. Gate Template Quality
- Are the 5 gate templates (#SMOKE_TEST, #COMPLETENESS_SCAN, #REVIEW, #REFACTOR, #DOCUMENT) well-structured?
- Do they provide enough guidance for Claude to act autonomously?
- Are the self-healing instructions (create beads, inject into playlist) clear and safe?
- Is there a risk of gate prompts causing scope creep or unintended side effects?

### 6. Failure Recovery
- Is the retry context injection effective? Does it give Claude enough information to adapt?
- Is the model escalation strategy (haiku → sonnet → opus) well-aligned with typical failure modes?
- Should the retry prompt be more prescriptive about alternative approaches?

### 7. Missing Prompt Types
- Are there invocation scenarios that would benefit from a dedicated prompt template that doesn't currently exist?
- Should there be a "discovery" or "exploration" prompt type for unfamiliar codebases?

### 8. Anti-Patterns
- Are there prompt patterns that are known to be suboptimal with Claude (e.g., negative instructions, implicit assumptions, ordering effects)?
- Are there missed opportunities to use Claude's strengths (e.g., structured output, chain-of-thought, prefilled responses)?

### 9. Architectural Observations
- Is the single-prompt-per-invocation model optimal, or would multi-turn or system prompts improve outcomes?
- Should any prompt content be moved to a CLAUDE.md project file (which Claude reads automatically) vs. injected per-invocation?
- Is the 200-word cross-bead handoff sufficient for complex multi-step epics?

## Output Format

Structure your response as:

1. **Executive Summary** — Top 3-5 highest-impact findings
2. **Detailed Analysis** — Organised by the 9 categories above
3. **Specific Rewrites** — For any prompt text you'd change, show the before/after with rationale
4. **Architectural Recommendations** — Changes to the prompt assembly algorithm or system design
5. **Risk Assessment** — Potential failure modes in the current prompt strategy and mitigations
```

---