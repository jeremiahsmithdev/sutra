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
1. If an epic ID is given, run:
   `br ready --parent=<epic-id> -r --json`
   Then for each bead ID, run `br show <id> --json` to get title and deps.
   If `br ready` returns nothing, run `br list --parent=<epic-id> --json`.
2. If raw bead IDs are given, run `br show <id> --json` for each.
3. Generate the playlist.
4. Output a code block in your response.
5. If an output file was requested (`-o <file>` or "save to X"), also
   write it with the Write tool.

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
