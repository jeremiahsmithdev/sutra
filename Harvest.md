# The Harvest

What you do when you wake up.

See also: [[PHILOSOPHY.md]] | [[metrics.md]]

---

## The Cycle

Sutra runs overnight. You sleep. Code gets written, tests get run, beads get closed, quality gates get created. By morning there is a pile of work sitting in your repository that no human has looked at.

The harvest is how you process that pile.

It is not optional. Autonomous execution without human review is how you wake up to a codebase you no longer understand. The sutra loop is fast and tireless but it has no taste. It cannot tell you whether the feature it built is the right feature. It cannot tell you whether the fix it shipped is the fix your users actually need. It completed the bead. Whether the bead was worth completing is your job.

## What the Harvest Produces

**Verified work.** Issues that passed human verification get marked `verified=yes`. This creates an audit trail showing who verified what and when. Good implementations get merged to main. Clean commits, passing tests, sensible changes. These are the wins — work that would have taken you a day, done while you slept.

**Reverted work.** Bad implementations get thrown away. No sentiment. The loop will try again tonight with better guidance. A reverted sutra run costs you nothing but tokens. A merged bad sutra run costs you debugging time for days.

**Calibrated scouts.** The scout predicted difficulty and entry points before the run. The inner loop produced actual results. Comparing the two tells you whether your scouting is accurate. If the scout said "easy, 2 iterations" and the loop took 15, that is signal. If the scout said "entry point at auth.py:45" and the loop worked in a completely different file, that is signal. Over time this tightens your scoring.

**Updated beads.** Some completed beads reveal new work. Some beads the loop couldn't finish need better descriptions. Some beads should be broken down. Some should be abandoned. The harvest is where you groom the backlog based on what the overnight run taught you.

**Refined prompts.** Every harvest teaches you something about how the loop fails. A pattern emerges — the loop keeps missing edge cases in form validation, or it writes tests that test the implementation rather than the behaviour, or it forgets to update templates after changing routes. Each pattern becomes a guardrail in your prompt. The loop does not learn between runs. You learn for it.

## The Harvest Routine

This is a checklist, not a ceremony. It should take 15-30 minutes for a typical overnight run.

**1. Read the log.** What ran, what completed, what failed, what timed out. Get the shape of the night before looking at any code.

**2. Review verification queue.** Sutra marks every closed issue `verified=needs-review` with test instructions:
```bash
bnr                    # List issues awaiting verification
```
For each issue in the queue:
- Read the verification instructions (shown in preview panel or via `bd state <id> verified`)
- Skim the diff. Does the change make sense?
- **Actually perform the verification steps.** Don't just mark verified without testing.
- Do the tests pass? Are they meaningful tests?
- Does the implementation match what you intended when you wrote the bead?

Then decide:
- **Verified:** `bV` (opens picker, select issue, marks `verified=yes`)
- **Broken:** `breopen <id>` — reopen for another attempt tonight
- **Needs rework:** Add a comment, update the bead description, let sutra try again

Do not "fix it up" — either it is good enough or the loop tries again.

**3. Check quality gates.** Sutra created review and test beads as follow-ups. Some of these the loop may have already processed. Check whether the quality gate work is substantive or superficial. A review bead that just says "looks good" is not a review.

**4. Calibrate the workflow.** Use [[metrics.md]] data to surface anomalies, then analyse qualitatively:

*Data-driven (deterministic):*
```bash
# Issues where time predictions were way off
sqlite3 .sutra/metrics.db "
SELECT issue_id, estimated_minutes, actual_minutes, time_ratio
FROM task_metrics WHERE time_ratio > 3.0 OR time_ratio < 0.3;"
```

*Qualitative (AI-assisted):*
For flagged issues, review scout reports and git diffs. Identify:
- Why the prediction was wrong
- Patterns in miscalibration (e.g., always underestimates refactoring)
- Prompt improvements to prevent recurrence
- Whether scout entity extraction or recon needs adjustment

**5. Groom the backlog.** Based on what you saw:
- Mark verified beads with `bV` after testing.
- Reopen beads where the implementation missed the point (`breopen <id>`).
- Break down beads that sutra struggled with.
- Add new beads for issues you spotted in the diffs.
- Update bead descriptions that were ambiguous.
- Check unverified closed issues: `buv` shows issues closed without verification state — decide whether to mark for review or trust them.

**6. Update guidance.** If you noticed failure patterns:
- Add guardrails to your prompt or CLAUDE.md.
- Update your AGENTS.md with new conventions.
- Adjust scout configuration if scoring was off.
- Tweak quality gate descriptions if reviews were shallow.
- Adjust sutra config to prevent recurrence.

## What the Harvest Is Not

It is not a full code review. You are not reading every line. You are reading diffs, checking intent, and making merge/revert decisions. The quality gates exist to catch detail-level issues. Your job is strategic judgment.

It is not debugging. If the loop produced broken code, revert it. Write a better bead. Let sutra try again tonight. Your time is more valuable than the loop's time. Never spend an hour fixing what sutra can redo in ten minutes.

It is not planning. Planning happens during the day when you create beads, write descriptions, set priorities. The harvest looks backward at what was produced. It does not look forward at what to produce next. Keep the phases separate.

## The Feedback Loop

The harvest is where the system improves. Not the model — the model improves on its own schedule. The system around the model: your prompts, your bead descriptions, your scout configuration, your quality gates, your conventions.

```
Night: Sutra executes → produces work
Morning: Harvest reviews → produces insights
Day: You apply insights → produces better beads, prompts, config
Night: Sutra executes with better input → produces better work
```

Each cycle tightens the system. Beads get more precise. Scouts get more calibrated. Prompts catch more edge cases. Quality gates get more specific. The loop itself does not change. Everything around it does.

This is the human role in an automated system. Not directing execution — shaping the environment that execution happens in. The harvest is where that shaping occurs.

## The Discipline

Harvest every morning. Do not skip it. Do not let two nights of unharvested work accumulate. An unharvested run is unreviewed code in your repository, which is technical debt you chose to take on.

Revert freely. Sutra does not have feelings. It does not remember that you threw away its work. Tomorrow it will try again with no grudge and no hesitation. Reverting is cheap. Merging bad work is expensive.

Timebox it. If the harvest is taking more than 30 minutes, the overnight run attempted too much. Reduce the number of beads in scope. Smaller batches, more frequent harvests.

Trust the process. The first few harvests will feel slow and the output will be rough. The tenth harvest will be fast because your prompts have absorbed nine rounds of refinement. The twentieth harvest will feel routine. That is the goal.

---

## Quick Reference: Verification Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `bneeds-review` | `bnr` | List issues awaiting verification |
| `bverify` | `bV` | Select and mark issue as verified |
| `bmark-review` | `bmr` | Mark a closed issue as needs-review |
| `bverified` | - | List already-verified issues |
| `bunverified` | `buv` | List closed issues with no verification state |

For complete verification workflow details, see [[BEADS_VERIFICATION_WORKFLOW.md]].
