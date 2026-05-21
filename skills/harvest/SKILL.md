---
name: harvest
description: >
  HARD TRIGGER: when user messages contain "harvest" + any of sutra/ralph/run/
  session/playlist/findings/gaps/methodology/work/code/self/review/verifications/
  morning, LOAD THIS SKILL. Also trigger on "run a harvest", "harvest this
  run", "harvest findings", "review sutra run", "morning review". Supports
  three modes: code harvest (review work produced), methodology harvest
  (analyze run itself), self-harvest (skill uses same orchestrator it evaluates).
  Handles multiple unharvested runs, marks as harvested, provides interactive
  flow with reports and bead-ready commands.
allowed-tools: "Read,Grep,Glob,Bash(br:*),Write,Edit,AskUserQuestion"
version: "1.1.0"
---

# Harvest Skill

Performs sutra harvests — reviewing completed runs to extract learnings,
improve orchestration, and groom backlog. Two main harvest types:

| Harvest type | What it reviews | Output |
|-------------|----------------|--------|
| **Code harvest** | Code, beads, tests produced overnight | Verified/reverted work, updated backlog, refined prompts |
| **Methodology harvest** | The run itself (orchestration, instructions) | Self-improvement beads, process improvements |

Both harvests are peer activities. Run code harvest first; a bad merge can't be
undone by a methodology insight.

## Mode Selection

The skill operates in three modes, detected from user phrasing:

| Mode | Trigger phrases | What it does |
|------|--------------|-------------|
| **Code harvest** | "harvest code", "morning review", "review beads", "harvest:code", "review verifications" | Reviews code/beads produced, marks verified/reverted, grooms backlog |
| **Methodology harvest** | "methodology harvest", "harvest methodology", "harvest:methodology", "harvest self" | Analyzes run orchestration, finds gaps, generates self-improvement beads |
| **Self harvest** | "self harvest", "harvest self", "harvest:self" | Methodology harvest for the skill itself |

If mode is ambiguous or user didn't specify, **ask user to clarify** using
AskUserQuestion with these options:
- "Code harvest (review work produced)"
- "Methodology harvest (analyze run itself)"
- "Self harvest (review skill improvement)"

## Detecting Runs to Harvest

### Step 1 — Find unharvested runs

Scan for completed runs that haven't been harvested yet:

```bash
# Check .sutra/reports/ for unharvested runs
ls -t .sutra/reports/*.md 2>/dev/null | while read f; do
  if ! grep -q "harvested:" "$f" 2>/dev/null; then
    echo "$f"
  fi
done
```

Also list prior harvest reports for this project — both code and methodology
harvests are written to `.sutra/harvests/`:
```bash
ls -t .sutra/harvests/*.md 2>/dev/null || echo "No prior harvests"
```

### Step 2 — Multiple runs found

If more than one unharvested run exists, ask user which to harvest first:

```bash
# List available runs with metadata
for report in $(ls -t .sutra/reports/*.md 2>/dev/null | head -10); do
  basename "$report"
  # Extract timestamp, run type, identifier
done
```

Use AskUserQuestion with options:
- "Harvest [run 1] first"
- "Harvest [run 2] first"
- "Harvest all sequentially"

If user chooses sequential, process runs one at a time, asking after each whether to continue.

### Step 3 — Load run metadata

For the selected run, extract:
- Run identifier: from report filename or user input
- Run type: playlist or standard mode
- Session log path: `.sutra/logs/sessions/<filename>`
- Stream-json files: `.sutra/logs/stream/<session>-*.jsonl`
- Playlist file (if applicable): locate `.playlist` file
- Playlist completion report: `.sutra/playlist-progress.md`
- Bead state: `br list --json`

---

## CODE HARVEST MODE

The code harvest reviews work that sutra produced overnight. It is the morning
routine described in `Harvest.md`.

### Step 1 — Read the log

Read the session log to understand what ran:
- What completed, what failed, what timed out
- Get the shape before looking at code

### Step 2 — Review verification queue

Use `bnr` to list issues awaiting verification:

```bash
bnr  # or: br list --label needs-review --json
```

For each issue in the queue, use AskUserQuestion to drive the review:

```
# Read bead details and git diff
br show <id> --json
git log --oneline --all -n 5
git diff HEAD~5 HEAD --stat

# Present options
- [Verified] Mark as verified
- [Reopen] Reopen for another attempt
- [Needs rework] Add comment and update description
```

**Important:** Actually perform the verification steps. Don't just mark verified
without testing. Check:
- Do tests pass?
- Are they meaningful tests?
- Does implementation match the intended bead?

### Step 3 — Check quality gates

Sutra creates review and test beads as follow-ups. Check whether the quality
gate work is substantive or superficial:
- A review bead that just says "looks good" is not a review
- Test beads should have meaningful coverage

For each gate bead, ask user:
- "Substantive gate work?"
- [Yes] [No] [Skip]

### Step 4 — Calibrate the workflow

Use metrics data to surface anomalies. Run queries to find outliers:

```bash
# Issues where time predictions were way off
if [ -f .sutra/metrics.db ]; then
  sqlite3 .sutra/metrics.db "
    SELECT issue_id, estimated_minutes, actual_minutes, time_ratio
    FROM task_metrics WHERE time_ratio > 3.0 OR time_ratio < 0.3;"
fi
```

For flagged issues, review scout reports and git diffs. Use AskUserQuestion
to capture insights:
- "Why was the prediction wrong?"
- [Scout entity issue] [Task complexity] [Entry point wrong] [Other]

### Step 5 — Groom the backlog

Based on what was seen, propose backlog updates:

| Action | When to use | Command |
|--------|-------------|---------|
| Mark verified | Tests pass, implementation matches | `bV` |
| Reopen bead | Implementation missed the point | `breopen <id>` |
| Break down bead | Loop struggled with it | Create sub-beads |
| Add new bead | Spotted issue in diffs | `br create --title=...` |
| Update description | Description was ambiguous | `br update <id> --description=...` |

Present proposed actions to user with AskUserQuestion:
- "Approve these backlog updates?"
- [Apply all] [Review individually] [Skip all]

### Step 6 — Update guidance

If failure patterns were identified, propose prompt/template improvements:
- Add guardrails to CLAUDE.md or prompt
- Update AGENTS.md with new conventions
- Adjust scout configuration
- Tweak quality gate descriptions

Ask user:
- "Proposed prompt improvements found. Approve?"
- [Yes, apply] [Review first] [Skip]

### Step 7 — Generate harvest report

Write the final harvest report (see "Report Format" below) to
`.sutra/harvests/`. This is the harvest's own output; the sutra
completion report under `.sutra/reports/` is left untouched except
for the marker stamp added in Step 8.

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HARVEST_REPORT=".sutra/harvests/${TIMESTAMP}-code.md"
mkdir -p .sutra/harvests
# Render the report using the structure documented under "Report Format"
# below, then write it to "$HARVEST_REPORT".
```

### Step 8 — Mark the run as harvested

After the harvest report is written and user review is complete,
stamp the underlying sutra completion report so future harvest runs
skip it:

```bash
# Append a marker to the run's completion report (NOT the harvest report).
REPORT_FILE=".sutra/reports/$(basename "$REPORT_PATH")"
harvest_date=$(date +%Y-%m-%d)

echo -e "\n\n---\n## Harvest\n\n**Code harvest completed:** $harvest_date\n**Mode:** code\n**Verifications reviewed:** N\n**Reopened:** M\n**New beads:** K\n**Report:** $HARVEST_REPORT\n" >> "$REPORT_FILE"
```

---

## METHODOLOGY HARVEST MODE

The methodology harvest analyzes the run itself — orchestration, instructions,
gaps between planned and actual. This is the process improvement loop.

See `HARVEST_METHODOLOGY.md` for the full methodology. This section
provides the workflow.

### Step 1 — Read run inputs

Read all available inputs:
1. Session log (`.sutra/logs/sessions/*.log`)
2. Stream-json files (`.sutra/logs/stream/*.jsonl`) — extract turn counts, cost, model escalations, tool use patterns
3. Playlist file (if applicable) — planned order, annotations, gate tags
4. Playlist progress snapshot (`.sutra/playlist-progress.md`)
5. Playlist completion report (generated at run end)
6. Bead state diff — compare `br list` before/after

### Step 2 — Diagnose symptoms

Look for failure patterns in the logs:

| Symptom | Where to look | What it indicates |
|---------|--------------|------------------|
| Retries | Stream-json retry_count, log "retrying" | Model couldn't complete task |
| Escalation | Stream-json model changes, log "escalating" | Cheap model insufficient |
| Circuit breaker trip | `.sutra/state` circuit_breaker field | No progress on multiple attempts |
| Shallow gate work | Short turn counts after gate tags | Gate produced trivial changes |
| Stalls | Long pauses, timeout logs | Blocker not resolved |

For each symptom, record evidence: line numbers, bead IDs, invocation numbers.

### Step 3 — Classify findings

Each finding falls into one of five categories:

1. **Inner-loop instruction gap** — Prompt or template needs refinement
2. **Outer-loop orchestration gap** — Bash needs adjusting (determinism, reliability)
3. **Bead-description shape** — Bead was ambiguous or incomplete
4. **Gate template** — Quality gate template missed a case
5. **Context injection** — Inner loop lacked state it needed

**Important:** A finding that fits none of these categories is probably not a
methodology finding — it might be a bug for the work harvest.

### Step 4 — Score against guardrails

Each finding must survive ALL seven guardrails to become a bead. Failing
any one kills the candidate.

See `guardrails.md` for detailed guardrail explanations:

1. **Loop placement** — Intelligence in inner loop, orchestration in outer
2. **Simplicity delta** — Bias toward subtractive
3. **Artefact vs decision** — Store evidence, not ephemeral decisions
4. **Determinism** — Failure must be predictable, not probabilistic
5. **Configurable** — New capabilities must be opt-in
6. **Template vs code** — Instructions in templates/, logic in lib/
7. **Size limits** — File ≤200, function ≤50, case ≤10, string ≤5

For each finding, use AskUserQuestion to confirm classification:
- "Classified as [category]. Survives all guardrails?"
- [Yes, create bead] [No, reject] [Edit classification]

### Step 5 — Generate harvest report

**Write to the methodology codebase, not the execution project.** A methodology
harvest analyses sutra's orchestration — its findings and beads concern the
sutra codebase itself. The report and the self-improvement beads therefore
belong in the **sutra repo** (the methodology codebase), NOT in the execution
project whose `.sutra/queue` produced the run. Only the *code* harvest writes
into the execution project.

Resolve the sutra repo root (e.g. the directory containing `lib/loader.sh` and
`sutra`) and create the report at `<sutra-repo>/.sutra/harvests/<timestamp>-methodology.md`.
Create the epic and beads in the sutra repo's `.beads/` (run `br` from that
directory). The run's completion report under the execution project's
`.sutra/reports/` is still stamped in place (Step 7) — only the harvest
artefacts move.

```markdown
# Harvest <timestamp> — <playlist-name-or-session-id>

**Epic:** br-<epic-id> (created below)

## Summary

N findings diagnosed. M accepted as self-improvement beads. K rejected.

Run identifier: <identifier>
Run type: playlist / standard mode
Duration: <if available>
Total cost: <if available>

## Accepted Findings

### 1. HV: <short description>

**Category:** <category>

**Evidence:** <what in the logs/outputs supports this finding>

**Recommended bead:**
```bash
br create --type chore --title "HV: <short description>" \
  --parent=<epic-id> --priority 2 \
  --description "$(cat <<'EOF'
<detailed description including exact file paths and changes>

Files affected:
- <path>
- <path>

Changes required:
<specify what to change, how, and why>

Verification:
<how to test the change>
EOF
)"
```

---

### 2. HV: <short description>
...

## Rejected Candidates

### 1. <candidate description>

**Rejected:** Guardrail <N> — <one-line reason>

---

### 2. <candidate description>
...
```

### Step 6 — Create beads (after user review)

Ask user to review the report. Use AskUserQuestion:
- "Review complete. Approve bead creation?"
- [Create all beads] [Review individually] [Skip all]

After approval, create the epic and beads:

```bash
# Create epic
EPIC_ID=$(br create --type epic --title "Harvest $TIMESTAMP — $IDENTIFIER" \
  --priority 2 --description "Methodology harvest for sutra run $IDENTIFIER.

Run metadata:
- Type: <playlist/standard>
- Session: <session-log-path>
- Playlist: <playlist-file-or-none>
- Timestamp: $TIMESTAMP

Epic contains all findings that survived the seven guardrails.
See .sutra/harvests/$TIMESTAMP-methodology.md for full report." | jq -r '.id')

# Create beads for accepted findings
# (use commands from report)

# Label epic and children
br label add $EPIC_ID self-improvement
br label add <bead-id-1> self-improvement
...
```

### Step 7 — Mark as harvested

Mark the run as harvested in its report:

```bash
# Add harvest metadata to the report file
REPORT_FILE=".sutra/reports/$(basename "$REPORT_PATH")"
harvest_date=$(date +%Y-%m-%d)

echo -e "\n\n---\n## Harvest\n\n**Methodology harvest completed:** $harvest_date\n**Mode:** methodology\n**Epic:** br-$EPIC_ID\n**Findings accepted:** M\n**Report:** .sutra/harvests/$TIMESTAMP-methodology.md\n" >> "$REPORT_FILE"
```

---

## SELF HARVEST MODE

The self harvest is a methodology harvest of the skill itself. The skill
uses sutra to evaluate and improve the skill. This is the recursive property.

Follow the **methodology harvest** process, but with these inputs:
- Skill file: `skills/harvest/SKILL.md`
- Guardrail reference: `skills/harvest/guardrails.md`
- Previous run transcripts: for evaluation
- User feedback: from previous harvest reports

The self harvest produces findings about:
- Is the mode detection working correctly?
- Are the interactive questions helpful or annoying?
- Is the report format useful?
- Are the bead commands accurate?

Self harvest findings are tagged `self-improvement` and titled `SELF: <description>`.

---

## Interactive Flow Pattern

Throughout both harvest modes, use this pattern for user interaction:

1. **Gather information first** — read files, analyze logs, propose options
2. **Present with multiple choice** — when there are 2-4 clear options
3. **Free-form input** — when user needs to provide details (e.g., "What's the issue?")
4. **Confirm action** — before executing destructive commands
5. **Stop and ask** — if multiple reasonable pathways exist

Example for verification queue review:

```
# Gather: read bead details, diff
br show $bead_id --json
git diff HEAD~2 HEAD -- $files

# Present multiple choice
AskUserQuestion:
  "Bead $bead_title ($bead_id) — Skim the diff:"
  options:
    - label: "Verified"
      description: "Tests pass, implementation matches bead description"
    - label: "Reopen"
      description: "Implementation missed the point, try again"
    - label: "Needs rework"
      description: "Add comment and update description for next run"
    - label: "Show full diff"
      description: "Display complete git diff for detailed review"
```

---

## Report Format

After completion, generate a final report with all actionable items:

```markdown
# Harvest Report — <timestamp>

## Run Information

- **Identifier:** <playlist-name-or-session-id>
- **Mode:** code / methodology / self
- **Type:** playlist / standard
- **Date:** <YYYY-MM-DD>

## Summary

- **Mode:** code / methodology / self
- **Verifications reviewed:** N (code harvest only)
- **Verified:** M (code harvest only)
- **Reopened:** K (code harvest only)
- **Findings accepted:** L (methodology harvest only)
- **Findings rejected:** P (methodology harvest only)

## Actionable Items

### Code Harvest Actions

<if code harvest mode>

#### Verifications

| Bead ID | Title | Decision |
|---------|-------|----------|
| br-xxx | <title> | Verified |
| br-yyy | <title> | Reopened |

#### New Beads Proposed

```bash
br create --title "<title>" --description "<description>"
```

#### Backlog Updates

<details of proposed updates>

---

### Methodology Harvest Actions

<if methodology harvest mode>

#### Self-Improvement Beads Created

| Bead ID | Title | Category | Guardrails Passed |
|---------|-------|----------|-------------------|
| br-aaa | HV: <title> | <category> | All 7 |

#### Rejected Candidates

| Description | Rejection Reason |
|-------------|-----------------|
| <finding> | Guardrail N: <reason> |

---

## Next Steps

1. Review actionable items above
2. Run proposed commands to create beads
3. Commit changes:
   ```bash
   git add .beads/ <affected-files>
   git commit -m "harvest: <mode> harvest for <run-id>"
   ```
4. Push when ready

## Harvest Status

**Marked as harvested:** <date>
**Harvest report:** `.sutra/harvests/<timestamp>-{code|methodology}.md`
**Run report (stamped):** `.sutra/reports/<filename>.md`
```

---

## When NOT to use this skill

- User asks about **harvest syntax or methodology** — answer directly from docs
- User wants to **run or monitor** a playlist — use `sutra --playlist`
- User wants to **validate** a playlist — use `sutra playlist init`
- User asks about a **different tool's harvest** — different context

## Quick command reference

| Command | Purpose |
|---------|---------|
| `bnr` | List issues awaiting verification |
| `bV` | Mark issue as verified |
| `breopen <id>` | Reopen an issue |
| `br create --title=...` | Create a new bead |
| `br list -l self-improvement` | View pending methodology findings |
| `ls .sutra/harvests/` | Browse harvest archive |
| `ls .sutra/reports/` | Browse run reports |

See also:
- `Harvest.md` — Code harvest methodology
- `HARVEST_METHODOLOGY.md` — Methodology harvest specification
- `skills/harvest/guardrails.md` — Guardrail reference
