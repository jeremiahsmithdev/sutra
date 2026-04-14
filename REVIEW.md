Jeremiah, this is a meaty document — I've got everything I need right here to do the full review. Let me work through all nine categories systematically.

---

## 1. Executive Summary — Top 5 Highest-Impact Findings

**1. Critical information is buried at the bottom of prompts.** The `## When Done` section containing the `br close` command — arguably the single most important behavioral instruction — sits at the very end of the bead prompt. Claude's attention is strongest at the beginning and end of context, but the end competes with the `## Project Summary` (up to 100 lines of injected content). The close/release instructions should be elevated or duplicated.

**2. Heavy reliance on negative instructions.** Rules like "Do NOT touch .beads/ files," "Do NOT run `br sync`," "Do NOT create feature branches" are scattered across templates. Negative constraints are weaker behavioral anchors with Claude than positive directives stating what *to* do. Several of these would be more reliably enforced by moving them to a CLAUDE.md file that persists across invocations.

**3. The Orientation section is well-designed but creates a token-expensive mandatory preamble.** Every bead invocation forces Claude through `git status` → `git diff` / `git log` → `git show HEAD` before any implementation. For sequential playlist beads where the prior task context is accurate, this can burn 2-4 turns on verification that rarely catches discrepancies. A conditional orientation (full verification only when prior context is absent or flagged) would save meaningful turn budget.

**4. The 200-word cross-bead handoff is insufficient for complex multi-step work.** When an agent modifies 8 files across 3 architectural layers, 200 words cannot convey the structural decisions, naming conventions chosen, or partial implementations left in place. The trust model (treat as "CLAIM") is sound, but the truncation limit means Claude often can't even enumerate what changed, let alone explain *why*.

**5. Gate templates conflate observation with action, creating scope creep risk.** The `#REFACTOR` gate is a 90+ line prompt that instructs Claude to analyze, plan, *and* execute a full refactoring pass — all within a single invocation. Combined with the self-healing "create beads and inject into playlist" instruction, a single gate invocation can both modify the codebase extensively and alter the execution plan. This is the riskiest prompt in the system.

---

## 2. Detailed Analysis

### 2.1 Prompt Structure and Clarity

**Section ordering in the bead prompt is suboptimal.** The current order is: role statement → task details → orientation → branch → rules → file map → project summary → when done. The problem is that task details (the *what*) appear before orientation (the *how to start*), which is logical for a human reader but not optimal for Claude's execution. Claude will begin planning implementation while reading the task, then encounter orientation instructions that tell it to stop and check git state first. Consider moving Orientation immediately after the role statement and before task details, so Claude's first action is always to orient.

**The role statements are effective but inconsistent.** The bead prompt opens with "You are executing a single task from a beads issue tracker as part of an automated ralph loop." The raw prompt opens with "You are performing a maintenance task between automated bead implementations in the ralph autonomous loop." Both are clear, but the word "maintenance" in the raw prompt subtly underweights the importance of prompt-type tasks. Some raw prompts carry gate expansions that are as complex as any bead task.

**Rule 7 (prefer Read/Grep/Glob over Agent sub-tasks) is well-placed and actionable.** This is a good cost-optimization instruction. However, it appears in both bead and raw templates with slightly different wording — in the raw prompt, it says "not described in this task or the project context" while the bead prompt says the same. Consolidating the exact wording avoids drift.

**The `{{DETAILS}}` format is clean but lacks field delimiters.** When a bead has a long description followed by notes followed by acceptance criteria, there's no visual separator. Claude may conflate adjacent fields. Adding markdown headers or horizontal rules between fields would improve parsing.

### 2.2 Cross-Prompt Consistency

**Rule numbering is inconsistent.** The bead prompt has 7 rules (with rule 4 being the commit rule and rule 5 about being blocked). The raw prompt has 7 different rules with different numbering. The report prompt has 4 rules. When Claude encounters "Rule 3" across different invocation types, it means different things. This isn't a functional problem — each invocation is independent — but it suggests the rule sets haven't been harmonized.

**The commit rule contradicts across modes without clear signaling.** In standard mode, rule 4 says "Commit your changes." In playlist mode, rule 4 says "Do NOT commit." The branch section in playlist mode says "Commit directly on `<playlist-branch>`." This is a direct contradiction within the same prompt when `AUTO_COMMIT=false` in playlist mode. The branch section should be conditional on `AUTO_COMMIT` as well, or the branch section should say "Work on" rather than "Commit directly on."

**The trust model is coherent.** The Prior Task Context section explicitly labels the handoff as a "CLAIM" and the Orientation section instructs verification against git state. This is well-designed. The only gap is that the raw prompt (Type 2) includes `{{PRIOR_TASK_CONTEXT}}` but lacks the Orientation section with its git verification instructions, meaning a raw prompt following a bead will carry the "CLAIM" label but no instructions on how to verify it.

### 2.3 Instruction Effectiveness

**The Orientation section is the strongest instruction in the system.** It gives Claude a concrete, ordered procedure (check git state → read diff → verify prior context) before any implementation. This is effective because it's positive ("do this first"), sequential, and grounded in tool calls Claude can execute immediately. It's the gold standard for the other instructions to aspire to.

**"Do NOT touch .beads/ files" is likely to be ignored under pressure.** Negative instructions are weakest when Claude is troubleshooting a failure and grasping for solutions. If a bead's status is wrong and Claude thinks updating it directly would fix the problem, the negative instruction competes against Claude's problem-solving drive. A stronger approach would be to explain *why* (the outer loop manages state; direct edits will corrupt sync) and add it to CLAUDE.md as a project-level constraint.

**The "If you are blocked" instruction is good but incomplete.** It tells Claude to release the bead with `br update --status open`, but doesn't specify *what constitutes blocked*. Claude may interpret "blocked" narrowly (missing dependency) or broadly (this is hard and I'm confused). Adding 2-3 examples of blocked vs. not-blocked scenarios would calibrate the threshold.

**Missing: explicit instruction to not modify files outside the task scope.** The rules say "Implement this ONE task completely. Do not work on other tasks." But there's no constraint against modifying files that aren't related to the task. A refactoring-minded Claude might "improve" unrelated code it encounters during grep operations. Consider adding: "Only modify files directly required by this task's acceptance criteria."

### 2.4 Context Efficiency

**The Project Summary (100 lines) is high-value for early beads but degrades.** After 10+ beads have modified the codebase, the summary generated at session start describes a state that may have significantly changed. The 24-hour / 10-commit staleness check is a reasonable heuristic, but in a fast playlist session, 10 beads can complete in under an hour. Consider regenerating or appending a diff summary after every N beads.

**The File Map is underspecified.** Extracting purpose from the first comment line of each file is clever but fragile. Many files don't have purpose comments. The file map should fall back to a heuristic description (filename-based) when no comment is found, or the system should warn when a `CONTEXT_FILES` entry produces no description.

**Token budget is not tracked or managed.** With a 100-line project summary, a file map, prior task context (200 words), task details (variable length), and the template itself, prompts can exceed 2000 tokens before Claude does anything. For haiku with its smaller context, this ratio of instruction-to-action is worth monitoring. Consider logging prompt token counts and establishing a budget ceiling per model.

### 2.5 Gate Template Quality

**`#SMOKE_TEST` is too terse.** "curl each endpoint implemented in the last batch of beads" assumes Claude can identify which endpoints were implemented, but it receives no explicit list. It must infer this from git history or prior task context, which may be incomplete. The gate would benefit from instructing Claude to first enumerate endpoints from the diff, then test each.

**`#REFACTOR` is excellent in structure but dangerously ambitious.** The three-phase process (Analyze → Plan → Execute) is well-designed. The SCRATCHPAD.md pattern is good for traceability. But the scope is unbounded — "all modified files in the session" could be dozens of files after a long playlist. Combined with 500 max turns and a 10-minute timeout, Claude may run out of budget mid-refactor, leaving the codebase in a partially refactored state. Consider adding a scope cap: "If more than N files are modified, focus on the top 5 by complexity."

**`#DOCUMENT` is the most complete gate template.** The INDEX.md structure, orphan detection, ADR criteria, and frontmatter template give Claude everything it needs. This is the model for what the other gates should aspire to.

**Self-healing instructions are clear but need guardrails.** "Create beads (type=bug only)" is a good constraint — it prevents gates from spawning feature work. The injection cap is a smart safety valve. However, there's no instruction limiting the *severity* of bugs that should be beads vs. fixed inline. A gate might create a bead for a trivial typo, wasting a future invocation. Consider: "Only create beads for issues that require more than 5 minutes of focused work."

### 2.6 Failure Recovery

**The retry context injection is well-structured.** Providing the exit code, diagnosis, and last output gives Claude concrete information to adapt. The adaptation guidance (timeout → smaller steps, context overflow → shorter output) is actionable.

**Missing: cumulative failure context.** On retry attempt 3, Claude only sees the context from the most recent failure, not the pattern across all failures. If attempt 1 timed out and attempt 2 hit context overflow, attempt 3 should know both happened — this suggests the task itself may be too large, not just the approach.

**Model escalation is mechanically sound but semantically misaligned.** Haiku → Sonnet escalation on timeout doesn't address the root cause (task too large for the time budget). A smarter escalation would be: timeout → retry with same model but reduced scope instruction; tool error → escalate model; context overflow → retry with same model but "produce shorter output" instruction. The model escalation should be tied to the *type* of failure, not just the *occurrence*.

### 2.7 Missing Prompt Types

**No "Decomposition" prompt for oversized tasks.** When a bead is too large for a single invocation (repeatedly timing out or hitting context limits), there's no mechanism to break it into sub-beads. A decomposition prompt could instruct Claude to analyze the task, create 2-3 child beads with `br create`, and release the parent.

**No "Verification-Only" prompt.** After a bead closes, the system trusts Claude's `br close --reason` output. A lightweight verification prompt could re-read the acceptance criteria and run the specified tests without any implementation authority, providing a second opinion.

**No "Recovery" prompt for dirty-state situations.** If a previous invocation crashed mid-implementation (timeout with uncommitted changes), the next invocation gets the Orientation section, but there's no explicit instruction for how to handle a half-done state. A recovery prompt could instruct Claude to assess the partial work, decide whether to continue or revert, and then proceed.

### 2.8 Anti-Patterns

**Negative instruction clustering.** Rules 1, 4 (sometimes), 5, 6, and 7 across various prompts contain "Do NOT" phrasing. Claude is more reliably constrained by positive restatements. For example, "Do NOT touch .beads/ files" → "All beads state changes happen through `br` commands only. The outer loop manages `.beads/` files directly."

**Implicit assumption about git proficiency.** The prompts assume Claude will correctly interpret complex git states (detached HEAD, merge conflicts, dirty index vs. working tree). There's no guidance for edge cases like "if you encounter a merge conflict" or "if HEAD is detached." These states can occur if a previous invocation crashed, and Claude's response without guidance is unpredictable.

**Missing chain-of-thought encouragement.** The prompts don't ask Claude to reason about its approach before implementing. Adding a brief "Before implementing, state your plan in 2-3 sentences" instruction after the Orientation section would improve decision quality, especially for complex beads, at minimal token cost.

**Numbered rules with a gap.** The bead prompt has rules 1, 2, 3, `{{COMMIT_RULE}}` (which renders as "4."), 5, 6, 7. But the commit rule template literally starts with "4." — so the numbering is hard-coded in the template. If the commit rule is removed or the list is reordered, numbering breaks. Use unnumbered bullets or generate numbers dynamically.

### 2.9 Architectural Observations

**CLAUDE.md is dramatically underutilized.** Claude Code reads CLAUDE.md automatically on every invocation. Static rules that never change between invocations — "don't touch .beads/", "prefer Read/Grep/Glob", "don't run br sync", branch naming conventions, commit message format — belong in CLAUDE.md, not in the per-invocation prompt. This would reduce prompt size by roughly 20-30% and ensure consistency without template maintenance.

Moving to CLAUDE.md:
- Rule 6 (don't touch .beads/)
- Rule 7 (prefer direct tools over Agent)
- Branch naming conventions
- Commit message format expectations
- The "Do NOT run `br sync`" instruction
- File map (if it changes rarely)

**The single-prompt model is appropriate for this architecture.** Multi-turn would introduce state management complexity in the bash outer loop without clear benefit. The current model's strength is its simplicity and debuggability — every invocation's full context is a single string you can inspect. Don't change this.

**The 200-word handoff limit should scale with task complexity.** Simple tasks (rename a function, add a config option) need 50 words. Complex tasks (implement an auth layer across 8 files) need 500. Consider sizing the handoff based on the number of files modified: `word_limit = min(500, 50 + (files_changed * 50))`.

---

## 3. Specific Rewrites

### 3.1 Bead Prompt — Reorder for Attention Priority

**Before (current section order):**
```
Role statement → Task details → Prior context → Orientation → Branch → Rules → File map → Project summary → When done
```

**After (recommended):**
```
Role statement → Orientation → Task details → Prior context → Branch → Rules → When done → File map → Project summary
```

**Rationale:** Orientation should be the first action Claude takes, before it reads task details and starts planning. "When Done" moves above the injected context sections so it doesn't get buried under 100+ lines of project summary. File map and project summary are reference material — they belong at the end where Claude can consult them as needed.

### 3.2 Blocked Definition

**Before:**
```
5. If you are blocked and cannot complete the task, say so clearly.
```

**After:**
```
5. If you are BLOCKED (missing dependency not yet implemented, external service unavailable, or task description is ambiguous/contradictory), release the bead. You are NOT blocked just because the task is difficult or requires significant work — attempt implementation first.
```

**Rationale:** Calibrates Claude's threshold for declaring itself blocked, preventing premature bail-out on hard tasks while preserving the escape hatch for genuine blockers.

### 3.3 Negative Rules → Positive Restatements

**Before:**
```
6. Do NOT touch .beads/ files — never commit, stash, or modify them. Do NOT run `br sync`. The outer loop handles beads state automatically.
```

**After:**
```
6. All beads state changes go through `br` CLI commands only (`br close`, `br update`, `br create`). The `.beads/` directory and `br sync` are managed exclusively by the outer loop — your only interface is the `br` command.
```

**Rationale:** Positive framing ("your interface is `br`") is a stronger behavioral anchor than negative framing ("don't touch X"). The explanation of *why* (outer loop manages it) gives Claude a mental model that prevents creative workarounds.

### 3.4 Retry Context — Cumulative Failure History

**Before:**
```
## RETRY CONTEXT (attempt {{ATTEMPT}}/{{MAX_RETRIES}})
The previous attempt FAILED. Here is what happened:
* Exit code: {{EXIT_CODE}}
* Diagnosis: {{DIAGNOSIS}}
```

**After:**
```
## RETRY CONTEXT (attempt {{ATTEMPT}}/{{MAX_RETRIES}})

### Failure History
{{FAILURE_HISTORY}}

### Most Recent Failure
* Exit code: {{EXIT_CODE}}
* Diagnosis: {{DIAGNOSIS}}

### Pattern Analysis
If multiple failures share a root cause (e.g., task too large for time budget), consider decomposing the task: create 2-3 sub-beads with `br create` and release the parent with `br update {{TASK_ID}} --status open`.
```

Where `{{FAILURE_HISTORY}}` accumulates across retries:
```
Attempt 1: Timeout (exit 124) — haiku
Attempt 2: Context overflow (exit 1) — sonnet
```

**Rationale:** Cumulative history enables Claude to recognize systemic issues (this task is fundamentally too large) rather than just responding to the most recent symptom.

### 3.5 Playlist Branch Section — Fix Commit Contradiction

**Before:**
```
You are working on branch `<playlist-branch>`. This is the single branch for this entire playlist session.
Do NOT create feature branches. Do NOT run `git checkout` to any other branch.
Commit directly on `<playlist-branch>`. Merging is a separate manual step.
```

**After (when AUTO_COMMIT=false):**
```
You are working on branch `<playlist-branch>`. This is the single branch for this entire playlist session.
Do NOT create feature branches. Do NOT run `git checkout` to any other branch.
Leave changes staged or unstaged — the outer loop handles commits. Do NOT run `git commit`.
```

**Rationale:** The current version says "Commit directly" in the branch section while rule 4 says "Do NOT commit." This is a direct contradiction within the same prompt. The branch section should respect the AUTO_COMMIT setting.

### 3.6 Add Planning Step to Bead Prompt

**Insert after Orientation, before implementation:**

```
## Plan
Before writing code, state your implementation approach in 2-3 sentences. Include:
which files you'll modify, what pattern or approach you'll follow, and what you'll test.
```

**Rationale:** Lightweight chain-of-thought that improves decision quality without significant token cost. Also creates a useful artifact in the stream-json log for debugging failed invocations.

---

## 4. Architectural Recommendations

### 4.1 Migrate Static Rules to CLAUDE.md

Create a `.ralph/CLAUDE.md` (or project-root `CLAUDE.md`) containing all rules that are invariant across invocation types:

```markdown
# Ralph Autonomous Loop — Agent Rules

## Beads State Management
All beads state changes go through `br` CLI commands only. Never modify `.beads/` files directly. Never run `br sync`.

## Tool Preferences
Prefer Read, Grep, and Glob tools for file operations. Only use Agent sub-tasks for exploring unfamiliar code not described in the task prompt.

## Scope Discipline
Only modify files directly required by the current task. Do not refactor, improve, or "fix" unrelated code encountered during implementation.

## Git Hygiene
Never create feature branches unless explicitly instructed. Follow conventional commit message format.
If you encounter merge conflicts, stop and report them — do not attempt resolution.
If HEAD is detached, run `git checkout <expected-branch>` before any work.
```

This removes approximately 4-6 rules from every bead and raw prompt, saving ~150-200 tokens per invocation and eliminating cross-template drift.

### 4.2 Dynamic Handoff Sizing

Replace the fixed 200-word truncation with:

```bash
files_changed=$(git diff --name-only HEAD~1 | wc -l)
word_limit=$((50 + files_changed * 50))
word_limit=$((word_limit > 500 ? 500 : word_limit))
truncate_to_word_limit "$text" "$word_limit"
```

### 4.3 Conditional Orientation Depth

Add a `--quick-orient` mode for sequential playlist beads where prior task context exists and the previous bead closed successfully:

```
## Orientation (Quick)
The previous bead closed successfully. Run `git diff --stat` to confirm the scope of recent changes matches the Prior Task Context above. If it matches, proceed to implementation. If it doesn't match, fall back to full orientation (git diff, git show HEAD).
```

This saves 2-3 turns on the happy path while preserving full verification when needed.

### 4.4 Gate Scope Caps

Add to all gate templates:

```
## Scope Limit
If this analysis identifies more than 10 distinct issues, prioritize the top 5 by severity and create beads only for those. List the remainder in the commit message for future reference.
```

This prevents gate invocations from spiraling into 15-bead creation events that distort the playlist.

### 4.5 Add a Decomposition Prompt (Type 9)

Triggered after 2 consecutive failures on the same bead:

```
You are decomposing a task that has failed twice in the ralph autonomous loop.

## Failed Task
ID: {{TASK_ID}}
{{DETAILS}}

## Failure History
{{FAILURE_HISTORY}}

## Instructions
1. Analyze why this task is too large for a single invocation.
2. Break it into 2-4 sub-tasks, each completable in under 10 minutes.
3. Create each sub-task: `br create --title "..." --description "..." --parent {{TASK_ID}}`
4. Release the parent: `br update {{TASK_ID}} --status open`
5. The outer loop will pick up the sub-tasks in the next cycle.

## Rules
- Each sub-task must be independently testable.
- Sub-tasks should be ordered by dependency (foundational first).
- Do NOT implement anything — only decompose and create beads.
```

---

## 5. Risk Assessment

### 5.1 Highest Risk: Gate-Induced Codebase Corruption

**Scenario:** The `#REFACTOR` gate modifies 15 files, times out at 80% completion, and leaves the codebase in an inconsistent state (some files refactored, others still referencing old patterns). The next bead inherits this broken state.

**Mitigation:** Add a pre-gate `git stash` or checkpoint commit that the outer loop can revert to if the gate fails. Gate prompts should include: "If you cannot complete all planned refactoring within this invocation, revert uncommitted changes and create beads for the remaining work."

### 5.2 Medium Risk: Commit Contradiction in Playlist Mode

**Scenario:** Branch section says "Commit directly," commit rule says "Do NOT commit." Claude follows whichever instruction it weighted more heavily, leading to inconsistent commit behavior across playlist beads.

**Mitigation:** Apply the rewrite from Section 3.5. Both sections must agree.

### 5.3 Medium Risk: Project Summary Staleness

**Scenario:** A 20-bead playlist runs in 2 hours. The project summary generated at session start describes the codebase as it was 20 beads ago. Bead 18 reads the summary and makes incorrect assumptions about directory structure or patterns that were changed by bead 5.

**Mitigation:** Regenerate the project summary every 10 beads or after any bead that creates new directories. Alternatively, append a "changes since summary generation" section derived from `git diff --stat` against the summary's recorded commit hash.

### 5.4 Lower Risk: Handoff Truncation Information Loss

**Scenario:** A complex bead modifies 12 files across 3 layers. The 200-word handoff captures only the surface-level summary ("implemented auth middleware"), losing details about naming conventions, configuration choices, and partial implementations that the next bead needs.

**Mitigation:** Dynamic handoff sizing (Section 4.2) and/or structured handoff format requiring enumeration of files changed and key decisions made.

### 5.5 Lower Risk: Model Escalation Cost Spiral

**Scenario:** A task that's genuinely too large for any model cycles through haiku (timeout) → sonnet (timeout) → opus (timeout), consuming 3× the budget on a task that should have been decomposed after the first failure.

**Mitigation:** After 2 consecutive timeouts, trigger decomposition (Section 4.5) instead of escalating to opus. Reserve model escalation for non-timeout failures where the model's reasoning capacity is the bottleneck.

---

That covers all nine analysis categories. The system is well-designed overall — the Orientation section, the trust model for cross-bead handoffs, the gate injection cap, and the deterministic outer loop are all strong architectural choices. The highest-leverage changes are: migrating static rules to CLAUDE.md, fixing the commit contradiction, reordering prompt sections for attention priority, and adding the decomposition prompt type. Happy to dive deeper into any of these or draft the actual CLAUDE.md file.
