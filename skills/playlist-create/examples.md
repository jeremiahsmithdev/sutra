# Examples: Bad → Good

Concrete bad→good playlist examples for the playlist-create skill. Load
this file when generating a non-trivial playlist, when gate context
specificity is uncertain, or when handling multiple epics.

The primary example uses the ralph-046 epic (prompt engineering overhaul)
since those beads exist in the repo and illustrate realistic ordering and
gate decisions.

---

## 1. Gate context — the most common defect

### Bad — generic gates (rejected at `sutra playlist init`)

```
ralph-046.1
ralph-046.2
ralph-046.3
ralph-046.7
ralph-046.9
> @opus #SMOKE_TEST
ralph-046.11
ralph-046.12
ralph-046.14
> #COMPLETENESS_SCAN
> @opus #REVIEW
> @opus #REFACTOR
> @opus #DOCUMENT
```

**Why it fails:**

- `#SMOKE_TEST` with no context — the expanded template says "test API
  endpoints" but there are no endpoints. What should Claude test here?
  Which commands? What outputs to verify?
- `#COMPLETENESS_SCAN` with no context — scans the whole project for
  TODOs/FIXMEs, but the prompt template asks Claude to focus on "code
  written during this playlist." Without context it has no anchor.
- `#REVIEW` with no context — reviews "the last epic" in the abstract,
  but which patterns? Which risky areas?

The semantic audit in `sutra playlist init` will flag all three and
ask you to add context.

### Good — specific gates

```
# branch: prompt-engineering-overhaul.playlist
ralph-046.1
ralph-046.2
ralph-046.7
ralph-046.3
ralph-046.9
> @opus #SMOKE_TEST invoke sutra with --dry-run --playlist selftest.playlist; verify loop header, prompt assembly, and that no file writes occur
ralph-046.11
ralph-046.12
> #COMPLETENESS_SCAN focus on invoke.sh retry logic, lifecycle.sh dry-run guards, and any FIXMEs in the new escalation and cost-tracking code
ralph-046.14
> @opus #REVIEW prompt engineering overhaul: verify --bare and system prompt integration, check retry escalation edge cases, confirm cost tracking persists correctly across crashes
> @opus #REFACTOR
> @opus #DOCUMENT
```

**Why it works:**

- `#SMOKE_TEST` names the exact command to run and what to observe
- `#COMPLETENESS_SCAN` names specific files and the area of concern
- `#REVIEW` names the three subsystems introduced by this playlist

---

## 2. Dependency ordering — wrong vs right

### Bead data for this example

```
ralph-046.1 — Fix commit contradiction in prompt template (parent: ralph-046)
ralph-046.2 — Reorder prompt sections for attention priority (parent: ralph-046)
ralph-046.3 — Add --bare mode and system prompt file (parent: ralph-046) [depends: ralph-046]
ralph-046.7 — Add failure mode inoculation to prompt templates (parent: ralph-046) [depends: ralph-046]
ralph-046.9 — Replace prose handoff with structured JSON state file (parent: ralph-046) [depends: ralph-046]
ralph-046.11 — Error-type-aware escalation and cumulative failure history (parent: ralph-046) [depends: ralph-046]
ralph-046.12 — Add outcome-based verification to outer loop (parent: ralph-046) [depends: ralph-046]
ralph-046.14 — Add gate scope caps and conditional orientation depth (parent: ralph-046) [depends: ralph-046]
```

All beads depend on the epic (`ralph-046`) as their direct parent, not on
each other. That means they're all technically parallelisable relative to
each other. The right ordering logic is:

1. Template-only changes first (low risk, no pipeline deps): .1 and .2
2. Template changes that are deeper: .7 (inoculation)  
3. Pipeline changes (depend on templates being correct): .3 (--bare mode)
4. State/handoff changes: .9 (JSON state)
5. Retry/escalation logic: .11
6. Outcome verification: .12 (logically builds on .11)
7. Gate/orientation depth: .14 (final tuning)

### Bad — random order ignores logical tiers

```
ralph-046.12
ralph-046.3
ralph-046.1
ralph-046.14
ralph-046.11
ralph-046.7
ralph-046.9
ralph-046.2
```

**Why it's bad:**

- `.12` (outcome verification) comes before `.11` (escalation logic) —
  verification depends conceptually on the retry/escalation being in place
- `.3` (--bare mode) comes before `.1` and `.2` (template fixes) — the
  --bare mode should pick up the cleaned-up templates on first run
- Random order makes the session harder to follow and increases the chance
  of a task failing because its informal dependency isn't in place yet

### Good — logical tier order

```
# branch: prompt-engineering-overhaul.playlist
ralph-046.1
ralph-046.2
ralph-046.7
ralph-046.3
> @opus #SMOKE_TEST invoke sutra with --dry-run --playlist selftest.playlist to verify prompt assembly, loop header display, and no accidental file writes
ralph-046.9
ralph-046.11
ralph-046.12
> #COMPLETENESS_SCAN focus on retry escalation in invoke.sh, dry-run guards in lifecycle.sh, cost accumulation edge cases
ralph-046.14
> @opus #REVIEW prompt engineering overhaul: verify --bare + system prompt integration, check retry logic under timeout and OOM exits, confirm JSON handoff survives crash/resume
> @opus #REFACTOR
> @opus #DOCUMENT
```

**Why it works:**

- Template-only changes (.1, .2, .7) land first — zero pipeline risk
- Pipeline change (.3) comes after templates are clean
- SMOKE_TEST fires after 5 beads, tests the integrated pipeline early
- State (.9), escalation (.11), verification (.12) follow in logical order
- Gate depth tuning (.14) is last — it can reference the fully-built system
- Tail gates anchor the session end

---

## 3. Multi-epic playlist — REVIEW at boundaries

### Scenario

Two epics: `ralph-046` (prompt engineering) and `ralph-0h1` (playlist
validation). Each has 4 beads. Correct behaviour: REVIEW at the boundary.

### Good — epic boundary handling

```
# branch: combined-sprint.playlist
ralph-046.1
ralph-046.2
ralph-046.3
ralph-046.7
> @opus #SMOKE_TEST run sutra --dry-run on selftest.playlist; verify prompt assembly and invocation pipeline
> @opus #REVIEW prompt engineering epic: check --bare mode integration, template ordering, and inoculation coverage
ralph-0h1.11
ralph-0h1.12
ralph-0h1.20
ralph-0h1.13
> #COMPLETENESS_SCAN focus on playlist_validate.sh and playlist_init.sh — check for incomplete gate injection or semantic validation edge cases
> @opus #REVIEW playlist validation epic: verify dry-run reports gate density correctly, init runs semantic audit, marker insertion is idempotent
> @opus #REFACTOR
> @opus #DOCUMENT
```

**Why it works:**

- `#REVIEW` before the epic boundary summarises the first epic before
  starting the second — clean conceptual break
- `#SMOKE_TEST` fires after the 5th bead of the first epic (position 5)
- `#COMPLETENESS_SCAN` fires 5 beads into the second epic (position 9+)
- Second `#REVIEW` after the second epic summarises before tail gates
- `#REFACTOR` and `#DOCUMENT` are always the final two lines

---

## 4. Tail gates — when they do and don't appear

Tail gates (`#REFACTOR`, `#DOCUMENT`) only appear when total bead count
exceeds 5. For a 3-bead playlist, they are omitted.

### Short playlist — no tail gates

```
ralph-046.1
ralph-046.2
ralph-046.3
```

(3 beads, no smoke test, no refactor/document — correct)

### Longer playlist — tail gates required

```
ralph-046.1
ralph-046.2
ralph-046.3
ralph-046.7
ralph-046.9
> @opus #SMOKE_TEST run sutra --dry-run on selftest.playlist
ralph-046.11
> #COMPLETENESS_SCAN focus on retry and cost accumulation logic
> @opus #REVIEW check escalation chain and cost tracking end-to-end
> @opus #REFACTOR
> @opus #DOCUMENT
```

(7 beads — tail gates added)

---

## Quick checklist before outputting

- [ ] Beads are in logical-tier order (foundational before dependent)
- [ ] Every gate line has specific context after the tag
- [ ] SMOKE_TEST fires after the ~5th bead (or at bead count 5 if >5 total)
- [ ] COMPLETENESS_SCAN fires every ~5 beads without a gate
- [ ] REVIEW appears at every epic boundary (if multi-epic)
- [ ] REFACTOR and DOCUMENT appear as the final two lines (if >5 beads)
- [ ] REVIEW appears before REFACTOR/DOCUMENT if used as a final review
- [ ] Branch directive is at the top (line 1) for single-epic playlists
- [ ] No blank lines inside the playlist body
- [ ] File is written with the Write tool to the specified output path
