# Playlist Format Reference

Full syntax reference for sutra playlist files. Load this file when you
need to verify a specific syntax detail while generating a playlist.

---

## Line types

| Line | Syntax | Example |
|---|---|---|
| Comment | `# text` | `# Sprint 4 — auth epic` |
| Branch directive | `# branch: name` | `# branch: oauth-login.playlist` |
| Bead | `<bead-id>` | `ralph-046.3` |
| Bead with annotations | `<bead-id> @key=value ...` | `ralph-046.3 @turns=30 @model=opus` |
| Prompt | `> text` | `> Run the integration tests` |
| Gate shorthand | `> @model #TAG context` | `> @opus #SMOKE_TEST curl /api/login` |
| Bare model shorthand | `>@model text` | `>@opus Final review` |

Rules:
- Blank lines are skipped at runtime but avoid them for readability
- Comments (`#`) are skipped at runtime
- The branch directive (`# branch:`) must appear in the first 5 lines
- Bead IDs must exist in the `br` database (`sutra playlist init` checks this)
- Prompt lines begin with `>` followed by a space (or immediately `@` for
  the bare model shorthand form `>@opus`)

---

## Annotations

Annotations appear after the bead ID (space-separated) or at the start of
a prompt line (before the prompt text). They set per-line overrides that
apply for that invocation only. On retry, global values are restored.

| Annotation | Syntax | Effect |
|---|---|---|
| Model (key=value) | `@model=opus` | Use specified model for this line |
| Model (bare) | `@opus`, `@sonnet`, `@haiku` | Shorthand; backward-compatible |
| Max turns | `@turns=30` | Override MAX_TURNS for this line |
| Timeout | `@timeout=20` | Override timeout in minutes for this line |

Examples:
```
ralph-046.3 @model=opus @turns=50 @timeout=30
ralph-046.7 @turns=20
> @model=sonnet Run the linter
>@opus Final architecture review
```

Multiple annotations on one line are space-separated, all before the
prompt text (for prompt lines) or after the bead ID (for bead lines).

---

## Gate tags

Gates are prompt lines with a `#TAG` in them. Sutra expands the tag into
a detailed audit prompt at runtime using the template in
`templates/gate_*.txt`. The context you provide after the tag is appended
to that expanded prompt.

| Tag | Model | Placement | Purpose |
|---|---|---|---|
| `#SMOKE_TEST` | `@opus` (recommended) | After first ~5 beads | Test API endpoints / functionality against live backend |
| `#COMPLETENESS_SCAN` | (default) | Every ~5 beads without a gate | Scan for TODOs, stubs, incomplete work |
| `#REVIEW` | `@opus` (recommended) | At epic boundaries | Architecture, patterns, test coverage review |
| `#REFACTOR` | `@opus` (recommended) | Tail only (>5 beads) | Systematic refactor of session code |
| `#DOCUMENT` | `@opus` (recommended) | Tail only, after REFACTOR | Document completed features |

Gate syntax:
```
> @opus #SMOKE_TEST <context specific to surrounding beads>
> #COMPLETENESS_SCAN <context specific to surrounding beads>
> @opus #REVIEW <context specific to surrounding beads>
> @opus #REFACTOR
> @opus #DOCUMENT
```

### Gate placement algorithm

```
bead_count = 0
beads_since_gate = 0
has_smoke_test = false
last_epic = ""

for each bead in order:
    current_epic = bead.parent

    if last_epic != "" and current_epic != last_epic:
        insert  > @opus #REVIEW <context>     ← epic boundary

    if not has_smoke_test and bead_count == 4:   ← i.e., before bead 5
        insert  > @opus #SMOKE_TEST <context>
        has_smoke_test = true
        beads_since_gate = 0

    if beads_since_gate >= 5:
        insert  > #COMPLETENESS_SCAN <context>
        beads_since_gate = 0

    insert  <bead-id>
    bead_count++
    beads_since_gate++
    last_epic = current_epic

if bead_count > 5:
    if no REFACTOR in playlist:  insert  > @opus #REFACTOR
    if no DOCUMENT in playlist:  insert  > @opus #DOCUMENT
```

---

## Branch directive

The branch directive tells sutra which branch to use for the entire
playlist session. It must appear in the first 5 lines.

```
# branch: feature/auth-v2
```

When `sutra playlist create` is used with a single `--epic`, the branch
directive is automatically injected as `# branch: <epic-slug>.playlist`
where `<epic-slug>` is the epic title slugified. When generating
interactively, include it if you know the target branch name.

---

## Complete minimal example

```
# branch: oauth-login.playlist
ralph-046.1
ralph-046.2
ralph-046.3
ralph-046.7
> @opus #SMOKE_TEST curl POST /api/auth/login — verify JWT in response and 401 on invalid credentials
ralph-046.9
ralph-046.11
ralph-046.12
> #COMPLETENESS_SCAN focus on token refresh edge cases and error handling in auth middleware
ralph-046.14
> @opus #REVIEW auth module: architecture, test coverage for login/refresh/logout paths
> @opus #REFACTOR
> @opus #DOCUMENT
```
