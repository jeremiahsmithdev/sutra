# Ralph — Recommended Changes

Synthesised from two independent external reviews, a full prompt engineering catalogue, and hands-on debugging of the playlist subsystem. Changes are grouped into three tiers by expected impact on task completion rates and cost efficiency. Each change includes what to do, where to do it, and why it matters.

Sources referenced throughout:
- **REVIEW.md** — Prompt structure, instruction effectiveness, and gate template analysis
- **research.md** — Anthropic documentation, CLI capabilities, and cross-system research
- **Session audit** — 8 bugs found during playlist stress testing (April 2026)

---

## Tier 1 — High Impact, Implement First

These changes address fundamental architectural gaps. Each one independently improves task completion rates or eliminates a class of failure.

### 1.1 Adopt `--bare` + `--append-system-prompt-file`

**What:** Switch all scripted invocations to `--bare` mode and move stable behavioural rules into a system prompt file loaded via `--append-system-prompt-file`.

**Where:** `lib/invoke.sh` (_invoke_claude_once), new file `ralph-system-prompt.md`

**Current state:** Ralph passes everything through `claude -p` as a user message. Claude Code's built-in system prompt loads by default, but ralph has no way to add stable rules to the system prompt layer. Local CLAUDE.md files, hooks, and MCP servers are auto-discovered, making behaviour vary across machines.

**Change:**
```bash
# In _invoke_claude_once(), replace current invocation with:
"${prefix[@]}" command claude \
    -p "$prompt" \
    --bare \
    --append-system-prompt-file "$RALPH_DIR/ralph-system-prompt.md" \
    --dangerously-skip-permissions \
    --model "$MODEL" \
    --output-format stream-json \
    --max-turns "$MAX_TURNS" \
    --verbose \
    > >(tee "$INVOKE_LOG" | format_stream) &
```

**`ralph-system-prompt.md` contents** — all rules that are invariant across invocation types:
- Beads state management (use `br` commands only, never touch `.beads/`)
- Tool preferences (prefer Read/Grep/Glob over Agent sub-tasks)
- Scope discipline (only modify files required by the current task)
- Git hygiene (no feature branches unless instructed, conventional commits, handle merge conflicts by stopping)
- The "do not run `br sync`" rule

**Why:** 
- Reproducibility: `--bare` skips auto-discovery of hooks, skills, plugins, MCP servers, and CLAUDE.md files, eliminating machine-to-machine variance.
- Cost savings: system prompt content is cacheable across invocations — the stable rules are paid for once, not every time.
- Stronger enforcement: system prompt instructions sit in a privileged position in Claude's attention hierarchy, above user messages.
- Prompt size reduction: removes ~150–200 tokens of repeated rules from every bead and raw prompt template.

**Sources:** research.md §2 ("Three critical CLI capabilities"), REVIEW.md §4.1 ("Migrate static rules to CLAUDE.md")

---

### 1.2 Calibrate `--max-turns` per prompt type

**What:** Replace the blanket `MAX_TURNS=500` with per-prompt-type turn limits.

**Where:** `lib/config.sh` (new defaults), `lib/invoke.sh` (accept turns parameter), `lib/prompt.sh` + `lib/playlist.sh` (pass turns to invoke), `lib/playlist_annotations.sh` (`@turns` annotation already exists)

**Current state:** Every invocation gets 500 max turns. Claude Code's default is unlimited. Anthropic recommends 5–10 for moderate tasks. A runaway agent at 500 turns will consume enormous token budgets before halting.

**Recommended values:**

| Prompt Type | Max Turns | Rationale |
|---|---|---|
| Bead task execution | 25 | Single feature, implement + test + commit |
| Raw playlist prompt | 25 | Free-form, similar scope to bead |
| Gate: #SMOKE_TEST | 10 | Run commands, check output |
| Gate: #COMPLETENESS_SCAN | 10 | Grep + read + report |
| Gate: #REVIEW | 10 | Read-only analysis |
| Gate: #REFACTOR | 30 | Multi-file changes with test runs |
| Gate: #DOCUMENT | 15 | Write docs, update index |
| Completion report | 5 | Write one file, commit |
| Project summary | 5 | Scan + write one file |
| Playlist creation | 5 | Analyse beads, output list |
| Playlist validation | 5 | Read-only audit |
| Retry (any type) | +5 | Add 5 turns to the original limit |

**Implementation:** Add a `TURNS_FOR_TYPE` associative array in config.sh. Each prompt builder sets a local `max_turns` before calling `invoke_claude`. The `@turns` annotation already overrides per-line.

**Why:** A 500-turn ceiling is functionally unlimited. Tight per-type limits act as circuit breakers — if Claude can't complete a smoke test in 10 turns, something is wrong and it should fail fast rather than spin. This directly reduces cost on runaway invocations.

**Sources:** research.md §3 ("The 500 max-turns setting is a non-functional safety net")

---

### 1.3 Fix the commit contradiction in playlist mode

**What:** Make the branch section template respect `AUTO_COMMIT`.

**Where:** `templates/branch_playlist.txt`, `lib/prompt.sh` (format_branch_instructions)

**Current state:** The branch section says "Commit directly on `<branch>`" while Rule 4 says "Do NOT commit." These appear in the same prompt when `AUTO_COMMIT=false` (the playlist default). Claude follows whichever it weights more heavily, producing inconsistent commit behaviour.

**Change `templates/branch_playlist.txt`:**
```
You are working on branch `{{BRANCH}}`. This is the single branch for this entire playlist session.
Do NOT create feature branches. Do NOT run `git checkout` to any other branch.
{{COMMIT_INSTRUCTION}}
```

Add `COMMIT_INSTRUCTION` substitution in `format_branch_instructions()`:
```bash
playlist:*)
    local branch="${branch_ctx#playlist:}"
    local commit_instr
    if [[ "$AUTO_COMMIT" == true ]]; then
        commit_instr="Commit directly on \`$branch\`. Merging is a separate manual step."
    else
        commit_instr="Leave changes staged or unstaged — the outer loop handles commits."
    fi
    render_template "$TEMPLATES_DIR/branch_playlist.txt" \
        "BRANCH=$branch" \
        "COMMIT_INSTRUCTION=$commit_instr"
    ;;
```

**Why:** Contradictory instructions within the same prompt are the most reliable way to get unpredictable behaviour from Claude. This is a direct bug in the current templates.

**Sources:** REVIEW.md §3.5 ("Fix Commit Contradiction"), §2.2 ("The commit rule contradicts across modes")

---

### 1.4 Reorder prompt sections for attention priority

**What:** Move the Orientation section before task details, and "When Done" above injected context.

**Where:** `templates/prompt_bead.txt`

**Current section order:**
```
Role → Task details → Prior context → Orientation → Branch → Rules → File map → Project summary → When done
```

**Recommended order:**
```
Role → Orientation → Task details → Prior context → Branch → Rules → When done → File map → Project summary
```

**Why:**
- Claude begins planning implementation while reading task details. By the time it hits Orientation ("check git state first"), it's already committed to an approach. Moving Orientation first means Claude's first action is always to orient.
- "When Done" (the `br close` command — arguably the most important instruction) currently sits at the very end, buried under 100+ lines of project summary. Moving it above the reference material sections ensures it gets primacy-adjacent attention.
- File map and project summary are reference material Claude consults as needed — they belong at the end.
- Research: Liu et al. (2024) measured 30%+ accuracy drop when answer-relevant content moved from edges to middle. Queries placed after context improve response quality by up to 30%.

**Sources:** REVIEW.md §3.1 ("Reorder for Attention Priority"), research.md §5 ("Instruction ordering matters")

---

### 1.5 Structured handoff replacing 200-word prose truncation

**What:** Replace the 200-word prose handoff with a structured JSON state file that the next invocation reads via its Read tool.

**Where:** `lib/task_outcome.sh` (capture_task_handoff), `lib/prompt_context.sh` (format_prior_task_context), new file `.ralph/handoff.json`

**Current state:** `capture_task_handoff()` extracts the last assistant text block, collapses whitespace, and truncates to 200 words. Complex beads modifying 8+ files cannot convey structural decisions, naming conventions, or partial implementations in 200 words.

**Change:** After a bead closes, write a structured handoff file:
```json
{
  "bead_id": "ralph-yys.2",
  "status": "closed",
  "files_changed": ["lib/auth.sh", "lib/session.sh", "tests/test_auth.sh"],
  "summary": "Implemented session token rotation with 15-minute expiry...",
  "key_decisions": ["Used HMAC-SHA256 for token signing", "Stored expiry in epoch seconds"],
  "tests_passing": true,
  "commit": "a1b2c3d"
}
```

The prompt instructs Claude to read the handoff file rather than embedding 200 words of prose:
```
## Prior Task Context
The previous bead (ralph-yys.2) closed successfully. Read `.ralph/handoff.json` for details of what changed. Verify against `git diff` / `git show HEAD` — the handoff is a CLAIM, not ground truth.
```

**Dynamic sizing as fallback:** If structured handoff is too complex to implement immediately, scale the word limit by files changed: `word_limit = min(500, 50 + (files_changed * 50))`.

**Why:** 
- JSON is preferred over prose for state transfer because "the model is less likely to inappropriately change JSON files compared to Markdown" (Anthropic research).
- Context passed as files on disk rather than embedded in the prompt string keeps the prompt lean while providing richer context.
- Structured data lets the next agent make targeted decisions (e.g., skip re-reading files it knows were changed).

**Sources:** research.md §4 ("The 200-word handoff sacrifices structure"), REVIEW.md §4.2 ("Dynamic Handoff Sizing"), §5.4

---

## Tier 2 — Medium Impact, Implement After Tier 1

These changes improve prompt quality, reduce cost, and prevent known failure modes. They build on the Tier 1 foundation.

### 2.1 Add XML tags to template assembly output

**What:** Wrap conditional sections with XML tags so they have unambiguous boundaries.

**Where:** All template files in `templates/`

**Example for `prompt_bead.txt`:**
```
You are executing a single task from a beads issue tracker as part of an automated ralph loop.

<orientation>
Before implementing, orient yourself...
</orientation>

<task>
ID: {{TASK_ID}}
{{DETAILS}}
</task>

<prior_context>
{{PRIOR_TASK_CONTEXT}}
</prior_context>

<branch>
{{BRANCH_SECTION}}
</branch>

<rules>
1. Implement this ONE task completely...
</rules>

<completion>
Close the issue with a reason...
</completion>

<reference>
{{FILE_MAP}}
{{PROJECT_SUMMARY}}
</reference>
```

**Why:** Claude was trained to recognise XML tags as a prompt organising mechanism. When conditional blocks are included or excluded, XML tags prevent sections from bleeding into each other. Without them, a missing `{{PRIOR_TASK_CONTEXT}}` collapses to an empty string, potentially concatenating the section above with the section below without any delimiter.

**Sources:** research.md §5 ("XML tags should structure the assembled prompt")

---

### 2.2 Restate negative rules as positive directives

**What:** Convert "Do NOT" rules into positive statements with explanations of *why*.

**Where:** `ralph-system-prompt.md` (for static rules moved in 1.1), remaining template rules

**Key conversions:**

| Current (negative) | Recommended (positive) |
|---|---|
| Do NOT touch .beads/ files — never commit, stash, or modify them. Do NOT run `br sync`. | All beads state changes go through `br` CLI commands only (`br close`, `br update`, `br create`). The `.beads/` directory and `br sync` are managed exclusively by the outer loop — your only interface is the `br` command. |
| Do NOT create feature branches. | Work only on the branch specified above. The outer loop manages branch creation and merging. |
| Do NOT run `git checkout` to any other branch. | Stay on the current branch for the entire invocation. Branch switching is handled by the outer loop between tasks. |
| Do not work on other tasks. | Complete this single task before exiting. One bead per invocation is the architectural contract. |

**Why:** Negative instructions are weakest when Claude is troubleshooting and grasping for solutions — the forbidden action competes against Claude's problem-solving drive. Positive framing with an explanation of *why* gives Claude a mental model that prevents creative workarounds. Use specific negatives only for targeting documented failure modes (e.g., "If you encounter a merge conflict, stop and report it — do not attempt resolution").

**Sources:** REVIEW.md §3.3 ("Negative Rules → Positive Restatements"), research.md §5 ("Positive framing versus specific negatives")

---

### 2.3 Add failure mode inoculation to each prompt type

**What:** Add 1–3 "vaccination" statements per prompt type that describe common failures before Claude encounters them.

**Where:** Each template file in `templates/`

**Examples:**

**Bead execution (`prompt_bead.txt`):**
```
## Common Pitfalls
You may be tempted to implement multiple features at once if you see related work nearby. Do not — complete this single bead fully before stopping.
You may encounter code that looks "wrong" but is unrelated to this task. Do not fix it — create a quick bead with `br q "..."` and move on.
```

**#REFACTOR gate:**
```
## Common Pitfalls
You may want to refactor more files than were changed in this session. Do not — scope to session changes only.
You may be tempted to add abstractions "for future flexibility." Do not — simplify existing code, don't add new patterns.
```

**#SMOKE_TEST gate:**
```
## Common Pitfalls
You may assume you know which endpoints were implemented. Do not assume — enumerate them from `git diff --stat` first, then test each.
```

**Why:** Claude Code's own system prompts use this technique extensively — describing the specific failure before the model encounters it. This "vaccinates" against known failure patterns and is more effective than post-hoc rules.

**Sources:** research.md §5 ("Failure mode inoculation is highly effective and underused"), REVIEW.md §2.5 ("#SMOKE_TEST is too terse")

---

### 2.4 Per-prompt-type timeouts

**What:** Replace the universal 10-minute timeout with calibrated values.

**Where:** `lib/config.sh` (new defaults), `lib/invoke.sh` (accept timeout parameter), prompt builders

**Recommended values:**

| Prompt Type | Timeout | Rationale |
|---|---|---|
| Bead task execution | 15 min | Complex multi-file work needs room |
| Raw playlist prompt | 15 min | Similar scope to bead |
| Gate: #SMOKE_TEST | 5 min | Run commands, report |
| Gate: #COMPLETENESS_SCAN | 5 min | Grep and report |
| Gate: #REVIEW | 5 min | Read-only analysis |
| Gate: #REFACTOR | 15 min | Multi-file changes |
| Gate: #DOCUMENT | 10 min | Write multiple doc files |
| Completion report | 3 min | Single file write |
| Project summary | 3 min | Scan + single file |
| Playlist creation | 3 min | Analyse + output list |
| Playlist validation | 3 min | Read-only audit |

**Implementation:** Pair with per-type max-turns from 1.2. When either limit is hit, record the failure type (timeout vs. turns-exhausted) in the handoff state so the next invocation knows the task was *interrupted*, not *failed*.

**Why:** A 10-minute timeout is too generous for a smoke test (delays failure detection) and too tight for complex refactoring (premature termination of productive work). Calibrated timeouts are the time-domain equivalent of calibrated max-turns.

**Sources:** research.md §7 ("The 10-minute timeout should be per-prompt-type")

---

### 2.5 Tool scoping per prompt type

**What:** Use `--allowedTools` and `--disallowedTools` to restrict tool access per invocation type.

**Where:** `lib/invoke.sh` (accept tool scope), prompt builders

**Recommended scoping:**

| Prompt Type | Disallowed Tools | Rationale |
|---|---|---|
| Gate: #REVIEW | Bash, Write, Edit, NotebookEdit | Reviews should be read-only |
| Gate: #SMOKE_TEST | Write, Edit, NotebookEdit | Tests should not modify source |
| Completion report | Bash (except git) | Report only writes one file |
| Playlist validation | Bash, Write, Edit | Pure analysis |
| Playlist creation | Bash, Write, Edit | Pure analysis, output goes to stdout |

**Implementation:** Add tool scope arrays per prompt type. Pass as CLI flags:
```bash
"${prefix[@]}" command claude \
    -p "$prompt" \
    --bare \
    --append-system-prompt-file "$RALPH_DIR/ralph-system-prompt.md" \
    --disallowedTools "${DISALLOWED_TOOLS[*]}" \
    ...
```

**Why:** Defence in depth. A #REVIEW gate that can't call Write/Edit physically cannot make unintended changes, regardless of what its prompt says. This is how Claude Code scopes its own Explore sub-agent — with an exhaustive deny-list, not a "read-only" instruction.

**Sources:** research.md §8 ("Tool scoping per prompt type"), REVIEW.md §2.5 ("#REVIEW — use --disallowedTools")

---

### 2.6 Outcome-based verification in the outer loop

**What:** After each invocation, verify outcomes mechanically rather than trusting Claude's prose claims.

**Where:** `lib/task_outcome.sh` (new verification step after `check_bead_status`), `lib/invoke.sh` (check `--output-format json` result fields)

**Verification checks by prompt type:**

| Prompt Type | Outer Loop Verification |
|---|---|
| Bead execution | `br show $tid --json` confirms status=closed; `git diff --stat HEAD~1` confirms files changed |
| #SMOKE_TEST | Parse stream-json for Bash tool calls; verify each had exit code 0 |
| #COMPLETENESS_SCAN | Verify no new TODO/FIXME lines added (compare grep counts before/after) |
| #REVIEW | Verify no files modified (`git diff --stat` is empty) |
| #REFACTOR | Run test suite; verify exit 0 |
| #DOCUMENT | Verify `docs/` directory modified (`git diff --name-only \| grep ^docs/`) |
| Completion report | Verify report file exists |

**Why:** The fundamental vulnerability in any autonomous agent system: agents can produce no-op implementations that pass quality checks without addressing the requirement. "Verify outcomes (build passes, tests pass, files exist, diffs are non-empty), not agent claims." Multiple production autonomous systems document this failure mode.

**Sources:** research.md §6 ("Quality gate templates need outcome-based verification"), REVIEW.md §2.7 ("Verification-Only prompt")

---

### 2.7 Error-type-aware escalation

**What:** Classify failure types before deciding whether to retry, escalate model, or decompose.

**Where:** `lib/invoke.sh` (escalate_model), `lib/invoke_retry.sh`

**Decision matrix:**

| Failure Type | Exit Code | Action |
|---|---|---|
| Timeout | 124 | Retry same model with reduced scope instruction |
| OOM/Kill | 137 | Retry same model with "produce shorter output" |
| Rate limit | 429 | Exponential backoff on same model, NOT escalation |
| Context overflow | 1 (with overflow marker) | Retry same model with truncated context |
| Quality failure (200 OK, wrong output) | 0 (bead still in_progress) | Escalate model |
| 2 consecutive timeouts | 124, 124 | Trigger decomposition prompt (see 3.1) |

**Current state:** All failures trigger model escalation regardless of type. This means a timeout (task too large) gets thrown at a more expensive model that will also time out — wasting 3x the budget on a task that should have been decomposed.

**Why:** Model escalation only helps when the bottleneck is reasoning capacity. Timeouts, rate limits, and OOM are infrastructure problems that a bigger model doesn't solve.

**Sources:** research.md §6 ("Model escalation strategy"), REVIEW.md §2.6 ("Model escalation is mechanically sound but semantically misaligned")

---

### 2.8 Add lightweight planning step to bead prompt

**What:** Insert a brief chain-of-thought instruction after Orientation.

**Where:** `templates/prompt_bead.txt`

```
## Plan
Before writing code, state your implementation approach in 2-3 sentences.
Include: which files you'll modify, what pattern you'll follow, and what you'll test.
```

**Why:** Lightweight chain-of-thought that improves decision quality at minimal token cost (~1 turn). Also creates a useful artifact in stream-json logs for debugging failed invocations — you can see *what Claude intended* before it started writing code.

**Sources:** REVIEW.md §3.6 ("Add Planning Step"), §2.8 ("Missing chain-of-thought encouragement")

---

### 2.9 Cumulative failure history across retries

**What:** Pass the full history of failures, not just the most recent one.

**Where:** `lib/invoke_retry.sh` (augment_prompt_with_failure_context), `templates/retry_context.txt`

**Current state:** On retry attempt 3, Claude only sees the most recent failure context. If attempt 1 timed out and attempt 2 hit context overflow, attempt 3 doesn't know both happened.

**Updated template:**
```
## RETRY CONTEXT (attempt {{ATTEMPT}}/{{MAX_RETRIES}})

### Failure History
{{FAILURE_HISTORY}}

### Most Recent Failure
* Exit code: {{EXIT_CODE}}
* Diagnosis: {{DIAGNOSIS}}

### Last output before failure
{{LAST_OUTPUT}}

### Pattern Analysis
If multiple failures share a root cause (e.g., task too large for time budget),
consider decomposing: create 2-3 sub-beads with `br create` and release
the parent with `br update {{TASK_ID}} --status open`.
```

**Implementation:** Accumulate `FAILURE_HISTORY` across retries as a simple list:
```
Attempt 1: Timeout (exit 124) — haiku
Attempt 2: Context overflow (exit 1) — sonnet
```

**Why:** Cumulative history enables Claude to recognise systemic issues ("this task is fundamentally too large") rather than just responding to the most recent symptom.

**Sources:** REVIEW.md §3.4 ("Retry Context — Cumulative Failure History"), §2.6

---

## Tier 3 — Lower Impact, Implement When Convenient

These are refinements, new prompt types, and guard rails that harden the system. None are urgent.

### 3.1 Decomposition prompt type (Type 9)

**What:** When a bead fails twice consecutively, trigger a special prompt that breaks it into sub-beads instead of retrying.

**Where:** New template `templates/prompt_decompose.txt`, `lib/invoke.sh` (failure routing)

**Template:**
```
You are decomposing a task that has failed twice in the ralph autonomous loop.

<task>
ID: {{TASK_ID}}
{{DETAILS}}
</task>

<failure_history>
{{FAILURE_HISTORY}}
</failure_history>

<instructions>
1. Analyse why this task is too large for a single invocation.
2. Break it into 2-4 sub-tasks, each completable in under 10 minutes.
3. Create each sub-task: `br create --title "..." --description "..." --parent {{TASK_ID}}`
4. Release the parent: `br update {{TASK_ID}} --status open`
5. The outer loop will pick up the sub-tasks in the next cycle.
</instructions>

<rules>
Each sub-task must be independently testable.
Sub-tasks should be ordered by dependency (foundational first).
Do NOT implement anything — only decompose and create beads.
</rules>
```

**Why:** Currently, a task that's too large cycles through 3 retries with escalating models, consuming 3x budget on work that should have been decomposed after the first failure. This prompt type turns timeout-loop failures into productive decomposition.

**Sources:** REVIEW.md §4.5 ("Add a Decomposition Prompt"), §5.5 ("Model Escalation Cost Spiral")

---

### 3.2 Gate scope caps

**What:** Limit how many issues a gate can create and how many files it can modify.

**Where:** All gate templates in `templates/gate_*.txt`

**Add to each gate:**
```
## Scope Limit
If this analysis identifies more than 10 distinct issues, prioritise the top 5 by severity
and create beads only for those. List the remainder in your output for future reference.
```

**For #REFACTOR specifically:**
```
If more than 10 files are modified in the session, focus on the top 5 by complexity.
If you cannot complete all planned refactoring within this invocation, revert uncommitted
changes and create beads for the remaining work.
```

**Why:** The #REFACTOR gate is the riskiest prompt in the system — it can both modify the codebase extensively and alter the execution plan via bead creation. A scope cap prevents 15-bead creation events that distort the playlist. Combined with tool scoping (2.5), this provides defence in depth.

**Sources:** REVIEW.md §2.5, §5.1 ("Gate-Induced Codebase Corruption")

---

### 3.3 Conditional orientation depth

**What:** Use a shortened orientation for sequential playlist beads where prior context exists and the previous bead closed successfully.

**Where:** `templates/prompt_bead.txt` (new variant), `lib/prompt.sh` (select variant)

**Quick orientation:**
```
## Orientation (Quick)
The previous bead closed successfully. Run `git diff --stat` to confirm the scope
of recent changes matches the Prior Task Context above. If it matches, proceed to
implementation. If it doesn't, fall back to full orientation (git diff, git show HEAD).
```

**Full orientation:** Current version, used when there is no prior context or the previous bead did not close.

**Why:** Sequential playlist beads where the prior task context is accurate burn 2–4 turns on verification that rarely catches discrepancies. This saves meaningful turn budget on the happy path while preserving full verification when needed.

**Sources:** REVIEW.md §4.3 ("Conditional Orientation Depth"), §1 finding #3

---

### 3.4 Calibrate the "blocked" definition

**What:** Add examples of blocked vs. not-blocked to the bead prompt.

**Where:** `templates/prompt_bead.txt` (Rules section or system prompt file)

**Current:**
```
5. If you are blocked and cannot complete the task, say so clearly.
```

**Recommended:**
```
5. If you are BLOCKED (missing dependency not yet implemented, external service unavailable,
   or task description is ambiguous/contradictory), release the bead with:
     br update {{TASK_ID}} --status open
   You are NOT blocked just because the task is difficult or requires significant work —
   attempt implementation first.
```

**Why:** Without calibration, Claude may interpret "blocked" broadly ("this is hard and I'm confused") and bail on difficult but achievable tasks. The examples set a threshold.

**Sources:** REVIEW.md §3.2 ("Blocked Definition")

---

### 3.5 Add `--max-budget-usd` per invocation

**What:** Use Claude Code's `--max-budget-usd` flag as a per-invocation cost ceiling.

**Where:** `lib/invoke.sh` (_invoke_claude_once), `lib/config.sh` (defaults per type)

**Recommended values:**

| Prompt Type | Budget Ceiling |
|---|---|
| Bead execution | $2.00 |
| Raw prompt | $2.00 |
| Gate (any) | $1.00 |
| Report/summary | $0.50 |
| Playlist creation/validation | $0.50 |

**Why:** Defence in depth alongside max-turns and timeouts. A runaway agent that somehow evades turn limits (e.g., very expensive single tool calls) is still bounded by cost.

**Sources:** research.md §2 ("--max-budget-usd"), §3 ("Pair --max-turns with --max-budget-usd")

---

### 3.6 Project summary staleness during long playlists

**What:** Regenerate or append to the project summary after every N beads in a long playlist.

**Where:** `lib/project_summary.sh`, `lib/playlist.sh` (after bead completion)

**Current state:** The summary is generated once at session start with a 24h/10-commit staleness check. A 20-bead playlist running in 2 hours means bead 18 reads a summary describing the codebase as it was 20 beads ago.

**Options (in order of simplicity):**
1. **Append a diff summary** — after every 5 beads, append `git diff --stat <summary-commit>..HEAD` to the project summary file.
2. **Regenerate** — trigger full regeneration every 10 beads (cheap with haiku).
3. **Drop it** — if the file map and prior task context are sufficient, the project summary may not be worth its ~100-line token cost. Test completion rates with and without it.

**Sources:** REVIEW.md §2.4, §5.3 ("Project Summary Staleness")

---

### 3.7 Remove emphasis inflation from prompts

**What:** Audit all templates for MUST, ALWAYS, CRITICAL, ALL CAPS markers and replace with clear conditional logic.

**Where:** All template files in `templates/`, `ralph-system-prompt.md`

**Why:** Claude 4.x models evaluate logical necessity, not emphasis markers. Anthropic's documentation states: "Where you might have said 'CRITICAL: You MUST use this tool when...', you can use more normal prompting like 'Use this tool when...'" If every instruction is marked critical, the model treats none as truly critical.

**Sources:** research.md §5 ("Claude 4.x models evaluate logical necessity")

---

### 3.8 Scope discipline rule (prevent drive-by refactoring)

**What:** Add an explicit constraint against modifying files outside task scope.

**Where:** `ralph-system-prompt.md` (static rule)

```
Only modify files directly required by the current task's acceptance criteria.
If you encounter unrelated issues during implementation, capture them with
`br q "..."` and move on — do not fix them inline.
```

**Why:** Without this constraint, a refactoring-minded Claude might "improve" unrelated code it encounters during grep operations. The `br q` escape hatch gives it a productive way to handle discovered issues without scope creep.

**Sources:** REVIEW.md §2.3 ("Missing: explicit instruction to not modify files outside task scope")

---

### 3.9 Use `--output-format json` for structured output types

**What:** For prompt types that produce structured output (completion report, playlist creation), use `--output-format json` with `--json-schema` to get deterministic parsing.

**Where:** `lib/invoke.sh` (per-invocation output format), `lib/playlist_init.sh` (playlist creation)

**Why:** Ralph's outer loop currently parses free-text output via `extract_playlist_from_log()` — a fragile jq filter looking for code blocks in stream-json. JSON output with a schema would make parsing deterministic and eliminate the class of bugs where Claude's output format doesn't match the parser's expectations.

**Sources:** research.md §2 ("--output-format json combined with --json-schema")

---

## Implementation Order

The recommended implementation sequence, accounting for dependencies:

1. **1.3** Fix commit contradiction — smallest change, immediate bug fix
2. **1.4** Reorder prompt sections — template-only change, no code
3. **1.1** `--bare` + system prompt file — foundation for all other changes
4. **1.2** Per-type max-turns — requires invoke.sh changes from 1.1
5. **2.1** XML tags — template-only, pairs with 1.4
6. **2.2** Positive rule restatements — pairs with 1.1 (rules moving to system prompt)
7. **2.3** Failure mode inoculation — template-only
8. **2.8** Planning step — template-only
9. **1.5** Structured handoff — larger change, builds on all above
10. **2.4** Per-type timeouts — mirrors 1.2 implementation
11. **2.5** Tool scoping — extends invoke.sh from 1.1
12. **2.7** Error-type-aware escalation — extends invoke.sh retry logic
13. **2.9** Cumulative failure history — extends retry logic from 2.7
14. **2.6** Outcome verification — new outer loop capability
15. **Tier 3** items — in any order as time permits

---

## Changes NOT Recommended

The external reviews suggested several changes that I don't recommend based on hands-on experience with the system:

**Multi-turn conversations:** Both reviews confirmed the single-prompt model is correct. Don't change it. The simplicity and debuggability (every invocation is a single inspectable string) outweigh any theoretical benefits of multi-turn.

**`--fallback-model` flag:** This handles infrastructure-level fallback automatically, but ralph's quality-based escalation needs to remain in the outer loop. Using both would create confusing interactions. Keep escalation in `invoke.sh`.

**Verification-only prompt type:** research.md suggested a dedicated verification prompt that re-reads specs after completion. This is overkill for ralph — the circuit breaker + `br close --reason` + human verification workflow already provides three layers of completion checking. A fourth would add invocation cost without proportionate value.

**Initialiser prompt type:** research.md suggested a first-session agent for setup. Ralph's `--init` + project summary generation already covers this. Adding another prompt type for what amounts to `mkdir -p` and git operations would over-engineer the startup path.

**Recovery prompt type:** REVIEW.md suggested a dedicated prompt for dirty-state recovery. The Orientation section already handles this — it checks for dirty working trees and uncommitted changes. A dedicated recovery prompt would only fire in edge cases that the current system handles adequately.
