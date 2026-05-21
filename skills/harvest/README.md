# Harvest Skill

The methodology harvest skill for sutra. Reviews completed sutra runs to find
orchestration and instruction gaps, scores findings against seven guardrails,
and generates self-improvement beads.

## What it does

The methodology harvest reviews **how sutra performed**, not what code it produced.
It asks: *given the same philosophy, can the next run be simpler, better
aligned, or less redundant?*

## Input

A completed sutra run, identified by:
- Specific run ID (timestamp, playlist name, branch), or
- Auto-detected most recent run

The skill reads:
- Session logs (`.sutra/logs/sessions/*.log`)
- Stream-json files (`.sutra/logs/stream/*.jsonl`)
- Playlist files (if applicable)
- Playlist progress snapshot (`.sutra/playlist-progress.md`)
- Playlist completion report
- Bead state diffs

## Output

1. **A dated epic** of self-improvement beads (tagged `self-improvement`,
   prefixed `HV:`)
2. **A concise report** at `.sutra/harvests/<timestamp>.md`

## Process

1. **Diagnose** — Find symptoms: stalls, retries, escalations, circuit breaker
   trips, shallow gate work
2. **Classify** — Each finding falls into one of five categories:
   - Inner-loop instruction gap
   - Outer-loop orchestration gap
   - Bead-description shape
   - Gate template
   - Context injection
3. **Score** — Each finding must survive all seven guardrails
4. **Filter** — Most findings are rejected. A mature harvest rejects >50%.
5. **File** — Accepted findings become beads under a harvest epic

## The Seven Guardrails

1. **Loop placement** — Intelligence in inner loop, orchestration in outer
2. **Simplicity delta** — Bias toward subtractive
3. **Artefact vs decision** — Store evidence, not ephemeral decisions
4. **Determinism** — Failure must be predictable, not probabilistic
5. **Configurable** — New capabilities must be opt-in
6. **Template vs code** — Instructions in templates/, logic in lib/
7. **Size limits** — File ≤200, function ≤50, case ≤10, string ≤5

See `guardrails.md` for detailed explanations.

## When to use

Trigger phrases:
- "harvest this run"
- "run a harvest"
- "methodology harvest"
- "harvest findings"
- "what went wrong in this run"
- "review the sutra run"

## When NOT to use

- Code review of the work sutra produced — use the separate work harvest
- Questions about harvest syntax or methodology — answer directly
- Running or monitoring a playlist — use `sutra --playlist`
- Validating a playlist — use `sutra playlist init`

## Quick reference

| Command | Purpose |
|---------|---------|
| `sutra --playlist playlists/harvest-methodology.playlist` | Run the full harvest playlist |
| `br list -l self-improvement` | View pending methodology findings |
| `ls .sutra/harvests/` | Browse harvest archive |

## See also

- `SKILL.md` — The skill instructions for Claude
- `guardrails.md` — Detailed guardrail explanations
- `examples.md` — Concrete good/bad finding examples
- `HARVEST_METHODOLOGY.md` — Full methodology specification
