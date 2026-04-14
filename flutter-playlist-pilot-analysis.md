# Ralph Playlist Pilot Report: Flutter Production Implementation

**Date:** 2026-04-05
**Session:** Chippie-ralph-20260405-002433
**Playlist:** flutter.playlist (51 items: 39 beads + 12 prompts)
**Runtime:** ~6 hours (00:24 → 06:23)
**Total Cost:** ~$76
**Operator:** Jeremiah Smith

---

## Executive Summary

The first full ralph playlist run transformed the Chippie Flutter app from a 6.5/10 prototype (broken sync, hardcoded URLs, missing DTOs, stub implementations) into an 8.5/10 production-ready application with 30+ screens, offline sync via PowerSync, a complete design system, and all six implementation epics substantially complete.

51 playlist items were processed: 39 bead tasks (implementation work) and 12 prompt injections (quality gates between epics). 38 of 39 beads were closed successfully. One bead (Deep Links) was intentionally released as blocked. The circuit breaker never triggered. Total cost was approximately $76 over 40 Claude invocations across 6 hours of autonomous execution.

This was also the inaugural run of ralph's playlist feature, which was designed and built specifically for this project. The pilot exposed 6 bugs (all fixed during the session or immediately after) and identified 13 improvement opportunities for future runs.

---

## Part 1: Flutter Implementation Results

### 1.1 Epic Completion Status

| Epic | ID | Status | Children | Completion |
|------|----|--------|----------|------------|
| Foundation — Fix Architecture & Align with Backend | chippie-ogz3 | Closed | 8/8 closed | 100% |
| Core Features — CRUD Parity with PWA | chippie-hweb | Closed | 6/6 closed | 100% |
| UI Alignment — Match PWA Design System | chippie-0wau | Closed | 6/6 closed | 100% |
| Extended Features — Calendar, Settings, Team, Billing, GST | chippie-b0tt | Closed | 6/6 closed | 100% |
| Offline & Sync — PowerSync Integration | chippie-7m1j | Open | 5/6 closed | 83% |
| Polish & Production — App Store Ready | chippie-p63z | Open | 6/7 closed | 85% |

**Remaining open items:**
- `chippie-7m1j.1` — Status is "done" instead of "closed" (semantic issue, work is complete)
- `chippie-p63z.3` — Deep Links released as blocked (requires Xcode/iOS environment not available on build server)

### 1.2 Build & Compile Status

| Check | Result |
|-------|--------|
| `flutter analyze` | Zero errors, zero warnings |
| `dart run build_runner build` | 375 outputs, clean (1 minor json_annotation version warning) |
| `flutter build appbundle` | Success — 53.4MB AAB |
| `flutter build ios --no-codesign` | Blocked — no Xcode on server |
| Hardcoded URLs (`grep macbook\|localhost`) | Zero matches |
| Debug prints (`grep "print(" lib/`) | Zero matches |

### 1.3 Architecture Assessment

**Score: 9/10**

The app follows Clean Architecture with four layers:

```
lib/
├── core/           Foundation (theme, routing, network, sync, providers, constants)
├── data/           Data layer (models/DTOs, repositories impl, datasources)
├── domain/         Domain layer (entities, repository interfaces)
└── presentation/   UI layer (screens, widgets, providers)
```

**Strengths:**
- Dependency inversion: domain defines interfaces, data implements them
- Riverpod state management with proper async handling (loading/error/data)
- PowerSync integration for offline-first with conflict resolution
- GoRouter with auth guards and 30+ deep-linkable routes
- Enterprise-grade networking: JWT refresh, certificate pinning, error categorization
- Design system with ThemeExtension for entity colors

**Minor gaps:**
- No explicit Result/Either types (uses throw/catch for error flow)
- No domain use cases layer (providers call repositories directly)
- No analytics/observability hooks prepared

### 1.4 Screens Implemented

**Authentication (4 screens)**
- Login, Register, Forgot Password, Business Selection

**Core CRUD (12 screens)**
- Dashboard (stats grid + recent activity)
- Client list, detail, form
- Quote list, detail, form + line items editor
- Job list, detail
- Invoice list, detail

**Extended Features (12 screens)**
- Calendar screen, event detail, event form
- Settings hub, business profile, tax settings, theme settings, sync settings
- Team list, invite member, join requests
- Billing, plans

**GST Tools (4 screens)**
- Calculator, threshold tracker, BAS quarterly, resources

**Other (4 screens)**
- Notification list
- Pending operations (sync queue)
- Business setup (onboarding)
- Guided tour

**Total: 36 screens**

### 1.5 Reusable Widgets (19 components)

| Widget | Purpose |
|--------|---------|
| `app_shell.dart` | Persistent bottom nav + drawer scaffold |
| `status_badge.dart` | Semantic status colors matching PWA |
| `stat_card.dart` | Dashboard metrics with gradient backgrounds |
| `client_card.dart` | Client list item |
| `quote_card.dart` | Quote list item |
| `job_card.dart` | Job list item |
| `invoice_card.dart` | Invoice list item |
| `entity_sync_badge.dart` | Per-entity sync status indicator |
| `sync_status_indicator.dart` | Animated sync status with pending count |
| `offline_banner.dart` | Dismissible offline notification |
| `error_state.dart` | Error display with retry action |
| `empty_state.dart` | Empty state with CTA button |
| `skeleton_card.dart` | Loading shimmer placeholder |
| `currency_input.dart` | Amount input with formatting |
| `client_selector.dart` | Searchable client dropdown |
| `notes_section.dart` | Notes display + attachment management |
| `attachment_list.dart` | File attachment display |
| `quote_acceptance_dialog.dart` | Accept/decline quote modal |
| `line_items_editor.dart` | Inline line item CRUD |

### 1.6 Design System Alignment with PWA

| Token | PWA Value | Flutter Value | Match |
|-------|-----------|---------------|-------|
| Primary | #007bff | AppColors.primary | Yes |
| Success | #10b981 | AppColors.success | Yes |
| Warning | #f59e0b | AppColors.warning | Yes |
| Danger | #ef4444 | AppColors.danger | Yes |
| Info | #3b82f6 | AppColors.info | Yes |
| Clients entity | #007bff (blue) | EntityColors.clients | Yes |
| Quotes entity | #f59e0b (yellow) | EntityColors.quotes | Yes |
| Jobs entity | #10b981 (green) | EntityColors.jobs | Yes |
| Invoices entity | #3b82f6 (cyan) | EntityColors.invoices | Yes |
| Card radius | 10px | BorderRadius.circular(10) | Yes |
| Card shadow | 0 2px 15px rgba(0,0,0,0.08) | Matching BoxShadow | Yes |
| Touch targets | 44px minimum | 44px minimum | Yes |

### 1.7 Test Coverage

**12 test files implemented:**

| Category | Files | Coverage |
|----------|-------|----------|
| Entity unit tests | 4 (client, quote, job, invoice) | Status transitions, business rules |
| Provider unit tests | 4 (clients, quotes, jobs, invoices) | State management, async handling |
| Repository tests | 2 (client, quote) | CRUD with fake implementations |
| Sync tests | 1 (sync_queue) | Queue operations |
| Integration tests | 1 (quote_lifecycle) | Full create → accept → job → invoice flow |

**Score: 6/10** — Solid unit test foundation but limited widget/screen tests and no offline scenario tests.

### 1.8 Security

| Check | Status |
|-------|--------|
| JWT stored in flutter_secure_storage | Yes |
| Token refresh before expiry (1-hour proactive) | Yes |
| Certificate pinning (configurable) | Yes |
| Auth guard on all routes | Yes (GoRouter redirect) |
| No secrets in codebase | Yes |
| HTTPS-only enforcement | Yes |
| Biometric auth option | Scaffolded |

### 1.9 Remaining Work

| Item | Priority | Effort |
|------|----------|--------|
| Close chippie-7m1j.1 (status "done" → "closed") | P0 | 1 command |
| Update json_annotation to ^4.9.0 | P0 | 1 line |
| Complete chippie-p63z.3 (Deep Links) when Xcode available | P1 | 1 bead |
| Add widget tests for critical screens | P1 | 10 tests |
| Add offline scenario tests | P1 | 5 tests |
| iOS build signing configuration | P1 | Manual config |
| Localization (hardcoded English strings) | P2 | Future epic |
| Dark mode theme | P2 | Future epic |
| Accessibility audit | P2 | Future epic |

---

## Part 2: Ralph Playlist Performance

### 2.1 Session Metrics

| Metric | Value |
|--------|-------|
| Total loops | 40 |
| Productive loops | 38 (95% utilization) |
| Skipped (already closed) | 2 |
| Released (blocked) | 1 |
| Circuit breaker events | 0 |
| Retries | 0 (in this session) |
| Exit reason | Playlist complete |
| Average loop time | ~9 minutes |
| Fastest loop | ~1 minute (prompt review) |
| Slowest loop | ~35 minutes (test coverage, 94 turns) |

### 2.2 Cost Breakdown

| Category | Items | Cost | % |
|----------|-------|------|---|
| Sonnet bead tasks | 31 | ~$44 | 58% |
| Opus review prompts | 8 | ~$14 | 18% |
| Haiku sub-operations | — | ~$8 | 11% |
| Report generation | 1 | ~$2 | 3% |
| Wasted (re-reads, exploration) | — | ~$8 | 10% |
| **Total** | **40** | **~$76** | **100%** |

**Prompt caching performance:**
- Cache hit ratio: 94.8%
- Cache reuse multiplier: 28x
- Estimated savings from caching: ~$48 (would have cost ~$124 without)

### 2.3 Turn Distribution

| Range | Tasks | Notes |
|-------|-------|-------|
| 1-10 turns | 3 | Quick prompt reviews, report generation |
| 11-30 turns | 6 | Focused implementation tasks |
| 31-50 turns | 12 | Standard implementation tasks |
| 51-100 turns | 15 | Complex multi-file implementations |
| 100+ turns | 5 | Large features (test coverage hit 94 turns) |

**Median: ~35 turns per task. Target for future runs: 20-40.**

### 2.4 Most Expensive Tasks

| Task | Bead | Turns | Cost | Why |
|------|------|-------|------|-----|
| Test Coverage | chippie-p63z.6 | 94 | $4.96 | 219 tests to write across 12 files |
| App Store Prep | chippie-p63z.7 | 75+ | $4.96 | Build signing, assets, Firebase config |
| Extended Features Review | @opus prompt | 46 | $3.58 | Deep review of 6 feature areas |
| PowerSync Review | @opus prompt | 71 | $3.01 | Verified connector, sync paths, conflicts |
| Epic 2 Quality Review | @opus prompt | 60 | $2.36 | Reviewed all CRUD implementations |

### 2.5 Token Efficiency Issues

**File re-reading across tasks:**
- 839 total Read operations across 41 invocations
- 183 unique files read
- Top files read 18-19 times each: pubspec.yaml, main.dart, app_router.dart, api_service.dart
- Each new Claude invocation starts fresh — no context carries forward from the previous bead

**Agent spawning overhead:**
- 33 Explore agent spawns across the session
- 80% of tasks spawned at least one agent for "exploring the codebase"
- Agents are ~6x slower than direct Bash/Grep for file discovery
- Estimated overhead: ~$7.50

**Root cause:** Each bead task tells Claude to "search the codebase before assuming anything." Claude dutifully explores from scratch every time, re-reading the same foundational files. There is no mechanism to pass a project summary or prior task's output to the next task.

### 2.6 Bugs Discovered During Pilot

| Bug | ID | Severity | Status | Impact |
|-----|----|----------|--------|--------|
| `local` keyword in main loop body | ralph-58m.11 | P0 | Fixed | Crashed on first prompt injection |
| Model not restored on invoke failure | ralph-58m.12 | P1 | Fixed | Next bead ran on wrong model |
| Dry-run persists playlist position | ralph-58m.10 | P1 | Filed | Required --reset before real runs |
| Playlist advances before task completion | ralph-58m.15 | P0 | Fixed | Skipped unfinished beads on resume |
| Max turns hardcoded to 50 | — | P0 | Fixed | Complex tasks hit ceiling and failed |
| Skip-closed-beads on resume | ralph-58m.14 | P1 | Implemented | Prevents re-running completed work |

### 2.7 What the @opus Review Gates Found

| Review Point | Issues Found | Actions Taken |
|-------------|-------------|---------------|
| Epic 1 completion | Stale codegen (freezed files outdated) | Regenerated via build_runner |
| UI alignment | — | Confirmed colors match PWA spec |
| Post-client CRUD | Unused test imports | Removed |
| Mid-Epic 2 | Mockito generated code warnings | Suppressed in analyzer config |
| Epic 2 completion | — | Verified navigation flow works |
| Epic 4 completion | Missing Firebase config fallback | Made plugin conditional |
| Post-PowerSync sync cleanup | Old sync imports still referenced | Cleaned up |
| PowerSync review | — | Confirmed connector calls correct endpoint |
| Mid-Polish | JDK 17 incompatibility with Gradle 8.12 | Switched to JDK 21 |
| Final readiness | Android build succeeds, iOS blocked (no Xcode) | Documented |

**Verdict: The @opus checkpoints caught codegen and build issues but completely missed the real problem — the app doesn't work against the actual backend.** See Part 2.8.

---

## 2.8 CRITICAL FAILURE: Zero Real API Validation

**The most significant finding of this pilot: the playlist produced an app that cannot complete a basic login against the real backend.** Not one curl test, not one API integration check, not one end-to-end validation was performed during the entire 6-hour run. Every bead task and every @opus review operated in isolation from the running backend.

### Issues Found on First Manual Test

| # | Issue | Severity | Root Cause | Would Curl Have Caught It? |
|---|-------|----------|------------|---------------------------|
| 1 | Blank screen on launch (web) | P0 | `Firebase.initializeApp()` crashes with no web config | Yes — `flutter run -d chrome` + check console |
| 2 | `NotificationService` crash on web | P0 | `FirebaseMessaging.instance` in constructor, no web guard | Yes — same as above |
| 3 | Default API URL pointed at a fabricated URL | P0 | `api.chippie.com.au` — a domain that doesn't exist — instead of `localhost:8080`. Claude invented a production URL. | Yes — `curl` to default URL fails (domain doesn't resolve) |
| 4 | CORS preflight blocked | P1 | Middleware intercepts OPTIONS before Flask-CORS responds | Yes — `curl -X OPTIONS` with Origin header |
| 5 | Login endpoint not in PUBLIC_ROUTES | P0 | `api_auth.login` missing from middleware whitelist | Yes — `curl -X POST /api/v1/auth/login` returns 401 |
| 6 | `/businesses/my-businesses` returns 404 | P0 | Endpoint doesn't exist in backend API | Yes — `curl -H "Authorization: Bearer ..." /api/v1/businesses/my-businesses` returns 404 |

**Every single one of these issues would have been caught by a basic curl test against the running backend.** The playlist spent $14 on @opus reviews that checked `flutter analyze` output and compared CSS colors, but never once verified that the app can talk to the server it was built to talk to.

### What Should Have Happened

The playlist should have included **API integration validation prompts** at key checkpoints. These are not unit tests — they're live curl tests against the running backend that verify the Flutter app's assumptions about the API are correct.

### Required Validation Prompts for Future Playlists

**After Foundation epic (auth + API client):**
```
>@opus VALIDATION: Test the Flutter app's API integration against the live backend.
1. Verify backend is running: curl -s http://localhost:8080/api/v1/auth/login -X OPTIONS -I
2. Test login: curl -s -X POST http://localhost:8080/api/v1/auth/login -H "Content-Type: application/json" -d '{"username": "first@last.com", "password": "fourfour"}'
3. Extract token from response, then test authenticated endpoint: curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/clients
4. Test every endpoint the Flutter API service defines — verify they exist and return expected shapes.
5. If ANY curl test fails, STOP and fix the issue before proceeding. Do not close this task until all endpoints return valid responses.
6. Check CORS: curl -s -X OPTIONS http://localhost:8080/api/v1/auth/login -H "Origin: http://localhost:3000" -H "Access-Control-Request-Method: POST" -I
7. Verify the Flutter app's default API URL matches the backend: grep "defaultValue" flutter/lib/core/constants/api_constants.dart
```

**After Core CRUD epic:**
```
>@opus VALIDATION: Test all CRUD endpoints the Flutter app calls.
1. Login and get token
2. GET /clients — verify response shape matches ClientModel fields
3. POST /clients — create a test client, verify response
4. GET /quotes — verify response shape matches QuoteModel fields
5. POST /quotes — create test quote
6. POST /quotes/{id}/accept — verify creates job + invoice
7. GET /jobs — verify response
8. POST /invoices/{id}/mark-paid — verify
9. For EACH endpoint in api_service.dart, run the corresponding curl. Document any 404s or schema mismatches.
```

**After each epic:**
```
>@opus VALIDATION: Run the Flutter app on web/desktop and verify:
1. flutter run -d chrome (or macos) — app launches without blank screen
2. Login screen appears and accepts credentials
3. After login, dashboard loads with real data from backend
4. Navigate to each screen — no crashes, no blank pages
5. If any screen crashes, check the console error and fix it.
```

### Why the Existing Tests Didn't Catch This

The 12 test files written by the playlist are **unit tests with mocked dependencies**. They verify:
- Entity status transitions work in isolation
- Provider state management logic is correct
- Repository methods call the right functions

They do NOT verify:
- The API endpoints actually exist on the backend
- The request/response schemas match between Flutter DTOs and backend serializers
- Authentication flows work end-to-end
- The app can start up and render without crashing
- CORS, middleware, and routing are configured correctly

**Unit tests prove the code is internally consistent. They say nothing about whether it works with the real system.**

### Recommendation: Mandatory API Validation Phase

Every ralph playlist that builds a client for an existing backend MUST include:

1. **Pre-flight check** (before any implementation): Curl every API endpoint the client will use. Document the actual response schemas. Compare against the DTOs being built.

2. **Post-foundation validation** (after auth + API client): Live login test. Token extraction. Authenticated request test. CORS test.

3. **Post-CRUD validation** (after entity screens): Full CRUD curl cycle for every entity. Schema comparison between API response and Flutter model.

4. **Launch test** (after each epic): Actually run the app and verify it renders, logs in, and shows data.

This should be built into ralph as a **playlist template pattern**, not left to the playlist author to remember. When `--playlist` is used with a client-server project, ralph should warn if no curl/validation prompts are present.

### 2.9 CRITICAL FAILURE: No Completeness Scanning

A third validation category was entirely absent: **scanning for unfinished work**.

The Flutter app's authentication API blueprint contained multiple `TODO` comments and stub implementations — code that Claude wrote during bead tasks and then moved on from without resolving. The playlist never checked for this.

#### The Problem

Claude's workflow during a bead task often looks like:
1. Read existing code
2. Implement the main feature
3. Write `// TODO: handle edge case X` for things it runs out of turns for
4. Close the bead with "VERIFY: ..." notes
5. Ralph moves to next bead — TODOs stay forever

The @opus review prompts checked `flutter analyze` (syntax) and compared colors (design), but never ran `grep -rn "TODO" lib/`. The TODOs accumulated silently across 39 tasks.

#### Three Validation Categories

The playlist had only one of three required validation types:

| Category | What It Checks | Playlist Had It? | Cost to Add |
|----------|---------------|-------------------|-------------|
| **Syntax validation** | Does it compile? (`flutter analyze`) | Yes — every checkpoint | Already included |
| **API integration validation** | Does it work? (curl against real backend) | No — zero curl tests | ~$2-3 per checkpoint |
| **Completeness validation** | Is it finished? (TODO/stub scan) | No — zero grep scans | ~$1-2 per checkpoint |

#### Required Completeness Prompt

At every epic boundary:
```
> Scan for incomplete work: grep -rn "TODO\|FIXME\|HACK\|STUB\|stub\|placeholder\|not yet\|not implemented" flutter/lib/. For each match found in code written during this playlist, either implement it fully or remove it with a justification. Do not leave TODOs in shipped code.
```

### 2.10 Dynamic Playlist Injection — Review Agents That Create Work

The validation prompts described above may discover issues too large for a single prompt invocation to fix. For example, an API validation prompt might find 8 endpoints returning wrong schemas, 3 missing entirely, and CORS broken — that's not a "fix it and move on" situation.

#### The Pattern: Review → Discover → Inject → Continue

When a review/validation prompt discovers significant work, it should be able to **inject new bead tasks and prompt lines directly into the playlist file** after the current line. Ralph reads the playlist line-by-line from the file on each loop iteration — new lines inserted after the current position are picked up automatically on the next `playlist_next()` call.

#### How It Works

The review prompt's instructions would include:

```
>@opus VALIDATION: Test auth against live backend.
1. curl POST /api/v1/auth/login with test creds. Verify token returned.
2. curl GET /api/v1/clients with token. Verify response matches ClientModel.
3. ... (test all endpoints)

IF you find issues that require more than quick fixes:
- Create beads for each issue: br create --title="Fix: /businesses/my-businesses 404" --type=bug --priority=0
- Insert the new bead IDs into flutter.playlist IMMEDIATELY AFTER this line
- Also insert any necessary prompt lines (e.g., re-validation after fixes)
- Ralph will pick up the injected lines on the next loop iteration

Example: if you find 3 issues, insert into the playlist:
  chippie-XXXX
  chippie-YYYY
  chippie-ZZZZ
  > Re-validate: curl all previously-failing endpoints. All must pass.
```

#### Execution Flow

```
Playlist state before review:
  Line 20: >@opus VALIDATION: Test auth     ← currently executing
  Line 21: chippie-hweb.1                   ← next bead

Review agent finds 3 issues, injects lines:
  Line 20: >@opus VALIDATION: Test auth     ← done
  Line 21: chippie-NEW1                     ← INJECTED: fix CORS
  Line 22: chippie-NEW2                     ← INJECTED: fix login endpoint
  Line 23: chippie-NEW3                     ← INJECTED: add missing route
  Line 24: > Re-validate auth endpoints     ← INJECTED: verify fixes
  Line 25: chippie-hweb.1                   ← original next bead (shifted down)

Ralph's next playlist_next() reads line 21 → picks up chippie-NEW1.
```

#### Why This Works Without Ralph Code Changes

Ralph reads the playlist file fresh on each `playlist_next()` call via the `PLAYLIST_LINES` array. If the array is reloaded after a `>` prompt modifies the file (or if we switch to reading the file directly instead of the cached array), injected lines appear naturally. The `playlist_line` counter still points to the correct position because new lines are inserted *after* the current line.

One small ralph change needed: reload the playlist file after each `>` prompt execution, in case the prompt modified it. This is a 3-line change in `playlist_execute_prompt()`:

```bash
# After invoke_claude returns for a prompt:
playlist_reload  # re-read file in case the prompt injected lines
```

#### What This Enables

- **Self-healing playlists**: Review agents discover problems and schedule their own fixes
- **Adaptive execution**: The playlist grows organically based on what's actually found
- **Bounded scope per task**: Complex discoveries become multiple focused beads, not one giant prompt
- **Audit trail**: Every injected bead is tracked in beads_rust with full history
- **No human intervention**: The playlist keeps running — review finds issues, creates beads, injects them, ralph executes them, next review verifies

This is the key architectural insight from the pilot: **the playlist should be a living document that review agents can modify, not a static script.**

### 2.11 The Validation Dilemma: Inner Loop vs Outer Loop

The issues described in Sections 2.8, 2.9, and 2.10 expose a fundamental architectural question about where validation, enforcement, and self-healing should live in the ralph system.

#### The Two-Loop Architecture

```
┌─────────────────────────────────────────────────┐
│  OUTER LOOP (ralph — deterministic bash)         │  We control this. Editable. Repeatable.
├─────────────────────────────────────────────────┤
│  INNER LOOP (Claude — dynamic AI)                │  Controlled only by prompts. Non-deterministic.
└─────────────────────────────────────────────────┘
```

Ralph is a dumb for-loop by design (see PHILOSOPHY.md). All intelligence lives in Claude. Ralph's job is task selection, progress tracking, and circuit breaking — not decision-making.

But the pilot revealed that **Claude cannot be trusted to validate its own work**. It wrote 39 tasks worth of code, passed `flutter analyze` on every checkpoint, and produced an app that cannot log in. The inner loop optimised for what it was measured on (does it compile?) and ignored what it wasn't measured on (does it work?).

#### The Dilemma

Validation requires both **judgment** (what to check, how to interpret results) and **enforcement** (making sure checks actually happen). These pull in opposite directions:

- **Enforcement belongs in the outer loop** — deterministic, guaranteed to run, not skippable by Claude
- **Judgment belongs in the inner loop** — adaptive, context-aware, can diagnose and fix

If we put validation entirely in the inner loop (as `>` prompts), it's optional — the playlist author might forget it, or Claude might skip it. If we put it entirely in the outer loop, it's rigid — ralph can run `curl` but can't interpret why a response is wrong or decide how to fix it.

#### The Foundation Gap: Playlist Creation Has No Process

Before we can solve where validation lives, we must acknowledge a prior gap: **there is no defined process for creating playlists.**

The `flutter.playlist` used in this pilot was hand-crafted in a single Claude conversation. There is:
- No slash command or skill for playlist creation
- No documentation of the playlist format (what `>` means, what `@opus` does)
- No specification of what a playlist must contain
- No template system
- No validation of playlist quality before execution

If someone starts a fresh Claude session and says "create a ralph playlist for X," Claude has no idea what the format is. The quality of the playlist — including whether it contains validation gates — depends entirely on the authoring session's context.

This means the dependency chain for fixing validation is:

```
1. Define how playlists are created (authoring process)
   └─ 2. Define what rules the creation process must follow (quality gates)
      └─ 3. Define how the outer loop enforces rules at runtime (gate execution)
         └─ 4. Define how the inner loop responds to gate failures (self-healing)
```

The pilot skipped step 1, partially addressed step 2 (via hand-written `>` prompts), didn't do step 3, and didn't do step 4.

#### Proposed Architecture: Hybrid Gates

The solution splits responsibility across three layers — not two:

```
┌─────────────────────────────────────────────────────────────────┐
│  PLAYLIST (authored via skill/template with enforced structure)  │  ← static plan + quality rules
├─────────────────────────────────────────────────────────────────┤
│  RALPH (outer loop — deterministic gates)                        │  ← enforcement
├─────────────────────────────────────────────────────────────────┤
│  CLAUDE (inner loop — adaptive response)                         │  ← intelligence
└─────────────────────────────────────────────────────────────────┘
```

**Layer 1 — Playlist Authoring** answers: what gets built and in what order?

Playlists are created through a defined process that enforces structure. Options (not mutually exclusive):

| Option | How It Works | Enforcement Level |
|--------|-------------|-------------------|
| **Slash command** (`/create-playlist`) | Claude skill with format spec, project context, mandatory gate rules baked into the skill prompt | High — skill prompt forces Claude to include gates |
| **CLAUDE.md documentation** | Playlist format documented so any Claude session can author one | Medium — depends on Claude reading and following docs |
| **`ralph --playlist-init`** | Generates skeleton from template with gates pre-populated | Medium — human fills in beads, gates are pre-written |
| **`ralph --generate-playlist`** | Ralph invokes Claude to generate playlist from beads automatically | High — ralph controls the generation prompt |

Recommendation: **slash command (`/create-playlist`) as primary, `ralph --playlist-init` as fallback.** The slash command gives Claude the format spec and the mandatory quality rules. The template gives a starting point for manual authoring.

**Layer 2 — Ralph Gate Enforcement** answers: is the work actually correct?

Ralph gets a new concept: **gates**. A gate is a script that ralph runs *itself* — deterministically, no Claude, no prompts. It's a bash script with exit codes.

```bash
# ralph-gates.sh — deterministic validation, runs automatically
#!/usr/bin/env bash
set -e

echo "=== GATE: Syntax ==="
cd flutter && flutter analyze 2>&1 | tail -5
[[ $(flutter analyze 2>&1 | grep -c "error •") -eq 0 ]] || exit 1

echo "=== GATE: Completeness ==="
TODO_COUNT=$(grep -rn "TODO\|FIXME\|STUB" lib/ 2>/dev/null | wc -l)
echo "TODOs found: $TODO_COUNT"
[[ $TODO_COUNT -lt 20 ]] || exit 1

echo "=== GATE: API Smoke Test ==="
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"first@last.com","password":"fourfour"}' \
  | jq -r '.data.access_token // empty')
[[ -n "$TOKEN" ]] || { echo "FAIL: login returned no token"; exit 1; }

curl -sf -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/v1/clients > /dev/null \
  || { echo "FAIL: GET /clients failed"; exit 1; }

echo "=== ALL GATES PASSED ==="
```

Configuration in `.ralph.conf`:
```bash
GATE_AFTER_EVERY=5          # Run gates every N beads
GATE_AFTER_EPIC=true        # Run gates when parent epic changes
GATE_SCRIPT="./ralph-gates.sh"
```

Gates are:
- **Deterministic** — same script, same checks, every time
- **Project-specific** — the gate script is authored per project, not baked into ralph
- **Non-AI** — ralph runs bash, checks exit codes. No Claude invocation, no token cost
- **Mandatory** — if `GATE_SCRIPT` is set, ralph runs it. The playlist author can't skip it
- **Fast** — a gate script runs in seconds (curl + grep), not minutes (Claude invocation)

**Layer 3 — Claude Adaptive Response** answers: what do we do when a gate fails?

When a gate script exits non-zero, ralph invokes Claude with the gate output as context:

```
## Gate Failure
The deterministic validation gate failed after bead chippie-ogz3.8.

### Gate output:
=== GATE: API Smoke Test ===
FAIL: login returned no token
curl response: {"error": "Authentication required", "message": "Please log in"}

### Your Task
Diagnose and fix this failure. The gate script is at ./ralph-gates.sh.

If the fix requires multiple steps:
1. Create beads for each issue: br create --title="Fix: ..." --type=bug --priority=0
2. Insert the bead IDs into the playlist file AFTER the current line
3. Ralph will execute them before continuing the playlist
4. After fixes, the gate will re-run automatically
```

Claude decides **how** to fix. Ralph decides **whether** to run the check and **whether** the fix worked (by re-running the gate after the remediation beads).

#### How This Changes the Playlist

Playlists become simpler. Mechanical validation (`curl`, `grep`, `flutter analyze`) moves to the gate script. `>` prompts return to their original purpose — strategic review and plan adjustment:

```
# flutter.playlist — validation handled by ralph-gates.sh automatically

chippie-ogz3.1
chippie-ogz3.3
chippie-ogz3.2
chippie-ogz3.4
chippie-ogz3.5
# ← ralph auto-runs gates here (5 beads done)
# if gate fails → Claude diagnoses → creates fix beads → injects into playlist

chippie-ogz3.6
chippie-ogz3.7
chippie-ogz3.8

# Strategic review — not validation, that's handled by gates
>@opus Review Epic 1. Check remaining bead descriptions for accuracy.
Update any that reference changed patterns or file paths.
```

#### How Each Gap Is Now Handled

| Gap from Pilot | Layer 1 (Authoring) | Layer 2 (Gates) | Layer 3 (Claude) |
|---|---|---|---|
| No API testing | Slash command mandates gate script exists | Gate script runs curl smoke tests | Claude fixes endpoints that fail |
| TODOs left in code | — | Gate script greps and fails above threshold | Claude implements or removes TODOs |
| App doesn't launch | — | Gate script runs `flutter build` | Claude fixes build errors |
| CORS broken | — | Gate script sends OPTIONS with Origin header | Claude fixes middleware |
| Schema mismatch | — | Gate script curls + compares to DTO fields | Claude updates DTO or API route |
| No completeness scan | Slash command includes completeness gate | Gate script enforced by ralph | Claude resolves incomplete items |
| Playlist missing validation | Slash command + dry-run warnings | Gates run regardless of playlist content | — |

#### Self-Healing Flow

```
Ralph executes bead chippie-ogz3.7 (task completes, bead closed)
  │
  ├─ Bead count = 5 → trigger gate
  │
  ├─ OUTER LOOP: Run ralph-gates.sh
  │   ├─ GATE: Syntax .......... PASS
  │   ├─ GATE: Completeness .... PASS (12 TODOs, under threshold)
  │   └─ GATE: API Smoke Test .. FAIL (login returns 401)
  │
  ├─ OUTER LOOP: Invoke Claude with gate failure context
  │   │
  │   ├─ INNER LOOP: Claude reads gate output + middleware.py
  │   ├─ INNER LOOP: Diagnoses api_auth.login not in PUBLIC_ROUTES
  │   ├─ INNER LOOP: Fixes middleware.py directly (quick fix)
  │   ├─ INNER LOOP: Also finds /businesses/my-businesses missing
  │   ├─ INNER LOOP: Creates bead: br create --title="Add /businesses/my-businesses endpoint"
  │   └─ INNER LOOP: Injects bead ID into playlist after current line
  │
  ├─ OUTER LOOP: Reload playlist (picks up injected bead)
  ├─ OUTER LOOP: Execute injected bead
  ├─ OUTER LOOP: Re-run ralph-gates.sh
  │   ├─ GATE: Syntax .......... PASS
  │   ├─ GATE: Completeness .... PASS
  │   └─ GATE: API Smoke Test .. PASS ✓
  │
  └─ OUTER LOOP: Continue to next playlist line
```

Steps 1-3 are deterministic (outer loop). Steps 4-9 are adaptive (inner loop). Steps 10-14 are deterministic again. The outer loop **guarantees** the gate runs. The inner loop **decides** how to fix failures. The gate **re-runs** after fixes to verify they worked. No human intervention needed.

#### What This Means for Ralph's Philosophy

This doesn't violate "the bitter lesson." Ralph is still a dumb for-loop. Gates are just bash scripts with exit codes — the same level of complexity as the circuit breaker. The intelligence (diagnosis, fix decisions, bead creation) stays in Claude. Ralph just added a `if gate_fails; then invoke_claude_with_failure; fi` branch to the loop.

### 2.12 Upstream Problem: Bead Descriptions Built on Fabricated Reality

The runtime validation gaps (Sections 2.8–2.11) address what happens *during* playlist execution. But the pilot exposed an equally critical problem *upstream*: **the bead descriptions themselves were written against an imaginary codebase.**

#### What Happened

The 39 bead tasks were authored in a planning session where Claude:
- Assumed the backend login response returns `user` and `businesses` objects — it doesn't
- Invented a production URL (`api.chippie.com.au`) that has never existed
- Referenced `/businesses/my-businesses` as an endpoint — it's a 404
- Described the authentication flow based on what seemed reasonable, not what the backend actually implements
- Specified fields for DTOs based on a model inventory, but didn't verify the API serializers actually return those fields

Claude was planning against its *understanding* of the project, not against the *actual* project. The planning session read some backend files but never ran `curl` against the live API to verify what endpoints exist and what they return.

This is not a runtime validation failure — it's a **planning failure**. The beads were wrong before the playlist even started. No amount of runtime gates can fix a bead that says "use the `/businesses/my-businesses` endpoint" when that endpoint doesn't exist.

#### The Pattern: Fabricated Assumptions in AI Planning

When Claude plans implementation work, it tends to:

1. **Read code structure** — scans models, routes, file names. Gets the broad picture right.
2. **Infer behavior** — assumes endpoints return what the models describe. Often wrong because serializers, middleware, and route registration can differ from what models suggest.
3. **Invent what's missing** — if it can't find a URL, it fabricates a plausible one. If it can't find a response schema, it assumes a reasonable one. It does not flag these as assumptions — it states them as facts in the bead description.
4. **Never verify** — at no point during planning does it `curl` the running backend or check the actual route table. It plans from static code reading alone.

This is the AI equivalent of an architect designing plumbing from the floor plan without checking where the water mains actually are.

#### Required: Bead Authoring Quality Gates

The bead creation process — whether via a slash command, a planning session, or `ralph --generate-playlist` — must enforce verification against the real system. This is a separate concern from runtime gates. Runtime gates catch implementation bugs. Authoring gates catch planning bugs.

**Rule 1: Every API endpoint referenced in a bead must be verified by curl.**

Before a bead description can reference an endpoint, the authoring agent must:
```bash
# Verify the endpoint exists and document its actual response
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"first@last.com","password":"fourfour"}'
```

If the endpoint returns a 404, the bead must either:
- Reference a different, working endpoint
- Include a prerequisite task to create the missing endpoint
- Flag the gap explicitly: "NOTE: This endpoint does not exist yet. Backend task required."

**Rule 2: Every DTO field list must come from actual API responses, not model inspection.**

The planning agent must not read `application/models/tenant/quote.py` and assume the API returns all those fields. It must `curl` the actual endpoint and use the real response shape:

```bash
# Get actual response shape — this is the source of truth for the DTO
TOKEN=$(curl -s ... | jq -r '.data.access_token')
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/quotes | jq '.[0]'
```

If the response shape differs from the model (which it often does — serializers filter fields, middleware transforms data), the bead description must reflect reality, not the model.

**Rule 3: Assumptions must be flagged, not stated as facts.**

If the authoring agent cannot verify something (backend not running, endpoint requires special state), it must mark it:

```
# Good — flagged assumption
ASSUMPTION: Login response includes user object. VERIFY before implementing.

# Bad — stated as fact (what happened in our pilot)
Backend returns: { access_token, user, businesses }
```

**Rule 4: Backend changes must be tracked as separate beads.**

If implementing a Flutter feature requires a backend change (new endpoint, modified response schema, middleware update), that must be a separate bead with a dependency:

```bash
br create --title="Backend: Add /businesses/my-businesses endpoint" --type=task
br create --title="Flutter: Fetch businesses after login" --type=task
br dep add <flutter-bead> <backend-bead> --type=blocks
```

The pilot created Flutter beads that assumed backend endpoints exist without creating the backend beads to make them exist.

#### Implementation: Two Paths for Playlist Creation

Playlists can be created externally (by a human or Claude session) or internally (by ralph itself). Both paths are supported. The key difference is validation — ralph-created playlists are validated by construction, while external playlists go through an optional-but-prompted validation step.

**Path A: External Creation (flexible, any tool)**

The user creates the playlist however they want — in a Claude session, by hand, via a slash command, or generated by a script. Ralph doesn't care how the file was made. But when `ralph --playlist FILE` is invoked, ralph checks for a validation marker in the file:

```
# ✓ VALIDATED: 2026-04-05T12:00:00 by ralph playlist init
```

If this marker is absent, ralph prompts the user before running:

```
[ralph] WARNING: Playlist not validated.
  Missing: quality gates, API verification, completeness scan
  Run 'ralph playlist init flutter.playlist' to validate and add quality gates.

  Continue anyway? [y/N]
```

- **y** (or Enter) — continues immediately, no blocking
- **n** — offers to run validation inline:
  ```
  [ralph] Run 'ralph playlist init flutter.playlist' now? [Y/n]
  ```
  - **Y** — runs the init process (see below), then continues with the validated playlist
  - **n** — exits

This keeps ralph non-blocking for quick ad-hoc runs while surfacing the gap clearly.

**Path B: Ralph-Created Playlists (`ralph playlist create`)**

Ralph generates the playlist directly from beads:

```bash
# From specific bead IDs
ralph playlist create chippie-ogz3.1 chippie-ogz3.3 chippie-ogz3.2 -o flutter.playlist

# From an epic (all children in dependency order)
ralph playlist create --epic chippie-ogz3 -o flutter.playlist

# From multiple epics
ralph playlist create --epic chippie-ogz3 --epic chippie-hweb --epic chippie-0wau -o flutter.playlist
```

Ralph invokes Claude with a structured prompt that includes:
- The bead list and their descriptions (from `br show --json`)
- The project's `.ralph.conf` (gate script path, model preferences)
- Mandatory rules for playlist construction (see below)
- The current state of the codebase (key files, running services)

The creation prompt enforces:

```
## Mandatory Rules for Playlist Construction

1. VERIFY EVERY API ENDPOINT referenced in any bead description:
   - curl each endpoint against the live backend
   - Document the actual response shape
   - If an endpoint returns 404: create a backend bead as prerequisite,
     add it to the playlist before the bead that needs it
   - If an endpoint returns a different schema than the bead describes:
     update the bead description with br update to match reality

2. VERIFY EVERY DTO/MODEL field list:
   - Base field lists on actual curl responses, not model file inspection
   - If you cannot verify (backend not running), prefix with ASSUMPTION:

3. FLAG FABRICATED INFORMATION:
   - Never invent URLs, endpoint paths, or response schemas
   - If unsure, curl it. If you can't curl it, flag it.

4. INCLUDE QUALITY GATES:
   - After every 5 beads: completeness scan prompt (grep TODO/FIXME)
   - After each epic boundary: @opus review prompt
   - After auth/API foundation: API smoke test prompt with actual curl commands
   - After CRUD implementation: entity CRUD curl cycle

5. TRACK BACKEND DEPENDENCIES:
   - If a Flutter bead requires a backend change, create the backend bead first
   - Add dependency: br dep add <flutter-bead> <backend-bead> --type=blocks
   - Include the backend bead in the playlist before the Flutter bead

6. MARK AS VALIDATED:
   - Add "# ✓ VALIDATED: <timestamp> by ralph playlist create" as the first line
```

Ralph-created playlists are validated by construction — the creation prompt forces verification.

**Path C: Validate an Existing Playlist (`ralph playlist init`)**

For externally-created playlists, `ralph playlist init` runs a validation and augmentation pass:

```bash
ralph playlist init flutter.playlist
```

This invokes Claude with:
- The existing playlist file content
- The project context (key files, running services)
- Instructions to audit and augment

The init process has two phases — deterministic syntax validation (ralph, no AI) followed by semantic validation (Claude):

**Phase 1: Syntax validation (deterministic, no Claude invocation)**

Ralph parses the file line by line. Every non-blank, non-comment line must be one of:
- A bead ID (matches `br show <id>` — must exist in beads)
- A prompt line starting with `>` (optionally `>@model`)

Any line that doesn't match either pattern is a syntax error:

```
[ralph] Syntax validation:
  Line 15: ERROR — "chippie ogz3.1" is not a valid bead ID or prompt (missing hyphen?)
  Line 23: ERROR — "flutter analyze" is not a prompt (missing > prefix?)
  Line 41: WARNING — bead "chippie-xyz.99" does not exist in beads
  Line 52: WARNING — bead "chippie-ogz3.1" is already closed

  2 errors, 2 warnings. Fix errors before proceeding.
```

Errors block. Warnings don't. This phase runs instantly (no API calls, just `br show` lookups) and catches the most common authoring mistakes — typos in bead IDs, forgotten `>` prefixes, references to nonexistent beads.

**Phase 2: Semantic validation (Claude invocation)**

After syntax passes, Claude is invoked to audit the content:

1. **Verify each bead's description** against the real codebase:
   - curl every API endpoint referenced
   - Check that file paths in descriptions exist
   - Flag fabricated URLs or nonexistent endpoints
   - Update bead descriptions via `br update` where wrong
3. **Check for missing quality gates** — insert if absent:
   - Completeness scan prompts (grep TODO)
   - API smoke test prompts (curl)
   - @opus review prompts at epic boundaries
4. **Check for missing backend dependencies** — create backend beads if needed
5. **Add the validation marker** to the file header
6. **Output a brief report** of every edit made:

```
[ralph] Playlist validation complete. Changes made:

  Line 12: INSERTED — > grep -rn "TODO|FIXME" flutter/lib/. Implement or remove all matches.
  Line 23: INSERTED — >@opus VALIDATION: curl POST /auth/login, verify token, test /clients
  Line 24: INSERTED — chippie-NEW1 (created: Backend: add api_auth.login to PUBLIC_ROUTES)
  Line 45: UPDATED — bead chippie-ogz3.2 description: removed reference to /businesses/my-businesses (404)
  Line 1:  ADDED — # ✓ VALIDATED: 2026-04-05T12:00:00 by ralph playlist init

  5 lines added, 1 bead updated, 1 backend bead created.
  Playlist marked as validated.
```

The user can review the changes (the playlist is a text file — `git diff` shows everything) and then run:

```bash
ralph --playlist flutter.playlist --model sonnet --timeout 20
```

Ralph sees the `✓ VALIDATED` marker and proceeds without the warning prompt.

#### Summary: Playlist Lifecycle

```
                    ┌─────────────────────────┐
                    │ Human decides what to    │
                    │ build (epics, beads)     │
                    └──────────┬──────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                 ▼
    ┌─────────────────┐ ┌──────────────┐ ┌──────────────────┐
    │ Path A: External │ │ Path B: ralph │ │ Path C: External │
    │ creation (any    │ │ playlist     │ │ + ralph playlist │
    │ tool, by hand)   │ │ create       │ │ init             │
    └────────┬────────┘ └──────┬───────┘ └────────┬─────────┘
             │                 │                   │
             │ No validation   │ Validated by      │ Validated by
             │ marker          │ construction      │ init audit
             ▼                 ▼                   ▼
    ┌─────────────────────────────────────────────────────────┐
    │ ralph --playlist FILE                                    │
    │                                                          │
    │ if no ✓ VALIDATED marker:                                │
    │   "Playlist not validated. Continue? [y/N]"              │
    │    y → run anyway    n → offer ralph playlist init       │
    │                                                          │
    │ if ✓ VALIDATED marker present:                           │
    │   proceed directly                                       │
    └─────────────────────────────────────────────────────────┘
```

#### How This Relates to the Four-Layer Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│  BEAD AUTHORING (slash command or manual, verified against real   │  ← plans grounded in reality
│  codebase and live API via curl)                                  │
├───────────────────────────────────────────────────────────────────┤
│  PLAYLIST AUTHORING (ralph playlist create / init, or external   │  ← static plan + quality gates
│  with validation marker check)                                    │
├───────────────────────────────────────────────────────────────────┤
│  RALPH RUNTIME (outer loop — deterministic gates via gate script) │  ← enforcement
├───────────────────────────────────────────────────────────────────┤
│  CLAUDE EXECUTION (inner loop — adaptive task completion and      │  ← intelligence
│  gate failure remediation)                                        │
└───────────────────────────────────────────────────────────────────┘
```

Each layer catches a different class of error:

| Layer | What It Catches | Pilot Example |
|-------|----------------|---------------|
| Bead authoring | Wrong assumptions, fabricated URLs, missing endpoints | `api.chippie.com.au` doesn't exist, `/businesses/my-businesses` is a 404, auth response assumed to include `user` + `businesses` |
| Playlist authoring | Missing validation gates, wrong task ordering, no backend dependency tracking | No curl tests in prompt injections, no completeness scans |
| Ralph runtime gates | Implementation bugs, regressions, incomplete code, broken integration | TODOs left in code, CORS broken, login fails at runtime |
| Claude execution | Diagnosis and remediation of gate failures, adaptive fixes | Fix middleware, create missing routes, update DTOs to match actual response |

Without the bead authoring layer, the entire pipeline builds on fabricated foundations. Without the playlist validation layer, quality gates are optional and forgettable. Without runtime gates, implementation bugs go undetected. Without Claude's adaptive response, gate failures can't be diagnosed or fixed. All four layers are necessary.

---

## Part 3: Improvement Recommendations

### 3.1 Ralph Core Improvements

#### P0 — Must Fix

**R1: Cross-bead context handoff**
When a bead closes, capture a 200-word summary of what changed (files modified, patterns established, decisions made). Inject this into the next bead's prompt as a `## Prior Task Context` section. This eliminates the 5-10 turn "explore the codebase" phase at the start of every task.

Estimated savings: $15-20 per playlist run (150-200 turns saved).

Implementation: In `handle_task_outcome()`, after a task closes, extract the last assistant text block from the stream log and store it as `LAST_TASK_SUMMARY`. In `build_prompt()`, include it.

**R2: Pre-include core project files in prompt**
The top 10 most-read files should be cached in the prompt template. These are read 18-19 times each across a playlist run:
- pubspec.yaml
- lib/main.dart
- lib/core/routing/app_router.dart
- lib/data/datasources/remote/api_service.dart
- lib/core/constants/api_constants.dart
- lib/core/theme/app_theme.dart
- lib/presentation/providers/auth_provider.dart

Implementation: Add `--context-files FILE,FILE,...` flag or read from `.ralph.conf`. Append file contents to the prompt under `## Project Context`.

Estimated savings: $22 per run (290 Read calls eliminated).

**R3: Add "Do NOT spawn Agent sub-tasks" to prompt rules**
80% of tasks spawned Explore agents that were slower and more expensive than direct file reads. For projects where bead descriptions already specify file paths, this is pure waste.

Implementation: Add rule 7 to `build_prompt()`: "Do NOT spawn Agent sub-tasks for exploration. Use Read, Grep, and Glob directly."

Estimated savings: $7.50 per run.

**R4: Playlist templates (`ralph --playlist-init`)**
Ship starter templates for common patterns in `.ralph/templates/`. When creating a playlist:

```bash
ralph --playlist-init client-server > flutter.playlist
```

Generates a skeleton with validation gates pre-populated:

```
# === TEMPLATE: client-server ===
# Validation prompts are pre-populated. Fill in bead IDs between them.

# --- Phase: Foundation ---
# YOUR BEADS HERE

# [VALIDATION] Auth integration — DO NOT REMOVE
>@opus VALIDATION: Test auth against live backend. curl POST login with test creds.
Verify token. Test authenticated endpoint. Test CORS preflight.
IF issues found that need more than quick fixes: create beads with br create,
then insert the new bead IDs into this playlist file on the lines immediately
after this prompt. Ralph will pick them up on the next loop.

# [VALIDATION] Completeness scan — DO NOT REMOVE
> grep -rn "TODO\|FIXME\|STUB\|not implemented" lib/. For each match in code
written during this playlist, implement it or remove it. Do not leave TODOs.

# --- Phase: CRUD ---
# YOUR BEADS HERE

# [VALIDATION] CRUD smoke test — DO NOT REMOVE
>@opus VALIDATION: curl every entity CRUD endpoint. Verify response shapes
match DTOs. Create beads for any failures and inject into playlist.

# ... etc
```

The human fills in beads between gates. The gates are pre-written, marked `DO NOT REMOVE`, and include the dynamic injection instruction.

**R5: Dry-run validation warnings**
`ralph --playlist FILE --dry-run` should warn about missing validation patterns:

```
WARNINGS:
  * No API validation prompts detected (no lines containing "curl" or "VALIDATION")
  * No completeness scan detected (no lines containing "TODO" or "FIXME" or "grep")
  * Recommend adding validation checkpoints — see ralph --playlist-init
```

Non-blocking warnings, but they surface the gap before the playlist runs.

**R6: Playlist reload after prompt execution**
After a `>` prompt completes, reload the playlist file in case the prompt injected new lines. This enables the dynamic playlist injection pattern from Section 2.10.

Implementation: Add `playlist_reload()` function that re-reads the file into `PLAYLIST_LINES` while preserving `playlist_line` position. Call it in `playlist_execute_prompt()` after `invoke_claude` returns.

#### P1 — Should Fix

**R7: Per-line turn limits**
Allow playlist lines to specify max turns: `chippie-ogz3.1 @turns=30`. The global MAX_TURNS=500 is too generous for small tasks. A focused task with good descriptions should complete in 20-40 turns.

**R8: Loop counter visibility**
The current loop display is dim and easy to miss. Change to:
```
═══════════════════════════════════════════════════════
  LOOP 15 / 40  │  Task: chippie-hweb.2  │  Model: sonnet
═══════════════════════════════════════════════════════
```

**R9: Handle bead status "done"**
Ralph got a WARNING for status "done" on chippie-7m1j.1. Map "done" → "closed" in `check_bead_status()` and `bead_already_closed()`.

**R10: Cost tracking in state**
Add `total_cost_usd` to `.ralph_state`. Parse cost from each stream log's result entry. Show running total in monitor and cleanup summary.

**R11: Commit checkpoints in playlist**
Since no-commit mode means code accumulates unstaged, add explicit commit lines at epic boundaries. The playlist should include:
```
> git add flutter/ && git commit -m "feat(flutter): Epic 1 Foundation complete"
```

#### P2 — Nice to Have

**R12: Pre-computed project summary**
Generate `.ralph/project-context.md` at session start via a quick Claude invocation. Contains: directory structure, key files, dependency versions, architecture patterns. All subsequent tasks reference this instead of re-exploring.

**R13: Playlist line annotations**
Support inline metadata beyond @model: `chippie-ogz3.1 @turns=30 @timeout=10 @model=haiku`. Parsed by `playlist_next()`, forwarded to the invocation.

**R14: Playlist progress file**
Write `.ralph/playlist-progress.md` after each task completes. Human-readable status of what's done, what's next, what's blocked. Useful for monitoring without the TUI dashboard.

### 3.2 Playlist Composition Improvements

**P1: More granular checkpoints**
Add a quick `> flutter analyze` prompt after every 3-4 beads instead of only at epic boundaries. Catches issues earlier before they cascade.

**P2: Better bead descriptions**
Future playlists should have beads with:
- Explicit file paths to create/modify
- Expected output (e.g., "creates 3 files, modifies 2")
- `@turns` hint based on complexity estimate
- Reference to prior bead output ("ogz3.1 established the env config pattern — use it")

**P3: Conditional lines**
Support `?chippie-p63z.3` — execute only if the bead is not already closed. Useful for resume scenarios without needing the skip-closed logic.

### 3.3 Flutter-Specific Follow-Up

| Item | Type | Effort |
|------|------|--------|
| `br close chippie-7m1j.1` | Fix | 1 command |
| Update json_annotation to ^4.9.0 in pubspec.yaml | Fix | 1 line |
| Complete Deep Links (p63z.3) on macOS with Xcode | Bead | 1 task |
| Widget tests for 5 critical screens | New playlist | 5 beads |
| Offline scenario tests | New playlist | 3 beads |
| iOS build signing | Manual | Configuration |
| Commit all Flutter work to git | Manual | 1 commit |

---

## Part 4: Cost Projections

### Current Run
| Item | Cost |
|------|------|
| 31 Sonnet bead tasks | $44 |
| 8 Opus review prompts | $14 |
| Haiku sub-operations | $8 |
| Report generation | $2 |
| Waste (re-reads, agents, exploration) | $8 |
| **Total** | **$76** |

### Projected After Optimizations (R1-R3)

| Item | Current | Optimized | Savings |
|------|---------|-----------|---------|
| Context handoff (R1) | $15 wasted | $0 | -$15 |
| Pre-included files (R2) | $22 wasted | $2 (prompt size) | -$20 |
| No agent spawning (R3) | $7.50 wasted | $0 | -$7.50 |
| **Total savings** | | | **-$42.50** |
| **Projected run cost** | | **~$33** | **-56%** |

### Cost Per Feature
At $76 for 39 tasks across 6 epics, the cost per fully-implemented feature is approximately $12.67 per epic or $1.95 per individual task. With optimizations, this drops to ~$5.50 per epic or $0.85 per task.

---

## Part 5: Conclusion

### Flutter App Verdict

**Architecture: 9/10. Does it work: 3/10.**

The Flutter app has excellent Clean Architecture, proper layer separation, comprehensive screens, and a thoughtful design system. But it cannot complete a basic login against the real backend. Six P0 issues were found on the very first manual test — all of which a single curl command would have caught.

The app is a well-built house with no plumbing connected. The code quality is high but the integration is untested. Before this app is usable, it needs:
- Firebase guard for web platform
- Correct default API URL (localhost:8080)
- CORS middleware fix for OPTIONS
- API auth endpoint in PUBLIC_ROUTES
- Verify all endpoints in api_service.dart actually exist on the backend
- End-to-end login → dashboard flow working

### Ralph Playlist Verdict

**Orchestration: 8/10. Validation: 1/10.**

The playlist feature successfully orchestrated 39 tasks across 6 epics in 6 hours autonomously. The sequencing, @opus checkpoints, no-commit mode, circuit breaker, and crash recovery all worked. That's genuinely impressive for a v1 feature.

But the playlist had a fatal blind spot: **it never tested the app against the real backend**. All 12 prompt injections checked `flutter analyze` (does it compile?) but none checked `curl /api/v1/auth/login` (does it work?). The @opus reviews validated syntax and architecture but not functionality.

This is the most important lesson from the pilot: **`flutter analyze` passing is necessary but wildly insufficient.** A playlist for building a client app MUST include live API validation at every major checkpoint.

### What This Proves

Ralph playlists can autonomously produce high-quality code architecture at scale. But code quality without integration testing is a mirage. The $76 spent produced 30+ screens of well-structured code that doesn't connect to anything.

The fix is straightforward: add mandatory API validation prompts to the playlist template. Curl tests after auth, after CRUD, after each epic. Run the app and verify it renders. These cost ~$2-3 in additional prompt invocations and would have caught all 6 P0 issues.

### Priority Actions

1. **Immediately:** Fix the 6 P0 issues found during manual testing
2. **For ralph:** Add API validation prompt template as a mandatory playlist pattern for client-server projects
3. **For future playlists:** Include curl-based smoke tests at every checkpoint, not just `flutter analyze`
4. **Lesson learned:** "Does it compile?" is not "Does it work?" — ralph needs to test both
