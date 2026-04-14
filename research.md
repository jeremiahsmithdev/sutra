# Prompt engineering review of ralph's autonomous coding harness

Ralph's single-prompt-per-invocation architecture is fundamentally sound and aligns with Anthropic's own recommended pattern for long-running agents — but **several critical CLI capabilities go unused, and prompt assembly patterns diverge from current best practices in ways that likely degrade performance**. The most impactful issues are the absence of `--append-system-prompt` (which means every invocation discards Claude Code's ~27K-token built-in system prompt), a 500 max-turns setting that provides essentially no safety net, and a 200-word prose handoff that loses structured state. Addressing these would likely yield immediate, measurable improvements in task completion rates and cost efficiency.

This review is grounded in Anthropic's official documentation (April 2026), Claude Code's current CLI reference, Anthropic's published harness engineering research, and cross-system analysis of SWE-Agent, OpenHands, Aider, and Devin architectures.

---

## Ralph's architecture validates the "fresh context per task" pattern

Anthropic's own engineering team arrived at the same core architecture ralph uses: a deterministic outer loop feeding tasks to Claude one invocation at a time, with each invocation starting from a clean context window. Their published research on effective harnesses for long-running agents describes a "coding agent" pattern where each session reads structured state files (progress.txt, feature_list.json, git history), works on a single feature, commits, updates progress, and exits. This is architecturally equivalent to ralph's bead execution model.

The research validation is strong. SWE-Agent (Princeton/Stanford) uses a similar loop with a `forward()` method that prompts the model, parses actions, and executes — one cycle at a time. Mini-SWE-Agent achieves **65% on SWE-bench Verified in ~100 lines of Python** using this pattern. OpenHands uses ReAct-style decision loops with explicit step-oriented planning. The consensus across all major autonomous coding systems is that **clean context windows with structured file-based state handoff outperform continuous sessions**, particularly because compaction is lossy and context anxiety degrades performance as windows fill.

Ralph's template-based prompt assembly with `{{KEY}}` substitution also mirrors industry practice. Claude Code itself assembles its system prompt from approximately 80 modular sections with conditional inclusion logic. The pattern is sound — the execution details need refinement.

---

## Three critical CLI capabilities ralph should adopt immediately

**`--append-system-prompt` is the single highest-leverage change.** Ralph currently passes everything through `claude -p` as a user message, which means Claude Code's entire built-in system prompt — including 24 tool definitions, permission logic, sub-agent spawning, context management, and coding-specific behavioral guidelines — is loaded by default but ralph has no ability to add stable behavioral rules to the system prompt layer. The `--append-system-prompt` flag adds custom instructions to Claude's existing system prompt while preserving all built-in capabilities. This is explicitly Anthropic's recommended approach: "For most use cases, use an append flag to preserve Claude Code's built-in capabilities." System prompt content is also cacheable across invocations, reducing cost and latency for the stable portions of ralph's prompts (role definition, output format rules, commit conventions).

**`--bare` mode should be used for all scripted invocations.** Without it, Claude Code auto-discovers hooks, skills, plugins, MCP servers, auto memory, and CLAUDE.md files from the local environment. This means ralph's behavior varies across machines — a developer's local CLAUDE.md could inject conflicting instructions. Bare mode skips all auto-discovery, making execution reproducible. Ralph would then explicitly pass context via `--append-system-prompt-file` for stable rules and `-p` for dynamic task content. This is the pattern Anthropic recommends for CI/scripted usage: "Use `--bare` for CI/scripts for reproducibility."

**`--output-format json` combined with `--json-schema` would make post-invocation parsing deterministic.** Ralph's outer loop currently must parse free-text output to determine success/failure and extract results. JSON output includes `result`, `session_id`, and metadata fields. For prompt types like Playlist Completion Report and Project Summary Generation, a JSON schema would guarantee structured, validatable output — eliminating the fragile text-parsing that plagues autonomous agent systems.

Additional CLI flags ralph should evaluate include `--max-budget-usd` (cost ceiling per invocation), `--fallback-model` (automatic model fallback when the primary is overloaded), `--no-session-persistence` (avoids cluttering disk with ephemeral session data), and `--allowedTools`/`--disallowedTools` (scoping tool access per prompt type — quality gates don't need Bash write access, for example).

---

## The 500 max-turns setting is a non-functional safety net

Claude Code's default for `--max-turns` is **unlimited**. Anthropic recommends `--max-turns 5` for moderate tasks and `--max-turns 10` for complex multi-step tasks. Ralph's 500 max-turns is effectively unlimited — no legitimate coding task should require 500 tool-use cycles, and a runaway agent that hits 500 turns will have already consumed enormous token budgets and likely corrupted state.

The recommended approach is to **calibrate max-turns per prompt type**:

- **Bead Task Execution**: 15–30 turns (implement one feature, run tests, commit)
- **Quality Gate Expansion**: 5–10 turns (read code, evaluate, report)
- **Playlist Completion Report**: 3–5 turns (read state, generate report)
- **Project Summary Generation**: 5–10 turns (scan codebase, generate summary)
- **Playlist Creation**: 5–10 turns (analyze beads, generate ordering)
- **Playlist Semantic Validation**: 3–5 turns (read playlist, check dependencies)
- **Retry Context Injection**: 10–20 turns (more generous for recovery work)
- **Raw Playlist Prompt**: 15–30 turns (free-form, similar to bead execution)

Pair `--max-turns` with `--max-budget-usd` for defense in depth. When max turns is reached, Claude Code exits with an error — ralph should handle this as a specific failure type (timeout/complexity exceeded) rather than treating it the same as task failure.

---

## The 200-word handoff sacrifices structure for brevity

Ralph's 200-word cross-bead handoff truncates the previous agent's work summary into prose. While token efficiency is important — Anthropic's context engineering guide emphasizes finding "the smallest possible set of high-signal tokens" — prose summaries lose the structured information that the next invocation needs to make reliable decisions.

Anthropic's recommended pattern uses **four memory channels**, all file-based:

1. **Git commit history**: Each bead's changes are committed; next bead reads via `git diff`/`git log`
2. **progress.txt**: Chronological log of what was attempted and results
3. **task state JSON**: Structured data with `passes: true/false` — agent skips completed work
4. **AGENTS.md**: Long-term semantic memory of accumulated patterns and gotchas

The critical insight is that context should be passed as **files on disk**, not embedded in the prompt string. Each invocation reads these files fresh using Claude Code's Read tool, providing a clean context window with structured state. JSON is preferred over Markdown for task state because "the model is less likely to inappropriately change JSON files compared to Markdown."

Ralph's 200-word prose handoff should be replaced — or supplemented — with a structured JSON handoff file that the prompt instructs Claude to read. The prompt itself would contain only a brief orientation ("Read `bead-state.json` for current progress and `handoff.md` for the previous bead's summary") rather than embedding the full handoff in the prompt string. This keeps the prompt lean while providing richer cross-bead context.

---

## Prompt structure and instruction effectiveness need attention

Based on current Claude prompt engineering research, ralph's template-assembled prompts likely contain several instruction effectiveness issues that compound across the 8 prompt types.

**Instruction ordering matters more than most developers realize.** Claude exhibits a U-shaped attention curve — primacy and recency effects cause information in the middle of long prompts to receive less attention. Liu et al. (2024) measured a **30%+ accuracy drop** when answer-relevant content moved from the edges to the middle of a long context. Ralph's templates should place the most critical behavioral rules at the **top** of the assembled prompt and repeat the single most important constraint at the **bottom**, immediately before the task description. The task description itself should always be last — Anthropic's testing showed queries placed after context improve response quality by up to 30%.

**Positive framing versus specific negatives is nuanced.** Anthropic's official guidance recommends positive framing ("Write clean, minimal code" rather than "Don't write sloppy code"), and their prompt engineering docs confirm that general negative instructions can backfire by keeping the forbidden concept active in Claude's attention. However, analysis of Claude Code's own system prompts reveals extensive use of specific negative constraints targeting observed failure modes. The resolution: **use positive framing for behavioral guidelines, but use specific negatives for constraint rules** that target known failure modes. "Only create files directly required for the task" (positive) is better than "Don't create extra files" (general negative), but "Do not remove or modify existing tests — this causes regression failures" (specific negative targeting a documented failure mode) is highly effective.

**Claude 4.x models evaluate logical necessity, not emphasis markers.** Decorating instructions with MUST, ALWAYS, CRITICAL, or ALL CAPS does not reliably increase compliance. Anthropic's documentation for Claude 4 states: "Where you might have said 'CRITICAL: You MUST use this tool when...', you can use more normal prompting like 'Use this tool when...'" Ralph's templates should be audited for emphasis inflation — if every instruction is marked critical, the model treats none as truly critical.

**Failure mode inoculation is highly effective and underused.** Claude Code's own prompts describe the specific failure before the model encounters it: "You may be tempted to X. Do not do X because Y." This technique "vaccinates" the model against known failure patterns. Each of ralph's 8 prompt types should include 1–3 inoculations against the most common failures for that prompt type (e.g., for Bead Task Execution: "Do not attempt to implement multiple features at once — complete this single bead fully before stopping").

**XML tags should structure the assembled prompt.** Claude was trained to recognize XML tags as a prompt organizing mechanism. For template-assembled prompts with multiple conditional sections, XML tags provide unambiguous boundaries: `<task>`, `<context>`, `<constraints>`, `<prior_work>`, `<output_format>`. This prevents sections from bleeding into each other when conditional blocks are included or excluded. Ralph's `{{KEY}}` substitution should produce XML-delimited sections.

---

## Quality gate templates need outcome-based verification

Ralph's five quality gate types (#SMOKE_TEST, #COMPLETENESS_SCAN, #REVIEW, #REFACTOR, #DOCUMENT) represent a strong architectural pattern — but research reveals a critical vulnerability: **agents can produce no-op implementations that pass quality checks without actually addressing the requirement**.

Multiple sources document this failure mode. AgentField's production experience found agents building "entire API layers on modules that never exported the expected functions — tests passed because downstream agents mocked the dependency." Claude Code's own issue tracker documents agents completing "only the easy tasks and silently skipping the harder ones." The research is clear: **verify outcomes (build passes, tests pass, files exist, diffs are non-empty), not agent claims**.

For each quality gate, ralph should:

- **#SMOKE_TEST**: Verify that specific commands actually ran and produced expected exit codes, not just that Claude said they passed. Parse `--output-format json` for tool call results.
- **#COMPLETENESS_SCAN**: Require Claude to produce a checklist with file paths and line numbers as evidence, then verify the files exist.
- **#REVIEW**: Use `--disallowedTools "Bash,Write,Edit"` to prevent the review gate from making changes — it should be read-only.
- **#REFACTOR**: Require that existing tests still pass after refactoring (run the test suite as a post-condition in the outer loop).
- **#DOCUMENT**: Verify that documentation files were actually created/modified by checking git diff.

The self-healing pattern (quality gates creating new beads and injecting them into the playlist) is architecturally sound and aligns with the "Live-SWE-Agent" pattern of self-evolving scaffolds. However, it carries risk: self-repair using the same model that produced the error is a "non-deterministic gamble." AgentField documents regressions where agents "tried to be helpful" during repair and introduced new failures. Ralph should cap self-healing depth (maximum 2 self-generated beads per original bead) and escalate to a human-reviewable state if self-healing fails.

---

## Model escalation strategy is directionally correct but needs refinement

Ralph's haiku → sonnet → opus escalation follows the correct pattern of starting with cheaper models and escalating to more capable ones on failure. Research supports this approach — uncertainty-driven escalation achieves **97% of the most capable model's accuracy at 24% of the cost**.

However, several refinements are needed. First, **different models may interpret the same prompt differently.** Haiku 4.5 has a 200K context window like Sonnet and Opus, but its instruction-following fidelity is significantly lower. A prompt optimized for Sonnet may produce qualitatively different failures on Haiku — not just "less good" output, but structurally different output that the outer loop misinterprets. Ralph should validate that each prompt type's template produces usable output at every model tier, or maintain per-model template variants for critical sections.

Second, **the retry prompt should include the failure context but not the failed approach.** Anthropic's guidance and AgentField's production experience both recommend preserving error messages, failing test output, and the reason the previous attempt failed — but starting with a fresh approach rather than trying to patch the failed code. Ralph's Retry Context Injection should feed back "which check failed, last 20 lines of build/test output, which files were expected" while explicitly stating "implement a fresh solution rather than modifying the previous attempt."

Third, **escalation should be error-type-aware.** Rate limits (429) should trigger exponential backoff on the same model, not escalation to a more expensive one. Context overflow should trigger either truncation or model upgrade. Quality failures (200 OK but wrong output) are the only failure type that benefits from model escalation. Ralph's outer loop should classify failure types before deciding whether to retry, escalate, or abort.

Finally, Claude Code now offers a `--fallback-model` flag that handles model fallback automatically when the primary model is overloaded. This could simplify ralph's infrastructure-level (rate limit, timeout) escalation while keeping quality-based escalation in the outer loop.

---

## The 10-minute timeout should be per-prompt-type, not universal

A 10-minute timeout is reasonable for most coding tasks but creates two failure modes. For complex bead execution involving multi-file refactoring or test-suite-dependent work, 10 minutes may be insufficient — causing premature termination of otherwise productive work. For simple quality gates like #SMOKE_TEST or report generation, 10 minutes is excessively generous and delays failure detection.

Anthropic's harness research and AgentField's production experience both recommend **conversation-turn circuit breakers alongside time/cost limits.** The recommended pattern combines three limits:

- **Turn-based**: `--max-turns` calibrated per prompt type (as discussed above)
- **Time-based**: Calibrated per prompt type (2 minutes for reports, 5 minutes for quality gates, 15 minutes for complex bead execution)
- **Cost-based**: `--max-budget-usd` as an absolute ceiling

When any limit is hit, the failure type should be recorded in the handoff state so the next invocation (or escalation) knows the task was interrupted, not failed.

---

## Missing prompt types and architectural gaps

Several patterns from the research suggest capabilities ralph lacks.

**Initializer prompt type.** Anthropic's harness research uses a distinct "initializer agent" that runs only in the first session to set up `init.sh`, create the progress file, establish the git baseline, and expand high-level goals into structured feature lists. Ralph's Playlist Creation may partially serve this role, but a dedicated initializer that creates the execution environment (test scripts, linting configuration, dev server setup) would prevent repeated setup work across beads and provide a stable foundation for quality gates.

**Verification prompt type.** Distinct from quality gates, a verification prompt re-reads the original specification and confirms each requirement was met — not by running tests, but by semantic comparison of the requirement against the implementation. Anthropic's research found that without explicit verification against the original spec, "agents will mark tasks complete that technically work but don't meet requirements." This is the "premature completion" failure mode.

**Rollback/recovery prompt type.** When a bead produces a bad commit, ralph needs a prompt type that can evaluate whether to `git revert`, `git stash`, or attempt repair. Currently, retry context injection handles this implicitly, but a dedicated recovery prompt with access to `git diff`, test output, and the original bead specification would enable more intelligent recovery decisions.

**Tool scoping per prompt type.** Using `--allowedTools` and `--disallowedTools`, ralph could enforce read-only access for quality gates, prevent network access for local-only tasks, or restrict file modification to specific directories. This defense-in-depth approach aligns with Claude Code's own use of exhaustive deny-lists for its explore sub-agent rather than relying on a simple "read-only" instruction.

---

## Conclusion: high-value changes ordered by expected impact

Ralph's architecture is fundamentally sound — the deterministic bash outer loop, single-prompt-per-invocation model, template-based assembly, and quality gate system all align with validated patterns from Anthropic's own research and the broader autonomous coding agent ecosystem. The gaps are primarily in underutilizing Claude Code's CLI capabilities and in prompt engineering details that compound across hundreds of invocations.

The highest-leverage improvements, in order: **(1)** Adopt `--bare` + `--append-system-prompt-file` to separate stable behavioral rules (cacheable, in the system prompt layer) from dynamic task content (in the `-p` prompt), gaining both reproducibility and cost savings. **(2)** Replace the 200-word prose handoff with structured JSON state files that Claude reads via its Read tool, using Anthropic's four-memory-channel pattern. **(3)** Calibrate `--max-turns` and timeouts per prompt type instead of using blanket 500/10-minute settings. **(4)** Add XML tags to template assembly output so conditional sections have unambiguous boundaries. **(5)** Implement outcome-based verification in the outer loop (check exit codes, git diffs, file existence) rather than parsing Claude's prose claims about what it accomplished.

The prompt templates themselves should be audited for emphasis inflation (remove MUST/ALWAYS/CRITICAL markers in favor of clear conditional logic), instruction ordering (task description last, critical rules at top and bottom), and failure mode inoculation (describe the 2–3 most common failures for each prompt type before the model begins work). These changes are incremental and testable — each can be A/B tested against the current templates by comparing task completion rates on a fixed benchmark set.
