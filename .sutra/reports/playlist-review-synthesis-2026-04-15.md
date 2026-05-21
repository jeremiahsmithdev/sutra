---
type: synthesis
reviewer: claude (opus-4-6)
date: 2026-04-15
inputs:
  - .ralph/playlist-review-2026-04-15.md       # Chippie / recurring-jobs.playlist (pre-adjustments)
  - .ralph/reports/chippie-xero-review.md      # Chippie / xero-integration.playlist (post-adjustments)
purpose: |
  Synthesise two manual playlist reviews into (a) a prioritised adjustment list
  validated against the current ralph codebase, (b) a suggested bead roster,
  and (c) gap analysis against the draft HARVEST_METHODOLOGY.md.
---

# Playlist Review Synthesis — Recommended Adjustments

Two manual reviews were performed on Chippie playlist runs — one before recent ralph adjustments (usage-limit wait, ANSI stripping, progress-file fixes) and one after. This document consolidates their findings, validates each against the current ralph source tree, and produces an actionable adjustment plan.

## Codebase validation performed

Before writing this synthesis the following files were inspected to confirm findings still apply:

- `lib/playlist.sh` (`playlist_advance`, `playlist_execute`)
- `lib/utils.sh` (`save_state`)
- `lib/invoke.sh` (`_invoke_claude_once` — pre-invocation `save_state` call)
- `lib/task_outcome.sh` (`maybe_close_epic`)
- `lib/playlist_marker.sh` (validation-marker interactive prompt)
- `templates/branch_playlist.txt`
- `templates/gate_document.txt`
- `ralph` (main loop)

All CRITICAL and HIGH findings below were confirmed as still present in the current tree.

---

## Findings, ranked by severity

### CRITICAL — still present in codebase

**C1. Playlist pointer advances before invocation completes.**
`lib/invoke.sh:116` calls `save_state` *before* Claude runs. `save_state` → `playlist_advance` (`lib/utils.sh:163`) unconditionally commits the pending line. A usage-limit error, timeout, or crash during invocation leaves the pointer already moved. Caused orphaned `chippie-jy1a.4` and skipped `#SMOKE_TEST` between runs 2 and 3 of the xero playlist → unverified `#REFACTOR` and `#DOCUMENT` ran against unsmoke-tested code. The failure-path reset at `lib/playlist.sh:142/144` is a no-op because the commit has already persisted.

*Fix:* either (a) remove `playlist_advance` from `save_state` and add an explicit `playlist_advance` between `playlist_execute` and `save_state` on the main loop (`ralph:26`); or (b) gate `playlist_advance` inside `save_state` on an explicit `invocation_succeeded` flag set only after `playlist_execute` returns 0.
*Scope:* ~5 lines net across `lib/utils.sh`, `ralph`, `lib/playlist.sh`.

**C2. Branch template contradicts AUTO_COMMIT=false rule.**
`templates/branch_playlist.txt:3` reads `Commit directly on \`{{BRANCH}}\`. Merging is a separate manual step.` while the raw-prompt Rule 4 says "Do NOT commit." Claude consistently obeys Rule 4, leaving per-bead work uncommitted. Direct cause of run-1's commit-history collapse (9 beads → 1 mislabelled `refactor(...)` commit) and run-3's xero leak (6/7 test files untracked despite bead `.6` claiming 47 passing tests).

*Fix:* rewrite `templates/branch_playlist.txt` line 3 to `Commits on \`{{BRANCH}}\` are made by the outer loop after \`br close\`. Do NOT run \`git add\`, \`git commit\`, or \`git stash\` — per-bead history is lost if you commit yourself.` Then either (a) flip `AUTO_COMMIT=true` by default for playlist mode, or (b) add per-bead commit in `lib/task_outcome.sh` after `br close` (~15 lines) using the bead title/slug as the commit message.
*Scope:* 1 template line + either 1 config default flip or ~15 lines in `task_outcome.sh`.

**C3. Epic auto-close doesn't fire; `DONE` status not rolled forward.**
`chippie-9zsi` stayed open with all 9 children closed; `chippie-9zsi.7` stuck in `DONE`. `maybe_close_epic` exists at `lib/task_outcome.sh:110` but either wasn't invoked on every close path or the `DONE` child blocked it.

*Fix:* trace `maybe_close_epic` to confirm it treats `DONE` as closed-equivalent, and verify invocation on every close path (bead close, gate-created bead close, injected bead close). Add a post-close outer-loop check: if `br show <child>` returns `DONE`, run `br close <child>` with a roll-forward reason.

### HIGH — still present

**H1. Validation-marker prompt silent-proceeds on non-interactive TTY.**
`lib/playlist_marker.sh:46-52` reads `[y/N]` and falls through to "Proceeding without validation" on non-interactive input. All three xero runs bypassed `playlist init`'s semantic audit.

*Fix:* when `[[ ! -t 0 ]]`, halt unless `PLAYLIST_AUTO_CONTINUE=true` in `.ralph/config` or `--yes` passed. ~5 lines.

**H2. `{{PROMPT_TEXT}}` placeholder leak in rendered gates.**
Report 1 evidence: `**Edge Cases {{PROMPT_TEXT}} Limitations**` appeared in the rendered `#DOCUMENT` prompt while source (`templates/gate_document.txt:73`) reads `**Edge Cases & Limitations**`. The `&` → `{{PROMPT_TEXT}}` mangling suggests sed-style back-reference substitution in `render_template` or one of its callers.

*Fix:* audit `render_template` in `lib/utils.sh` and callers for any `sed 's/.../.../'` that doesn't escape `&`. Add a regression test template containing `&`, `\1`, `\0`.

**H3. Completion-report retries burn budget on usage-limit.**
Run 1 burned 3 retry attempts on report generation after hitting the usage-limit. Report generation is non-load-bearing telemetry.

*Fix:* in the completion-report path (`lib/lifecycle.sh`), treat exit 1 from `invoke_claude` as "skipped, log only" — don't retry. Or detect usage-limit exit code specifically. ~5 lines.

### MEDIUM — template / prompt hygiene

**M1. Bead prompts duplicate ~80 lines of epic context per invocation.**
Report 2 §4.2 measured ~720 redundant lines across the run (~32k recomputed tokens). The "Pricing", "AI/ML Compliance", "Existing Code" blocks are epic-scoped, not bead-scoped.

*Fix:* convention change — epic descriptions should link to a `docs/technical/features/<epic>_SPEC.md` file rather than inlining spec content. Epic `description` shrinks to 3–5 lines + link. Update `prompt_context.sh` / `prompt.sh` guidance if needed.

**M2. `## Playlist Progress` block is noisy for early beads.**
~16 lines of not-yet-started items on the first bead. ~150–300 tokens × N invocations.

*Fix:* in `lib/playlist_progress.sh::format_playlist_progress`, when `current_index <= 1` emit a one-line `Position: N/M · Next: <name>`. Cap "Remaining" at +3 lookahead. Saves ~150–300 tok × invocations.

**M3. `#REFACTOR` gate has no scope cap.**
Run 3 only stayed scoped because the playlist author hand-pinned a directory. Without the pin, `git diff` from session start sweeps everything.

*Fix:* in `templates/gate_refactor.txt` add a scope-limit block: run `git diff --stat` first; if > 10 files or > 1000 lines, STOP, ask via `br create` which directory to focus on, and exit. Pure template change.

**M4. `#SMOKE_TEST` gate lacks preconditions.**
No server-start, no tenant-context, no rollback-on-finding. Produces false negatives when the environment isn't already up.

*Fix:* bake preconditions into `templates/gate_smoke_test.txt` — start dev server, obtain auth/session, kill server on exit, collect failures-then-report (don't spawn beads mid-check). Report 2 §4.1 contains a concrete rewrite to adapt.

**M5. Close instruction buried under injected context.**
Boilerplate `"VERIFY: [how to test] NOTES: [what changed]"` leaked into close reasons (Report 2 §4.3).

*Fix:* in `templates/prompt_bead.txt` reorder — move `## On Success: br close …` to immediately after `## Your Task`, before Project Summary. ~3 lines reordered.

### LOW

**L1. Gate default to `@opus` inflates cost.** `#DOCUMENT` at opus (30 turns, $1.35) would have been ~$0.30 on sonnet. Suggest: escalate gates only on retry, don't pin them to opus.
**L2. Turn cap of 500 is 7.7× over-provisioned.** Max observed across both reports: 75. Drop default to ~100 with per-prompt override.
**L3. Retry context doesn't accumulate failure history.** Attempts 2 and 3 showed identical "Last output" prose — append-not-replace needed in `templates/failure_tail.jq` / `lib/invoke_retry.sh`.

---

## Suggested beads

One epic + 14 child beads, all `label=self-improvement`, title prefix `HV:` (conforms to HARVEST_METHODOLOGY convention even though these findings predate the methodology's first automated run).

**Epic:** `HV: Playlist review consolidation — 2026-04-15 dual-run retrospective`
*Type:* epic · *Priority:* 1 · *Label:* `self-improvement`

**Children:**

| Title | Priority | Type | Source |
|-------|----------|------|--------|
| `HV: Playlist pointer advances on failed invocation` | P0 | bug | C1 |
| `HV: Branch template contradicts AUTO_COMMIT=false rule` | P0 | bug | C2 |
| `HV: Outer loop auto-commits per-bead after br close` | P1 | chore | C2 follow-on (pick enable-AUTO_COMMIT OR outer-loop commit, not both) |
| `HV: Epic auto-close fails when child in DONE state` | P1 | bug | C3 |
| `HV: Non-interactive validation prompt silent-proceeds` | P1 | bug | H1 |
| `HV: Placeholder leak in render_template & back-reference` | P1 | bug | H2 |
| `HV: Completion report retries on usage-limit` | P2 | chore | H3 |
| `HV: Epic description spec-file extraction convention` | P2 | chore | M1 |
| `HV: Playlist progress block noise on early beads` | P2 | chore | M2 |
| `HV: Refactor gate scope cap` | P2 | chore | M3 |
| `HV: Smoke-test gate preconditions` | P2 | chore | M4 |
| `HV: Close instruction position in bead prompt` | P3 | chore | M5 |
| `HV: Gate default model + turn cap calibration` | P3 | chore | L1 + L2 |
| `HV: Retry context accumulation` | P3 | chore | L3 |

Command shape for creation:
```bash
br create --type=epic --priority=1 --title="HV: Playlist review consolidation — 2026-04-15 dual-run retrospective"
# for each child:
br create --type=<bug|chore> --priority=<N> --parent=<epic-id> \
    --title="HV: <...>" \
    -d "<self-contained description with file:line refs from this report>"
br update <id> --label self-improvement    # if label must be added separately
```

---

## Gap analysis — what HARVEST_METHODOLOGY.md (current draft) would NOT have caught

Reading both reports against the rubric I drafted, six gaps surface. Each is an opportunity to tighten the methodology before its first automated run.

**G1. Cross-run pattern detection.** Report 2 pulls signal from three sequential runs to spot the pointer-advance bug. The methodology doc is written single-run. *Fix:* add a "look-back window" clause — the harvest may ingest the last N runs of the same playlist and diff pointer positions, bead states, and working-tree state across them.

**G2. Ground-truth cross-checking.** Both reports validate `playlist-progress.md` claims and Claude's prose against `br show` and `git status`. The methodology's collection step reads both but doesn't mandate comparison. *Fix:* add an explicit "Ground Truth" sub-step — for every completed bead, compare progress-file claim vs `br show` status; compare close-reason claims vs `git log --stat` / `git ls-files`. Auto-flag divergences.

**G3. Git state as primary oracle.** The methodology lists "bead state diff" but not "working-tree state" or "commit-graph shape". Both reports caught bugs via `git log --stat` (9 beads → 1 commit) and `git status` (untracked test files). *Fix:* add `git log --stat <session-base>..HEAD`, `git status --porcelain`, and `git log --diff-filter=A` to collection inputs.

**G4. Prompt-internal contradiction detection.** The branch-template vs Rule-4 contradiction is a same-prompt inconsistency. The methodology's five classification categories don't include a "prompt coherence audit". *Fix:* for each rendered prompt in stream JSONL, audit for internally contradictory imperatives (e.g. "commit X" + "do not commit").

**G5. Outcome-vs-symbolic-state as a first-class axis.** The pattern connecting C1, C3, and the §P1 commit leak is *ralph trusting symbolic state (pointer, progress file, Claude's prose) over observable state (git diff, br show, exit codes)*. This cuts across the existing five categories and deserves its own. *Fix:* add a sixth classification category — "outcome-verification gap" — distinct from outer-loop orchestration because fixing it means *adding* a post-condition check, not modifying existing orchestration.

**G6. Unattended-mode behaviour.** H1 (silent auto-proceed) is specifically about non-TTY behaviour. The methodology assumes the harvest reviews a completed run but doesn't ask "which safety checks were bypassed by non-interactive defaults?" *Fix:* add a "bypass audit" — enumerate all confirmations and warnings in the session log and flag any auto-answered without explicit config opt-in.

---

## Recommended next steps (in order)

1. **Fix C1 and C2.** Both are small changes to ralph itself. Without them, the next playlist run carries the same risk.
2. **Update `HARVEST_METHODOLOGY.md`** to absorb G1–G6. Pure-doc change, low risk, and required before the first automated harvest has meaningful coverage.
3. **Create the epic + 14 beads** per the roster above. Once G1–G6 are absorbed into the methodology, these beads have a proper classification home.
4. **Address C3 and H1–H3** as priority work. C3 and H1 are footguns that silently erode safety; H2 and H3 are budget/hygiene issues but well-scoped.
5. **Batch M1–M5 into a "prompt-hygiene" sub-epic** for a dedicated playlist pass once the critical/high items are resolved.

---

*End of synthesis.*
