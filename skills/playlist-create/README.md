# playlist-create skill

Generates valid ralph playlist files with consistent dependency ordering,
quality gate placement, and annotation syntax — regardless of whether
the playlist is created interactively or via `ralph playlist create`.

## Why this skill exists

Ralph playlists can be created two ways:

| Path | Without skill | With skill |
|---|---|---|
| `ralph playlist create --epic X` | Uses `templates/prompt_playlist_create.txt` (incomplete rules) | Template says "invoke playlist-create skill" → full spec |
| Interactive Claude | Ad-hoc, inconsistent | Skill auto-activates on trigger phrases → full spec |

The skill is the single source of truth for playlist format rules. Both
paths load it, so both paths produce the same quality output.

## Activation

Auto-activates on phrasings like:

- "create a playlist for epic X"
- "generate a playlist for these beads"
- "build a .playlist file for epic X"
- "make a playlist"
- "write a playlist"

Also invoked explicitly when the ralph template says:
`"Invoke the playlist-create skill to generate this playlist."`

## Behavioral summary

While active, the skill:

- Determines operating mode (assisted vs self-service — see `SKILL.md`)
- In **assisted mode**: bead data is provided; outputs code block only
- In **self-service mode**: queries `br` for bead data, generates, and
  optionally writes the output file
- Applies the full gate placement algorithm (all 5 gate types)
- Enforces specific gate context — generic context is treated as a defect
- Outputs a triple-backtick code block always

## Files in this directory

| File | Purpose |
|---|---|
| `SKILL.md` | Core behavioral spec, two-mode handling, generation algorithm. Loaded automatically when the skill activates. |
| `format.md` | Full syntax reference: all line types, all 5 gate tags with placement algorithm, annotation table. Load on-demand when verifying syntax details. |
| `examples.md` | Bad→good examples: gate context, dependency ordering, multi-epic, tail gates. Load on-demand for non-trivial playlists. |
| `README.md` | This file. |

## Integration with ralph

**From `ralph playlist create`:** `templates/prompt_playlist_create.txt`
tells Claude to invoke this skill, then provides pre-fetched bead data.
After generation, ralph pipes the output through `ralph playlist init`
for Phase 1 (syntax + gate density) and Phase 2 (semantic audit).

**Interactive:** The skill handles its own `br` queries in self-service
mode. After generation, remind the user to run:
```bash
ralph playlist init <output-file.playlist>
```

## Installation

The skill lives in the ralph repo at `skills/playlist-create/`. Symlink
it into `~/.claude/skills/` so changes to the repo are immediately
reflected:

```bash
ln -s "$(pwd)/skills/playlist-create" ~/.claude/skills/playlist-create
```

Run from the ralph repo root. Verify with:
```bash
ls ~/.claude/skills/playlist-create/
```

## Related

- `ralph playlist init` — validates and semantically audits a playlist
- `ralph playlist create` — the CLI entry point that invokes this skill
- `beads-planning` skill — for planning the *content* of beads before
  creating a playlist to execute them
- `templates/prompt_playlist_create.txt` — the ralph template that
  references this skill

## Version

- **1.0.0** — initial release, alongside ralph's playlist implementation
  in `lib/playlist_create.sh`, `lib/gates.sh`, `lib/playlist_annotations.sh`,
  and the 5 gate templates in `templates/gate_*.txt`.
