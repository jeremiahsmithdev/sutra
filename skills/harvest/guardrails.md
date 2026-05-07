# Guardrails Reference

Detailed explanations of the seven guardrails for methodology harvest findings.

## Guardrail 1: Loop Placement

**Does this change keep intelligence in the inner loop and orchestration in the outer loop?**

The philosophy is: intelligence lives in the inner loop (Claude), the outer loop is boring and deterministic.

| Example | Accepted? | Why |
|--------|-----------|-----|
| Adding a template variable for branch context | ✓ | Better artefacts for inner loop |
| Adding a `context-injection` gate tag | ✓ | Gives model more to reason over |
| Hardcoding "if retries > 2, escalate" | ✗ | Judgment moved to bash |
| Caching Claude's analysis in state | ✗ | Ephemeral decision frozen |
| Adding a heuristic to pick next bead | ✗ | Model's job, not bash |

**Key principle:** The outer loop should not make decisions that require intelligence. If you need Claude to decide something, the outer loop should pass the data and let Claude decide.

## Guardrail 2: Simplicity Delta

**Net lines added or removed? Bias strongly toward subtractive.**

The system grows complex by default. Every addition must be justified.

| Example | Accepted? | Why |
|--------|-----------|-----|
| Removing 20 lines by clarifying a template | ✓ | Subtractive — complexity down |
| Adding 5 lines to prevent a crash | ✓ | Justified — fixes real bug |
| Adding 50 lines of "smarter" selection | ✗ | Over-complication |
| Refactoring a 250-line file into two 120s | ✓ | Same code, better structure |
| Adding abstraction layer "for future" | ✗ | Premature, adds lines now |

**Key principle:** If a prompt tweak or description clarification would work, do that instead of adding code.

## Guardrail 3: Artefact vs Decision

**Does this store reusable evidence, or freeze an ephemeral decision?**

Artefacts are data the model can read and reason over. Decisions are model outputs that should not be frozen.

| Example | Accepted? | Why |
|--------|-----------|-----|
| Writing turn counts to `.ralph/metrics.db` | ✓ | Reusable data for analysis |
| Writing tool use patterns to state | ✓ | Reusable context for next invocation |
| Caching Claude's suggested task order | ✗ | Ephemeral decision frozen |
| Storing "this bead is blocked" heuristic | ✗ | Model's judgment, not reusable |
| Saving retry success/failure pattern | ✓ | Reusable evidence |

**Key principle:** Store what happened (artefacts), not what the model concluded from it (decisions).

## Guardrail 4: Determinism

**Does failure become more predictable, or does non-determinism sneak in?**

The outer loop must be predictable. Randomness or opaque failure modes are defects.

| Example | Accepted? | Why |
|--------|-----------|-----|
| Adding explicit validation before operation | ✓ | Clearer failure |
| Adding error logging with specific context | ✓ | Predictable diagnosis |
| Adding "random retry" mechanism | ✗ | Non-deterministic |
| Try-catch that logs "error occurred" | ✗ | Opaque failure mode |
| Timeout with exponential backoff | ✓ | Deterministic timing |

**Key principle:** When something fails, it should fail in a way that is immediately explainable and repeatable.

## Guardrail 5: Configurable, Not Required

**New capability must be opt-in via `.ralph/config`.**

Users upgrade ralph and expect their workflows to keep working. Changes to default behaviour break this.

| Example | Accepted? | Why |
|--------|-----------|-----|
| Adding `GATE_AUTO_INJECT=true` config | ✓ | Opt-in, default behavior unchanged |
| Adding `--strict-gates` flag | ✓ | CLI flag, user must request it |
| Changing default `MODEL=haiku` to `sonnet` | ✗ | Behavioral change for all users |
| Enabling new gate by default | ✗ | Changes playlist behavior |
| Adding `CIRCUIT_BREAKER_THRESHOLD` config | ✓ | Parameter tuning, new default is safe |

**Key principle:** Existing users are paying customers. Never change what happens when they run `./ralph` unless they explicitly ask for it.

## Guardrail 6: Template vs Code

**Instruction changes live in `templates/`. Orchestration changes live in `lib/`.**

This separation keeps the system maintainable. When you need to change how something is said, edit templates. When you need to change how something happens, edit code.

| Example | Accepted? | Why |
|--------|-----------|-----|
| Modifying `prompt_bead.txt` | ✓ | Template change |
| Adding function to `playlist.sh` | ✓ | Code change |
| Embedding prompt string in bash | ✗ | Instruction in code — hard to edit |
| Adding bash logic to gate template | ✗ | Code in template — dangerous |
| Adding `{{BRANCH_CONTEXT}}` variable | ✓ | Template enhancement |

**Key principle:** If you're changing words, go to `templates/`. If you're changing logic, go to `lib/`. Never mix.

## Guardrail 7: Size Limits

**File ≤ 200 lines. Function ≤ 50. Case branch ≤ 10. Inline string ≤ 5.**

These limits are ralph-specific coding standards. They apply because methodology harvest findings are about improving ralph's own codebase.

| Example | Accepted? | Why |
|--------|-----------|-----|
| Splitting 250-line file into two 120s | ✓ | Within limits |
| Extracting 30-line function from 200-line file | ✓ | Within limits |
| Adding 60-line function | ✗ | Exceeds function limit |
| 15-line case statement | ✗ | Exceeds case branch limit |
| 10-line inline string | ✗ | Exceeds inline string limit |

**Action to take:** If a finding would violate a size limit, either:
1. Refactor to stay within limits (preferred)
2. Document the exception in the bead description with explicit approval

**Key principle:** Small files are easier to understand, test, and modify. Large files accumulate cruft.
