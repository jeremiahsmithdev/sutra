---
type: retrospective
project: Chippie
playlist: xero-integration.playlist
runs_reviewed: [20260415-023942, 20260415-040538, 20260415-040809]
reviewer: claude (opus-4-6)
date: 2026-04-15
---

# Ralph playlist retrospective — Chippie `xero-integration.playlist`

> This is an evaluation, not a summary. Every claim is backed by file paths, log line numbers, bead IDs, or commit SHAs.

## 1. Scoreboard

| Run | Started | Ended | Wall | Loops | Real invocations | Cost | Exit | Circuit |
|---|---|---|---|---|---|---|---|---|
| **1** `023942` | 02:39 | 03:06 | ~27m | 7 | 4 productive + 5× $0 errors | **$5.85** | Usage limit, 3 retries exhausted | CLOSED |
| **2** `040538` | 04:05 | 04:05 | ~10s | 1 | 0 (immediate limit) | $0.00 | Usage limit | CLOSED |
| **3** `040809` | 04:08 | 05:06 | ~58m (37m of it waiting) | 4 | 3 beads/prompts + 1 report | **$14.30** | Playlist complete | CLOSED |

**Bead outcomes (ground truth — `br show`, not `playlist-progress.md`):**
- Closed: `chippie-jy1a.{1,2,3,5,6}` — 5 of 6
- **Still `in_progress`**: `chippie-jy1a.4` (Xero settings UI) — **never executed after run 1's 2-turn usage-limit crash at 03:04:59**
- Not in playlist: `chippie-jy1a.7` (still open)
- Epic `chippie-jy1a`: **5/7 children closed (71%)**, NOT the "9/9 complete" that `.ralph/playlist-progress.md:5` reports.

**Per-invocation stats (from `stream/*.jsonl` `.type=="result"` records):**

| Inv | Bead / Prompt | Turns | Cost | Duration | Model |
|---|---|---|---|---|---|
| R1-001 | `jy1a.1` rebase | 65 | $1.82 | 7.6m | sonnet |
| R1-002 | `jy1a.2` review+update | 39 | $1.13 | 4.7m | sonnet |
| R1-003 | `jy1a.3` XeroInvoiceService | 41 | $1.24 | 4.9m | sonnet |
| R1-004 | `jy1a.5` webhooks | 48 | $1.66 | 7.5m | sonnet |
| R1-005 | `jy1a.4` settings UI (limit-killed at turn 2) | 2 | $0.08 | 5s | sonnet |
| R1-006..010 | report generation — all usage-limit | 1 ea | $0 | <1s ea | sonnet |
| R3-002 | `jy1a.6` tests | 60 | **$4.04** | 10.2m | **opus** (escalated) |
| R3-003 | `#REFACTOR` | 50 | **$2.88** | 7.2m | opus |
| R3-004 | `#DOCUMENT` | 30 | $1.35 | 3.1m | opus |
| R3-005 | completion report | 5 | $0.18 | 24s | sonnet |

Max turns used anywhere: **65** (R1-001). Configured ceiling: **500**. `research.md`'s "non-functional safety net" claim is **confirmed** in the strongest possible way — actual/budget ratio is 13%.

---

## 2. Three things that went well

**W1. Usage-limit wait-and-resume worked exactly as designed in run 3.**
The recently-added feature (per `git log /Users/admin/dev/ralph | head`: commit `d4a844e feat: wait for 5-hour usage window reset`) fired at `040809.log:207`:
> `⚠️ USAGE LIMIT HIT - WAITING FOR 5-HOUR WINDOW RESET / Reset time: 11:00pm / Wait duration: 37 minutes`
Ralph slept 37 min, woke, retried with **sonnet → opus escalation** (`:215`), and completed `jy1a.6` on the first opus attempt. This single feature is the reason run 3 finished at all.

**W2. Model escalation produced a real success, not just a retry loop.**
R3-002 was the first invocation post-reset. It escalated to opus and solved `jy1a.6` in 60 turns for $4.04 — producing a 47-test suite across 7 files. Haiku/sonnet on a fresh 10-min window might have timed out; the escalation-on-retry heuristic paid off here. Evidence: `040809.log:527` `br close chippie-jy1a.6 --reason "… 47 passed in <1s …"`.

**W3. The REFACTOR gate was substantive and produced a clean commit.**
Commit `478a63a refactor(xero): extract shared API helpers` is real work: `_xero_api.py` (147 lines) consolidates `XERO_API_URL` (was 3×), `xero_api_request` (was 4×), `store_rate_limits` (was 2×), `log_sync` (was 3×). Contact service shrank 42%, invoice service 32%. `git show --stat 478a63a`: 1553 insertions / 419 deletions across 9 files. The gate's "skeptical senior reviewer" framing (`040809.log:552-558`) produced measurable reduction, not bikeshedding.

---

## 3. Three things that went poorly — with evidence

### P1. The commit contradiction predicted by `review.md §2.2/§3.5` literally occurred, and it cost real work.

The same prompt emitted during run 1 contains both:

- `023942.log:144` — `Commit directly on xero-integration.playlist. Merging is a separate manual step.`
- `023942.log:150` — `4. Do NOT commit. Leave changes staged or unstaged — commits are handled externally.`

Claude followed rule 4. Run 1 closed beads `.1`, `.2`, `.3`, `.5` — claiming fully-implemented work — and produced **zero new commits**. The only "xero" commit in the branch dated to the January 2026 pre-existing WIP:

```
02414c7 wip: xero integration          ← Sun Jan 18 2026 (pre-ralph)
4b bead-state-sync commits             ← ralph outer loop
```

The beads' actual diffs lived uncommitted in the working tree until **run 3's REFACTOR gate accidentally swept them into `478a63a`** (the refactor commit pulled in `xero_invoice_service.py` +443 lines and `xero_webhook_service.py` +497 lines — neither of which had any pre-existing commit to "refactor from"). The refactor gate was inadvertently doing the original beads' commit work.

**And the leak is still leaking today.** `git status` right now on `xero-integration.playlist`:
```
Changes not staged for commit:
  modified:   application/api/integrations.py            (+85/-20)
  modified:   application/auth/middleware.py
  modified:   application/models/tenant/xero_connection.py
  modified:   application/services/integrations/xero/xero_sync_service.py  (+91/-30)
  modified:   atlas/migrations_tenant/atlas.sum
Untracked:
  tests/test_xero/__init__.py, conftest.py, test_xero_api.py,
  test_xero_auth_service.py, test_xero_encryption.py, test_xero_webhook_service.py
  atlas/migrations_tenant/20260415000003_add_xero_rate_limit_columns.sql
  atlas/migrations_tenant/20260415000004_add_xero_connection_sync_config.sql
  XERO_INTEGRATION_RESEARCH.md, ARCHITECTURE_INCONSISTENCIES_ANALYSIS.md
```

6 of the 7 test files that bead `.6` is supposedly "VERIFY: run pytest tests/test_xero/ -v — expect 47 passed" against are **untracked in git**. Bead `.6` is `CLOSED` with `verified:needs-review`. Two untracked Atlas migrations sit next to the committed one. This is exactly the research.md "no-op implementations passing gates" pattern, induced by the prompt contradiction.

### P2. `chippie-jy1a.4` was silently abandoned; `playlist-progress.md` lies about it.

Run 1's bead `.4` invocation (R1-005, `023942.log:1301`) ran 2 turns before the usage-limit kill. It was never retried. When run 3 started, its header reported `Playlist: xero-integration.playlist (9 actionable lines, starting at line 7)` (`040809.log:3`) — i.e., the line pointer had **already advanced past `.4`'s line**.

How? Run 2 (`040538.log`): the `#SMOKE_TEST` prompt on line 7 got a 1-turn usage-limit error (exit 1), **but the playlist pointer still advanced from 6 to 7**. That means a failed invocation advanced the counter. Run 3 then started at SMOKE_TEST's next successor (bead `.6` on line 8), skipping both the unfinished `.4` and the unexecuted `#SMOKE_TEST`.

Evidence the pointer advances on failure (bug-level finding):
- `040538.log:1-29` — LOOP 1 processes `#SMOKE_TEST`, 1 turn, $0, exit 1
- After `040538`, `.ralph/state` shows `playlist_line=7` → `playlist_line` had advanced
- `040809.log:7` — LOOP 1 Task: `chippie-jy1a.6` (playlist line 8), not `jy1a.4` (line 6) or `#SMOKE_TEST` (line 7)

Final state: `.ralph/playlist-progress.md:15-17`:
```
## Status: 9/9 items completed
...
* [bead] chippie-jy1a.4 — Build Xero settings UI and connection management page
* [prompt] @opus #SMOKE_TEST curl /api/integrations/xero/connect return
```
But `br show chippie-jy1a.4` → `IN_PROGRESS`. The progress file conflates "playlist pointer passed this line" with "bead completed". The final completion-report invocation (R3-005) even flagged it in Notes: `040809.log` final output — *"chippie-jy1a.4 is still in_progress — needs attention next session"* — yet the header still claims 9/9.

### P3. SMOKE_TEST was supposed to verify the prior 4 beads' endpoints; it never ran.

Playlist line 7 is the only safety-net before the REFACTOR gate (which blindly consolidates code without verifying behavior). That safety-net was consumed by a usage-limit error in run 2 and then skipped in run 3. The REFACTOR and DOCUMENT gates both fired against unverified endpoints. The curl assertions from the prompt — `POST /webhooks with bad HMAC returns 401, valid HMAC returns 200; verify xero_connection, xero_sync_log tables exist in a tenant schema` — were never executed. No webhook, no connect endpoint, no DB table was ever checked against a live backend.

---

## 4. Prompt quality audit — concrete rewrites

### 4.1 The playlist's hand-written `> #SMOKE_TEST` prompt is under-specified.

**Original (`xero-integration.playlist:7`):**
```
> @opus #SMOKE_TEST curl /api/integrations/xero/connect returns auth_url; POST /api/integrations/xero/webhooks with bad HMAC returns 401, valid HMAC returns 200; /settings renders Xero panel with connect button; verify xero_connection, xero_sync_log tables exist in a tenant schema
```

**Problems:**
- No server-start instruction. The endpoints don't respond unless a Flask dev server runs. The prompt doesn't say "start the server first, then curl".
- No tenant context. `/api/integrations/xero/connect` almost certainly requires auth + a tenant subdomain — Chippie is multi-tenant (evident from `application/models/tenant/*`). A bare curl will get 401 and the gate will record "expected auth_url, got 401" as a **fake negative** that creates noise beads.
- "valid HMAC returns 200" — with what body? Claude has to fabricate one that satisfies `xero_webhook_service.verify_signature`. If it fabricates wrong, the signature fails and the gate reports a bug that isn't there.
- No rollback on finding. If the gate finds a real issue it's supposed to `br create` a bug bead and insert into the playlist — but the same gate is also expected to curl-test. If Claude makes it half-way through the tests, hits a failure, spawns a bead, and exits, the remaining endpoints go unverified.

**Rewrite:**
```
> @opus #SMOKE_TEST @turns=25 @timeout=6
Preconditions (run before any curl):
  1. `flask run --port 5001 &` in a subshell; wait 3s; `curl -sf localhost:5001/health`
  2. Pick a tenant subdomain from `SELECT subdomain FROM tenant LIMIT 1` via `application/db_manager.py`.
  3. Mint a session cookie for that tenant via `tests/helpers/auth.py::login_as_admin`.
Checks (run ALL, collect failures, then report — do NOT spawn beads mid-check):
  A. GET  /api/integrations/xero/connect            → 200, json has `auth_url` starting `https://login.xero.com/`
  B. POST /api/integrations/xero/webhooks           → 401 when X-Xero-Signature header is absent
  C. POST /api/integrations/xero/webhooks           → 200 when body signed with XERO_WEBHOOK_KEY (use `xero_webhook_service.sign_body`)
  D. GET  /settings                                 → HTML contains id="xero-connection-panel"
  E. Tenant schema check: `psql` `\dt tenant_*.xero_connection` and `xero_sync_log` both exist.
Output: a table of {check, passed, evidence}. If ANY row fails, `br create --type=bug --title "SMOKE: <check-id> <one-line>" --description "<curl cmd> <response snippet>"`. Do not fix bugs in this invocation.
Kill the flask server on exit.
```

Rationale: makes preconditions explicit (eliminates the `research.md` "no-op pass" failure mode by forcing real HTTP responses), converts "curl each endpoint" into a closed checklist, separates detection (this gate) from fix (future bead).

### 4.2 Every bead prompt duplicates 80 lines of Xero context, whether relevant or not.

**Original (`023942.log:17-66` — repeated verbatim in the prompt for `.1` rebase, `.2` service update, `.3` invoice service, `.5` webhooks, `.4` settings UI, `.6` tests):**
```
## Scope
* OAuth 2.0 with PKCE (per-tenant token storage, Fernet encrypted)
* ONE-WAY contact sync: Chippie clients -> Xero contacts
* Invoice sync: Chippie invoices -> Xero ACCREC (default AUTHORISED)
...
## Rate Limits ...
## Pricing (AUD, tax exclusive) ...
## Granular Scopes (mandatory for apps created after 2026-03-02) ...
## Multi-Region Tax Handling ...
## Existing Code (xero branch, commit 65021d1) ...
## Missing (to build) ...
## AI/ML Compliance
Xero data operational use only. No training on Xero-sourced data.
```

**Problems:**
- "Pricing (AUD, tax exclusive)" and "AI/ML Compliance" are irrelevant for every single one of the 6 beads. They're background for the *epic*, not the task. `review.md §2.4` predicted this; the logs confirm it: each bead prompt contains these lines once.
- The "## Existing Code" block becomes stale the moment bead `.1` cherry-picks the xero branch (which it did). From bead `.2` onward, that file list is wrong — some of it is now committed, some is edited, some is replaced.
- Claude can't tell which of these is the *task description* vs the *epic background*. The actual description (`Title: Rebase xero branch onto dev and resolve conflicts / Description: Merge/rebase the xero branch (1 WIP commit: 65021d1) …`) appears at `023942.log:76-77`, 60 lines **after** the epic context started.

**Rewrite (epic description field):**
Move the bulk of that prose out of the epic `description` and into a file `docs/technical/features/XERO_SPEC.md` (ironically run 3's DOCUMENT gate already created a similar file — `0bc6af9`). Then the epic description is just:
```
Xero accounting integration for Chippie tenants (AU/GB/IE).
Specification: docs/technical/features/XERO_SPEC.md
Branch: xero-integration.playlist — cherry-picked from xero@65021d1 in task .1
```
Bead-level task descriptions contain only task-specific scope (what this one bead changes). Total prompt shrink: ~60 lines × 6 beads = ~360 lines of redundant tokens saved. Plus: when the spec changes, ONE file changes, not the epic description.

### 4.3 The bead prompts' "## When Done" / close instruction is buried under 100+ lines of injected context.

**Currently (`023942.log:1455-1475` region):** `br close <id> --reason "VERIFY: [how to test] NOTES: [what changed]"` appears *after* the Project Summary block.

**Problem confirmed by observation:** In the R3 `.6` invocation, the stream log shows Claude started its close-reason with `"VERIFY: [how to test] NOTES: [what changed]"` boilerplate still templated and had to self-correct (you can see this in `040809.log:527` where the close reason is a 400-character essay and clearly written under instruction-fatigue).

**Rewrite:** Move the close instruction to the top, right after "Your Task", and make it a positive instruction:

```
## Your Task
ID: chippie-jy1a.N
On success: `br close chippie-jy1a.N --reason "VERIFY: <exact command to re-run>  NOTES: <what changed, ≤3 lines>"`
On blocked: `br update chippie-jy1a.N --status open` AND write a handoff-note describing what you tried.
<blank line>
<Task details here>
```

This pairs with `review.md §3.1` (reorder for attention priority) and `research.md`'s primacy/recency point, but more importantly fixes the observed boilerplate-leak into close notes.

### 4.4 REFACTOR gate's scope-limit warning that `review.md` proposed, but isn't enforced.

The live REFACTOR prompt (`040809.log:552-600`) says "review code from this session". Run 3's REFACTOR did stay scoped to `application/services/integrations/xero/`, BUT only because the hand-written gate line pinned it (`xero-integration.playlist:9`: `#REFACTOR focus on application/services/integrations/xero/`). Without that hand-pin, per `review.md §2.5`, the gate would happily attack every file `git diff` shows — and in run 3's case, `git diff` from session start included the *entirety of the 02414c7 xero WIP commit* plus every uncommitted change from run 1. The gate got lucky. The template should bake in a hard cap like:

```
## Scope Limit (enforced)
Run `git diff --stat <session_start_sha>..HEAD` first. If more than 10 files or 1000 lines, STOP and ask: "The session touches N files / L lines. Which directory should I focus on?" via a `br create` 
description and exit. Do not attempt a refactor wider than 10 files without guidance.
```

This prevents a REFACTOR gate from spiraling (`review.md §5.1`'s highest risk).

---

## 5. Hypothesis verdicts against `review.md` and `research.md`

### From `review.md`

| Claim | Verdict | Evidence |
|---|---|---|
| Critical info buried at prompt end (§1, §3.1) | **Confirmed** | Close instruction at `023942.log:~1470` vs role at `:17`; `.6` close-reason showed boilerplate leakage (§4.3 above). |
| Negative instruction clustering weak under pressure (§2.3, §2.8) | **Not observed** | Claude respected `Do NOT touch .beads/` across all 11 productive invocations; none were under "pressure" in the sense the doc meant. |
| **Commit contradiction in playlist mode (§2.2, §3.5)** | **Confirmed, with blood on the floor** | `023942.log:144` vs `:150`; zero commits from run 1's 4 closed beads; `git status` today still shows leaked work (§P1). |
| Project Summary staleness within a session (§5.3) | **Confirmed** | R1-002 onward the "## Existing Code (commit 65021d1)" block is already stale because `.1` cherry-picked those files. |
| 200-word handoff insufficient (§2.4) | **Inconclusive** | Playlist mode used cross-prompt handoffs rarely; couldn't measure. |
| Gate scope sprawl (esp. #REFACTOR, §2.5, §5.1) | **Not observed here, but narrowly** | Only because the user hand-pinned a directory in the playlist line. The gate had no intrinsic cap. |
| Missing decomposition prompt type (§2.7, §4.5) | **Confirmed indirectly** | Bead `.4` died at turn 2 from usage limit; no decomposition path existed; next session skipped it entirely. Classic orphaning. |
| Missing verification prompt type (§2.7) | **Confirmed** | Bead `.6` closed with "47 tests pass" claim but 6/7 test files are untracked — nothing re-verifies the close reason. |
| Retry context lacks cumulative failure history (§3.4) | **Confirmed** | `023942.log` tail shows RETRY CONTEXT attempt 2 and attempt 3 with **identical** "Last output: You've hit your limit". No accumulation visible. |

### From `research.md`

| Claim | Verdict | Evidence |
|---|---|---|
| 500 max-turns is a non-functional safety net | **Confirmed, strongly** | Max turns used: 65. P90: 50. Budget utilization: 13%. |
| 10-min timeout should be per-prompt-type | **Contradicted in the small, Confirmed in the large** | All real invocations finished inside 11m; but the system default `--timeout 300m` is set by the current `state.model=sonnet` / config — orders of magnitude too loose. |
| Prose 200-word handoff loses structure | **Inconclusive** | Not exercised (playlist mode). |
| Missing `--append-system-prompt`/`--bare` means repeated context-injection costs | **Confirmed** | Same ~80 lines of Xero context appeared in 6 bead prompts + 3 gate prompts = ~720 redundant lines of injection. At ~50 tok/line × 9 = ~32k cacheable tokens recomputed every invocation. |
| No-op implementations pass gates | **Confirmed** | Bead `.6` close reason says "47 passed" — 6 of 7 test files are `untracked`. The close never runs pytest (it's a `br close` shell command, not a verification). |
| Error-type-aware escalation missing | **Confirmed** | Run 1's 5 final invocations ALL returned exit 1 from usage-limit. Ralph treated each as "General error — possibly API failure, auth issue, or tool crash" (`023942.log` tail) and burned 3 retry attempts for the completion report. A 429/limit-aware branch would have skipped the retries. |
| Tool-scoping per prompt type missing | **Inconclusive** | No evidence either way in this run. |
| Outcome verification (diff, exit code) should be post-condition | **Confirmed via bead .6** | If ralph post-checked `git ls-files tests/test_xero/__init__.py` it would have failed bead `.6` automatically. |

### Findings neither document predicted

**U1. Playlist pointer advances on a failed invocation.** Run 2 logged a 1-turn usage-limit error on the `#SMOKE_TEST` prompt and the pointer still moved. Run 3 then skipped SMOKE_TEST. This isn't a prompt-engineering issue — it's a bash-loop bug. Neither document scrutinized `lib/playlist.sh` state transitions; the run data surfaced it.

**U2. "Playlist not validated" warning is dismissible by silent default after 6s.** All three runs show:
```
WARNING: Playlist not validated.
  Continue anyway? [y/N] Proceeding without validation
```
The timestamps (`02:39:42` → `02:39:48`) show a 6-second gap. The prompt expects `[y/N]` but defaults to "proceed" when the TTY isn't interactive. For CI/tmux runs, the safety feature is effectively disabled — and that's how all 3 Chippie runs bypassed `playlist init`'s semantic audit, which would have caught both the commit-contradiction exposure and the lack of precondition wiring on `#SMOKE_TEST`. (`.ralph/config` can set `PLAYLIST_AUTO_CONTINUE=true`, but without an explicit opt-in, the default silent-proceed undermines the whole two-phase workflow.)

**U3. The completion-report prompt itself got caught by the usage-limit loop in run 1.** `023942.log` tail shows 3 retry attempts on report generation alone, all exit-1 from the same limit. A completion report should be skip-if-limit, not retry-on-limit — it's non-load-bearing telemetry. Currently it blocks session exit with 3 useless retries (lines `:final-70` to `:final`).

**U4. REFACTOR gate "accidentally" fixed the commit-leak from run 1.** Because `git diff --stat` picked up run 1's uncommitted changes as "session work", REFACTOR's first commit (`478a63a`) inadvertently captured `xero_invoice_service.py` and `xero_webhook_service.py` as new files — files that should have been committed by beads `.3` and `.5` respectively. This is a lucky accident masking the P1 bug. If the REFACTOR gate had used `git diff HEAD~1..HEAD` instead of `git diff <session_start>`, the leak would be fully visible in `git status` and beads `.3`/`.5` would have closed with no persisted artifacts whatsoever.

---

## 6. Calibration audit

- **Model choice:** sonnet default → opus on retry. Correct direction. `.6` benefited from opus (60-turn test-writing task). The REFACTOR and DOCUMENT gates were hand-pinned to opus (`@opus` annotations) and arguably did not need it — a 30-turn docs job at opus cost $1.35 vs. likely $0.30 on sonnet. **Suggest: don't default gates to opus; escalate only on retry.**
- **Turns:** over-provisioned by 7.7× (§5 table). Drop `--max-turns` default to 80; keep a per-prompt-type override hook.
- **Timeouts:** 300m is absurd. 10–15m per bead, 5m per gate, 2m per report.
- **Gate density:** 3 gates for 6 beads (50% — above the recommended 1:7 ratio) but the beads are all in the same subsystem, so the density feels right. The *order* is wrong: SMOKE_TEST should be **before** REFACTOR and DOCUMENT (verify behaviour before consolidating/documenting). It was, on paper — but SMOKE_TEST was skipped. The robustness question is "what happens if the verification gate is skipped" and the answer here was "REFACTOR and DOCUMENT run anyway against unverified code". That's a dependency the playlist cannot currently express.
- **Playlist ordering:** dependency-correct (rebase → review → invoice → webhook → UI → tests), but `.4` (UI) blocks `.6` (tests) in reality — you can't smoke-test a UI you haven't built. `.6`'s close mentions UI-related test files; without `.4` those tests can't cover the settings flow. Recommend: `br dep add chippie-jy1a.6 chippie-jy1a.4` should have been established before the playlist was written.

---

## 7. The one concrete change to make before next run

**Before any more playlist execution on this branch, fix the commit-contradiction template and re-run bead `.4` + the skipped `#SMOKE_TEST`.**

Template fix (in `/Users/admin/dev/ralph/templates/`):

1. In the playlist-mode branch-context template (the one that emits `023942.log:144`), replace `Commit directly on <branch>.` with `Commits on <branch> are made by the outer loop after close.` when `AUTO_COMMIT=false`. This is literally the rewrite `review.md §3.5` proposes.

2. Add a post-close hook in `lib/task_outcome.sh` that runs `git status --porcelain` after every `br close` and if it's non-empty, logs a loud warning and optionally flips the bead back to `in_progress` with a `POSSIBLE-LEAK` note. This is cheap, defensive, and would have caught §P1 on the first bead.

3. Fix `lib/playlist.sh` so the pointer only advances on `exit 0` from the invocation. A 1-turn usage-limit failure must NOT advance the line — that is what orphaned `jy1a.4` and skipped `#SMOKE_TEST`.

4. Change the `Continue anyway? [y/N]` prompt's non-interactive default to **N** (halt). Force the user to set `PLAYLIST_AUTO_CONTINUE=true` in `.ralph/config` or pass `--yes` explicitly when they really do want to skip validation. Today's silent-proceed is a footgun.

Then, and only then, run:
```
br update chippie-jy1a.4 --status open
./ralph --playlist xero-integration.playlist --resume-from chippie-jy1a.4
```
(or, if no `--resume-from` flag exists, rewrite the playlist so `.4` and the `#SMOKE_TEST` line come first in a new playlist file.)

The working-tree leaks (`application/*`, `tests/test_xero/`, the two Atlas migrations, and the two `*_ANALYSIS.md` scratch files) should be triaged by hand before that run — at minimum, the test files need committing under a `test(xero): add integration tests (chippie-jy1a.6)` commit so future sessions can `git log` and see `.6`'s work actually exists.
