# Harvest Examples

Concrete examples of findings, with classification and guardrail scoring.

## Example 1: Inner-loop instruction gap — ACCEPTED

**Finding:** The retry prompt doesn't include the previous turn's tool outputs,
so Claude doesn't know what it already tried.

**Evidence:** Stream-json shows 3 retries on bead br-123, each turn has identical tool
uses (same grep command run 3 times). Session log line 2340 shows "retrying
with context" but templates/retry_context.txt only includes turn count.

**Classification:** Inner-loop instruction gap

**Guardrail scoring:**
1. ✓ Loop placement: Gives inner loop better artefacts (previous outputs)
2. ✓ Simplicity delta: Adds 2 lines to template (minor)
3. ✓ Artefact vs decision: Stores previous outputs (reusable data)
4. ✓ Determinism: No non-determinism introduced
5. ✓ Configurable: No behavior change, just better context
6. ✓ Template vs code: Modifies template (correct location)
7. ✓ Size limits: Template stays well under 200 lines

**Result:** ACCEPTED — becomes bead `HV: Include previous tool outputs in retry prompt`

---

## Example 2: Outer-loop orchestration gap — ACCEPTED

**Finding:** The circuit breaker trips after 2 no-progress events, but a single
stalled bead can cause repeated failures across invocations. The breaker should
track per-bead progress.

**Evidence:** Bead br-456 stalled across 3 invocations, each incremented the
circuit breaker state independently. After third, breaker opened and halted the
run, even though other beads were making progress.

**Classification:** Outer-loop orchestration gap

**Guardrail scoring:**
1. ✓ Loop placement: Makes outer loop's job more boring (clearer state machine)
2. ✓ Simplicity delta: Adds 5 lines to track per-bead progress
3. ✓ Artefact vs decision: Stores progress data (reusable)
4. ✓ Determinism: Makes failure more predictable (per-bead tracking)
5. ✓ Configurable: No default behavior change
6. ✓ Template vs code: Modifies lib/circuit_breaker.sh (correct location)
7. ✓ Size limits: Function stays under 50 lines

**Result:** ACCEPTED — becomes bead `HV: Track per-bead progress in circuit breaker`

---

## Example 3: Bead-description shape — ACCEPTED

**Finding:** Epic br-789 has a 40-line description but only 2 tasks, and the
tasks have single-line descriptions. Implementing this epic required re-reading
the epic description for context.

**Evidence:** Bead br-790 and br-791 have 1-line descriptions ("Add auth",
"Add tests"). Session log shows agent asked to "re-read epic context" twice.

**Classification:** Bead-description shape

**Guardrail scoring:**
1. ✓ Loop placement: Improves bead descriptions (better artefacts)
2. ✓ Simplicity delta: No code change — bead edit only
3. ✓ Artefact vs decision: Better descriptions (artefact improvement)
4. ✓ Determinism: N/A (not about code)
5. ✓ Configurable: N/A (bead description)
6. ✓ Template vs code: N/A (not about code)
7. ✓ Size limits: N/A (not about code)

**Result:** ACCEPTED — becomes bead `HV: Clarify epic task descriptions`

---

## Example 4: Gate template — ACCEPTED

**Finding:** The `#REVIEW` gate template doesn't specify what aspects to
review. Expansion produces generic "review the changes" prompts that Claude
acts on by re-reading the entire codebase.

**Evidence:** Stream-json after #REVIEW shows turn count 45 with full codebase read
for each bead. The template at templates/gate_review.txt has no guidance
on what to focus on.

**Classification:** Gate template

**Guardrail scoring:**
1. ✓ Loop placement: Better template gives inner loop clearer task
2. ✓ Simplicity delta: Adds 10 lines to template (worthwhile)
3. ✓ Artefact vs decision: Better template (artefact)
4. ✓ Determinism: N/A (template change)
5. ✓ Configurable: N/A (template)
6. ✓ Template vs code: Modifies template (correct location)
7. ✓ Size limits: Template stays under 200 lines

**Result:** ACCEPTED — becomes bead `HV: Add focus guidance to #REVIEW gate template`

---

## Example 5: Inner-loop instruction gap — REJECTED (Guardrail 6)

**Finding:** The playlist parser should skip blank lines, but currently fails.
Add an `if [[ -z "$line" ]]; then continue` check.

**Evidence:** Session log shows "error: empty line in playlist" when a user added
a blank line between gate tags.

**Classification:** Inner-loop instruction gap (but actually...)

**Guardrail scoring:**
1. ✓ Loop placement: Correct location for blank line handling
2. ✓ Simplicity delta: Adds 2 lines (fine)
3. ✓ Artefact vs decision: N/A
4. ✓ Determinism: N/A
5. ✓ Configurable: N/A
6. ✗ **Template vs code: This is code logic (blank line handling), not instruction**
7. ✓ Size limits: N/A

**Result:** REJECTED — Guardrail 6. The fix should be in lib/ (playlist.sh),
not by changing how the parser is described.

**Correct classification:** This is actually an **outer-loop orchestration gap**,
not an instruction gap. The fix belongs in code, not a template.

---

## Example 6: Outer-loop orchestration gap — REJECTED (Guardrail 1)

**Finding:** Add a heuristic: if a bead retries 3 times, automatically escalate
to opus on the next attempt.

**Evidence:** Stream-json shows 3 beads that escalated to opus succeeded after
haiku/sonnet failed. This would have saved 2 retries per bead.

**Classification:** Outer-loop orchestration gap

**Guardrail scoring:**
1. ✗ **Loop placement: Pushes judgment into bash (deciding when to escalate)**
2. ✓ Simplicity delta: Adds 5 lines
3. ✓ Artefact vs decision: Stores escalation count (data)
4. ✓ Determinism: Makes escalation more predictable
5. ✓ Configurable: Could be a config option
6. ✓ Template vs code: Correct location (lib/invoke.sh)
7. ✓ Size limits: Within limits

**Result:** REJECTED — Guardrail 1. The decision of when to escalate belongs
in the inner loop (Claude's retry logic), not hardcoded in bash.

**Alternative approach:** Improve the retry context template to give Claude better
information about why the task failed, letting the model decide when to escalate.

---

## Example 7: Context injection — REJECTED (Guardrail 5)

**Finding:** Always include the full playlist progress snapshot in every bead
prompt, regardless of run mode.

**Evidence:** Some sessions showed Claude getting confused about what had been
completed because it didn't have progress context.

**Classification:** Context injection

**Guardrail scoring:**
1. ✓ Loop placement: Better artefacts for inner loop
2. ✓ Simplicity delta: No code change
3. ✓ Artefact vs decision: Stores progress (reusable)
4. ✓ Determinism: N/A
5. ✗ **Configurable: Changes default behavior for all runs**
6. ✓ Template vs code: Template change
7. ✓ Size limits: N/A

**Result:** REJECTED — Guardrail 5. This would add 50+ lines of context to
every prompt for all users. Some runs don't need this.

**Alternative approach:** Add a config option `INCLUDE_PROGRESS_CONTEXT=true`
(default false) so users can opt-in when they need it.

---

## Example 8: Inner-loop instruction gap — REJECTED (Guardrail 2)

**Finding:** Add a 60-line template that generates detailed retry context
including previous tool outputs, file diffs, and error summaries.

**Evidence:** Retries often failed because Claude didn't have enough context about
what went wrong.

**Classification:** Inner-loop instruction gap

**Guardrail scoring:**
1. ✓ Loop placement: Better artefacts
2. ✗ **Simplicity delta: Adds 60 lines to template — disproportionate**
3. ✓ Artefact vs decision: Stores more context
4. ✓ Determinism: N/A
5. ✓ Configurable: N/A
6. ✓ Template vs code: Template change
7. ✓ Size limits: Template still under 200 lines

**Result:** REJECTED — Guardrail 2. A 60-line template is disproportionate.
Can the same effect be achieved with 10 lines of prompt engineering?

**Alternative approach:** Clarify the existing retry context template with 2-3
focused lines that tell Claude what to look at (tool outputs, last error).

---

## Quick reference: What makes a good finding?

| Category | What to look for | Good finding | Bad finding |
|----------|----------------|--------------|-------------|
| Inner-loop instruction gap | Missing context, vague prompts | "Template X doesn't include Y" | "Add more detail to everything" |
| Outer-loop orchestration gap | Crashes, stalls, unreliable behavior | "Function X crashes on edge case Y" | "Make the loop smarter" |
| Bead-description shape | Ambiguous, incomplete descriptions | "Task br-123 has no what-to-implement" | "Descriptions should be better" |
| Gate template | Generic expansion, missing cases | "#REVIEW doesn't specify focus" | "Gates should be stricter" |
| Context injection | Missing state that would help | "Bead prompts lack branch context" | "More context is always better" |

**Rule of thumb:** A good finding points to a specific file/line and describes
a concrete change. A bad finding is vague or proposes over-general improvements.
