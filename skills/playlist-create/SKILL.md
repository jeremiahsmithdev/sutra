---
name: playlist-create
description: >
  Generate a valid ralph playlist file from an epic or set of bead IDs.
  Auto-activates on phrasings like "create a playlist for epic X",
  "generate a playlist for these beads", "build a .playlist file",
  "make a playlist", "write a playlist". Also invoked explicitly by
  ralph's playlist create command via templates/prompt_playlist_create.txt.
  Handles dependency ordering, quality gate placement, and per-line
  annotation syntax. Output is always consistent regardless of whether
  invoked interactively or from ralph's automated pipeline.
allowed-tools: "Read,Write,Bash(br:*)"
version: "1.0.0"
---

# Playlist Create Skill

Generate a ralph playlist file — a text file where each line is a bead
ID, a prompt, a gate shorthand, a comment, or a branch directive.

## Reference files in this skill directory

Load these on-demand, not eagerly.

- **`format.md`** — Full syntax reference: all line types, all 5 gate
  tags with placement rules, annotation syntax, branch directive.
  Load when you need to verify a specific syntax detail.
- **`examples.md`** — Complete bad→good playlist examples. Load when
  generating a non-trivial playlist (>5 beads, multiple epics, or when
  gate context specificity is uncertain).

## Reference files OUTSIDE this skill (in the ralph repo)

The gate tags you place in playlists are shorthand. At runtime ralph
expands each `#TAG` into the full prompt body from the corresponding
template file. Read these when the surrounding bead work is unusual
enough that you need to verify the gate's prompt will actually exercise
it correctly, OR when deciding what context to write after the tag.

| Tag | Template file | What the expanded prompt does |
|---|---|---|
| `#SMOKE_TEST` | `templates/gate_smoke_test.txt` | Starts dev server, establishes auth, hits endpoints from the session diff, records pass/fail table, kills server. Detection only — does not fix. |
| `#COMPLETENESS_SCAN` | `templates/gate_completeness_scan.txt` | Scans recent work for TODOs, stubs, placeholder returns, untested branches. Reports findings. |
| `#REVIEW` | `templates/gate_review.txt` | Architecture / pattern / test-coverage review across recent beads. |
| `#REFACTOR` | `templates/gate_refactor.txt` | Systematic refactor pass over session code; bounded by a scope limit (creates a bug bead if exceeded). |
| `#DOCUMENT` | `templates/gate_document.txt` | Documents completed features. |

These are at `/Users/admin/dev/ralph/templates/gate_*.txt`. Read them
with the Read tool if you need full detail for a specific tag — for
example, to confirm what auth fixtures `#SMOKE_TEST` looks for, or what
"scope limit" `#REFACTOR` enforces.

### How the context after a gate is used

Whatever you write after `#TAG` is appended to the expanded template as
a "scenario context" block. The template provides the procedure
(preconditions, checks, output format, teardown). YOUR context should
provide the *specifics* — endpoints, files, modules, request bodies,
edge cases — that the procedure should focus on. Don't restate what
the template already says; complement it.

Example: `#SMOKE_TEST`'s template already tells Claude to start the dev
server and run curl. So good context names the routes/methods/payloads
to test ("POST /api/auth/login with bad password — verify 401"), not
"please test the auth endpoints" (the template already implies that).

### Self-heal mechanism (why gates can rewrite the playlist mid-run)

Most gate templates end with a self-healing directive: when the gate
finds problems, Claude is told to `br create --type=bug` and **append
the new bead ID to the playlist file on the line after the current
gate**. Ralph's `playlist_reload.sh` re-reads the file after each `>`
prompt invocation, so injected beads become the next executed lines.

Implications when authoring:
- A gate is not a leaf — it can spawn follow-up beads. Place gates
  where you actually want that loop (after risky chunks of work).
- Don't manually pre-list defensive bug-fix beads "in case the gate
  finds something" — the gate creates them on demand.
- The number of injectable beads is capped (`MAX_INJECTED_BEADS` /
  `INJECTION_RATIO` in `lib/config.sh`); after the cap is hit
  `lib/gates.sh:strip_injection_instructions` removes the self-heal
  lines, so don't over-stack gates expecting unbounded recovery.

### Custom `>` audit prompts must respect playlist-reload

When you author bespoke `>` prompts that surface gaps (orientation
passes, mid-playlist recalibrations, self-audits — anything that
discovers new work), they MUST integrate with the same
`playlist_reload.sh` mechanism gates use. The whole point of an audit
prompt is to feed discovered work back into the run.

**NEVER write directives like:**
- "Do NOT mutate this playlist file"
- "Surface a numbered list for the operator"
- "Report only; do not modify the playlist"

These actively fight the runtime. If a human-only checkpoint is
genuinely intended, the playlist itself should not be the surfacing
medium — write the report to a doc instead.

**INSTEAD, end every audit-style `>` prompt with a placement
directive** that tells Claude both *to* inject and *where* to inject:

> Insert each raised bead into this playlist at the position that
> respects dependencies and phase order — e.g. an X gap belongs near
> line N (X phase), a Y gap belongs inside the Y phase. Place each
> bead before any gate or REVIEW that should audit it.

Why "at the right position" and not "on the line immediately after
this prompt":
- Gates self-heal "immediately after" because the gate is auditing
  the work that just ran — the next line is the right place.
- Custom audits often discover gaps that belong in *future* phases
  (a Universal Links gap surfaced by an orientation pass belongs in
  the Universal Links phase 15 lines later, not next).
- Tell the audit prompt to reason about phase boundaries and place
  each bead where it actually fits, with concrete examples drawn
  from the playlist's structure.

## Two operating modes

### Mode A — Assisted (called from ralph)

The prompt contains a `BEADS:` section with pre-formatted bead data
(`id — title (parent: X) [depends: Y, Z]`) and an `OUTPUT_FILE` path.

In this mode:
- The bead list is already complete — do not re-fetch IDs or titles
- You MAY call `br show <id> --json` for additional context (epic
  description, bead descriptions, design notes) if it would improve
  ordering or gate placement decisions
- Write the playlist directly to the specified output file using Write
- No commentary — just write the file and stop

### Mode B — Self-service (interactive)

The user asks you to create a playlist without providing bead data.

In this mode:
1. If an epic ID is given, gather its children in order:

   **Step 1 — try ready tasks first:**
   ```bash
   br ready --parent=<epic-id> -r --json
   ```
   Returns open, unblocked tasks. May return `[]` if all tasks are
   already claimed (in_progress) or if the epic has no open children.

   **Step 2 — if empty, fetch all non-closed tasks:**
   ```bash
   br list --status open --status in_progress --json \
     | jq '[.issues[] | select(.parent == "<epic-id>")]'
   ```
   Note: `br list` returns `{"issues": [...], ...}` — use `.issues[]`,
   not `.[]`. There is no `--parent` flag on `br list`.

   **Step 3 — for each bead ID found, get full details:**
   ```bash
   br show <id> --json
   ```
   Extract title, parent, and dependencies from the result.

2. If raw bead IDs are given, run `br show <id> --json` for each.
3. Generate the playlist and write it to the output file.
4. Show the playlist content in your response so the user can review it.

## How to generate the playlist

### Step 1 — Resolve the dependency order

Use the `[depends: ...]` field on each bead. Place foundational beads
(no unresolved dependencies) before beads that depend on them. Within a
dependency tier, keep epic siblings together.

For multiple epics: group each epic's beads together. Epic boundaries
are where the `parent` field changes between consecutive beads.

### Step 2 — Place gates

Load `format.md` now if you haven't already — it has the full gate table.

Rules:
1. **After the 5th bead** (if no SMOKE_TEST exists yet): insert
   `> @opus #SMOKE_TEST <specific context>`
2. **Every ~5 beads without any gate**: insert
   `> #COMPLETENESS_SCAN <specific context>`
3. **At epic boundaries** (parent field changes between consecutive beads):
   insert `> @opus #REVIEW <specific context>` before the first bead of
   the new epic
4. **At the playlist tail** (only when total beads > 5): append
   `> @opus #REFACTOR` then `> @opus #DOCUMENT` as the final two lines

### Step 3 — Write gate context (non-negotiable)

Every gate line MUST have specific context after the tag. Generic context
is a defect — the gate will expand to a vague prompt and Claude won't know
what to focus on.

**BAD — generic:**
```
> @opus #SMOKE_TEST
> #COMPLETENESS_SCAN
> @opus #REVIEW
```

**GOOD — specific:**
```
> @opus #SMOKE_TEST curl POST /api/auth/login and GET /api/users/:id — verify JWT in response, 401 on bad token
> #COMPLETENESS_SCAN focus on the session middleware and token refresh logic
> @opus #REVIEW auth module: check token expiry edge cases and test coverage for the refresh path
```

The context should name the endpoints, files, modules, or concepts that
the surrounding beads introduced. Read the bead titles to infer this —
don't guess generically.

### Step 4 — Write the file

If the playlist is for a single epic, add a branch directive as the
first line:
```
# branch: <epic-slug>.playlist
```
where `<epic-slug>` is the epic title lowercased with spaces replaced by
hyphens.

Build the playlist in order. No blank lines. No comments unless a branch
directive is needed.

## Output format

In both modes, write the playlist to a file using the Write tool.

- **Mode A (assisted):** write to the path specified in `OUTPUT_FILE`.
  No other output — just write the file and stop.
- **Mode B (self-service):** write to the path given by the user (`-o`
  argument or stated in the request). Also show the content in your
  response so the user can review it inline.

## Validation reminder

After generation, the playlist should be run through:
```bash
ralph playlist init <file.playlist>
```

This runs Phase 1 (syntax + gate density checks) and Phase 2 (semantic
audit via Claude that checks dependency ordering and gate context quality).
In the ralph `playlist create` pipeline, init is called automatically
after generation. In interactive use, remind the user to run it.

## When this skill does NOT apply

- User is asking about playlist syntax but not generating one — answer
  directly without activating this skill's generation workflow
- User wants to run or monitor an existing playlist — that's `ralph
  --playlist` territory, not this skill
- User wants to validate an existing playlist — that's `ralph playlist
  init`, not this skill
