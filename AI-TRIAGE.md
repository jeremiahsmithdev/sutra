# AI-Enhanced Issue Triage

Layering semantic investigation on top of structural scoring.

---

## The Gap in Current Scoring

BV's triage_score is **purely structural** — it analyzes the graph:

```
PageRank     → "This node is important in the dependency web"
Betweenness  → "This node is a bottleneck on critical paths"
BlockerRatio → "Completing this unblocks N downstream tasks"
```

What it **cannot** answer:

- Does the referenced file actually exist?
- Has the described problem already been fixed?
- Is the issue description coherent with current codebase?
- Are there obvious entry points for implementation?
- Does the issue reference deprecated APIs?

**Structural importance ≠ Actionability**

A P0 issue with perfect PageRank might reference code that was deleted last week.

---

## The Concept: Actionability Score

Layer an AI investigation pass on top of BV's structural scoring:

```
┌─────────────────────────────────────────────────────────────────┐
│                    EXISTING (Structural)                        │
│                                                                 │
│  bv --robot-triage                                             │
│    → triage_score: 0.72                                        │
│    → quick_wins, blockers_to_clear                             │
│    → Based on: graph position, dependencies, priority          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    NEW LAYER (Semantic)                         │
│                                                                 │
│  ai-triage --scan                                              │
│    → actionability_score: 0.85                                 │
│    → confidence: "high"                                        │
│    → investigation_notes: "Found handleAuth() at auth.ts:45"   │
│    → Based on: codebase grep, file existence, pattern matching │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    COMBINED OUTPUT                              │
│                                                                 │
│  {                                                              │
│    id: "bd-a3f8e9",                                            │
│    title: "Fix authentication bypass",                         │
│    triage_score: 0.72,         // structural importance        │
│    actionability_score: 0.85,  // semantic feasibility         │
│    combined_score: 0.78,       // weighted composite           │
│    confidence: "high",                                         │
│    entry_point: "src/auth.ts:45",                              │
│    investigation_notes: "Found handleAuth(), tests exist"      │
│  }                                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Investigation Checks

For each issue, run quick verification:

### 1. Entity Extraction

Parse issue title and description for:
- File paths mentioned (`src/auth.ts`, `lib/utils.js`)
- Function/class names (`handleAuth`, `UserSession`)
- API endpoints (`/api/login`, `POST /users`)
- Error messages (stack traces, error codes)
- Keywords (feature names, component names)

### 2. Existence Checks

```bash
# File exists?
[ -f "$mentioned_file" ] && score+=0.2

# Function found?
grep -q "function $func_name" src/**/*.ts && score+=0.2

# Similar patterns exist?
grep -rq "$keyword" src/ && score+=0.15
```

### 3. Staleness Detection

```bash
# Has the area changed recently?
git log --oneline -5 -- "$mentioned_file"

# Is there active WIP?
bd list --status in_progress | grep -q "$related_pattern"
```

### 4. Test Coverage Check

```bash
# Tests exist for the area?
[ -f "tests/${component}.test.ts" ] && score+=0.1
```

### 5. Blocker Detection

- References to external services
- Version-specific APIs
- Dependencies on other unfinished work

---

## Scoring Formula

```
actionability_score = base_confidence
    + (files_found × 0.2)
    + (functions_found × 0.2)
    + (patterns_found × 0.15)
    + (tests_exist × 0.1)
    + (recent_stability × 0.1)
    - (conflicting_wip × 0.3)
    - (stale_references × 0.25)
```

**Confidence Levels:**
- `high` — All referenced entities found, clear entry point
- `medium` — Some entities found, investigation needed
- `low` — Few entities found, may need clarification
- `blocked` — Critical blockers detected

---

## Implementation Approaches

### Approach A: Shell Script Wrapper

Minimal, Unix-philosophy approach:

```bash
#!/bin/bash
# ai-triage.sh - Scan issues and add actionability scores

# Get triage from bv
TRIAGE=$(bv --robot-triage)

# For each recommendation
echo "$TRIAGE" | jq -r '.recommendations[].id' | while read id; do
    # Get issue details
    ISSUE=$(bd show "$id" --json)
    TITLE=$(echo "$ISSUE" | jq -r '.title')
    DESC=$(echo "$ISSUE" | jq -r '.description')

    # Extract entities (simple grep patterns)
    FILES=$(echo "$DESC" | grep -oE '[a-zA-Z0-9_/]+\.(ts|js|py|go)' || true)
    FUNCS=$(echo "$DESC" | grep -oE '\b[a-z][a-zA-Z0-9_]+\(' | tr -d '(' || true)

    # Check existence
    score=0.5  # base
    for f in $FILES; do
        [ -f "$f" ] && score=$(echo "$score + 0.2" | bc)
    done
    for fn in $FUNCS; do
        grep -rq "$fn" src/ 2>/dev/null && score=$(echo "$score + 0.15" | bc)
    done

    # Output enriched record
    echo "{\"id\":\"$id\",\"actionability\":$score}"
done
```

### Approach B: Claude-Powered Investigation

Use Claude Code itself to investigate:

```bash
#!/bin/bash
# ai-investigate.sh - Use Claude to investigate an issue

ISSUE_ID=$1
ISSUE=$(bd show "$ISSUE_ID" --json)

claude -p "
You are investigating issue $ISSUE_ID for actionability.

Issue details:
$(echo "$ISSUE" | jq -r '.title, .description')

Do a BRIEF investigation (max 2 minutes):
1. Grep for mentioned files/functions
2. Check if referenced code exists
3. Look for related tests
4. Note any obvious blockers

Output ONLY this JSON:
{
  \"actionability_score\": 0.0-1.0,
  \"confidence\": \"high|medium|low|blocked\",
  \"entry_points\": [\"file:line\", ...],
  \"blockers\": [\"description\", ...],
  \"notes\": \"brief investigation summary\"
}
"
```

### Approach C: Batch Pre-Scan Agent

Run nightly before ralph execution:

```bash
#!/bin/bash
# pre-scan.sh - Scan all issues before overnight run

OUTPUT_FILE=".beads/actionability.jsonl"
> "$OUTPUT_FILE"

# Get all open issues sorted by triage score
bv --robot-triage | jq -r '.recommendations[].id' | while read id; do
    result=$(./ai-investigate.sh "$id")
    echo "{\"id\":\"$id\",\"scan\":$result,\"scanned_at\":\"$(date -Iseconds)\"}" >> "$OUTPUT_FILE"
done

echo "Scanned $(wc -l < "$OUTPUT_FILE") issues"
```

---

## Integration with Ralph

### Modified Task Selection

Instead of pure triage_score, use combined:

```bash
# In PROMPT.md or ralph's task selection:

# Get actionability data
ACTIONABILITY=$(cat .beads/actionability.jsonl 2>/dev/null || echo "{}")

# Get triage data
TRIAGE=$(bv --robot-triage)

# Combine scores (example: 60% triage, 40% actionability)
NEXT=$(echo "$TRIAGE" | jq -r --slurpfile act <(echo "$ACTIONABILITY") '
  .recommendations
  | map(. + {
      actionability: ($act[] | select(.id == .id) | .scan.actionability_score // 0.5),
      combined: (.triage_score * 0.6) + (($act[] | select(.id == .id) | .scan.actionability_score // 0.5) * 0.4)
    })
  | sort_by(-.combined)
  | .[0].id
')
```

### Storing Results

Option 1: Separate file (`.beads/actionability.jsonl`)
- Keeps beads clean
- Easy to regenerate
- Grep/jq friendly

Option 2: Issue metadata
```bash
bd update "$id" --metadata '{"actionability": 0.85, "last_scan": "2024-01-25"}'
```

Option 3: Issue comments
```bash
bd comment "$id" "AI Investigation ($(date)):
- Actionability: 0.85
- Entry point: src/auth.ts:45
- Notes: Found handleAuth(), tests exist"
```

---

## Workflow Integration

### Pre-Ralph Scan

```bash
# Before starting ralph overnight:

# 1. Run AI triage scan
./ai-triage-scan.sh

# 2. Review low-actionability issues
cat .beads/actionability.jsonl | jq 'select(.scan.actionability_score < 0.5)'

# 3. Fix or defer problematic issues
bd update bd-xyz --status deferred --comment "Needs clarification"

# 4. Start ralph with clean actionable set
ralph --monitor
```

### Continuous Scanning

Run as daemon or cron job:
```bash
# Scan new issues as they're created
while true; do
    # Find issues without actionability scan
    bd list --status open --json | jq -r '.[] | select(.metadata.last_scan == null) | .id' | while read id; do
        ./ai-investigate.sh "$id"
        bd update "$id" --metadata "{\"last_scan\": \"$(date -Iseconds)\"}"
    done
    sleep 300  # Every 5 minutes
done
```

---

## Benefits

1. **Filter out stale issues** before wasting compute on them
2. **Surface hidden blockers** that aren't in the dependency graph
3. **Provide entry points** so Claude starts in the right place
4. **Reduce false starts** where Claude searches for non-existent code
5. **Prioritize clarity** — well-described issues score higher

---

## Caveats

1. **Cost** — Each investigation uses API calls
2. **Staleness** — Scans become stale as code changes
3. **False negatives** — Grep may miss renamed entities
4. **Scope creep** — Keep investigations brief (2 min max)

**Mitigation:**
- Scan only top N issues by triage_score
- Re-scan only when issue or code changes
- Use cheap/fast investigation methods first
- Cache results with TTL

---

## Example Output

```json
{
  "id": "bd-a3f8e9",
  "title": "Fix authentication bypass in handleAuth",
  "triage_score": 0.72,
  "actionability_scan": {
    "actionability_score": 0.85,
    "confidence": "high",
    "entry_points": [
      "src/auth/handler.ts:45",
      "src/auth/middleware.ts:23"
    ],
    "blockers": [],
    "related_tests": [
      "tests/auth/handler.test.ts"
    ],
    "notes": "Found handleAuth() with 3 call sites. Tests exist. No conflicting WIP."
  },
  "combined_score": 0.78,
  "recommendation": "Ready for implementation"
}
```

---

## Next Steps

1. **Prototype** the shell script wrapper (Approach A)
2. **Test** on 10-20 issues manually
3. **Measure** how often actionability catches stale issues
4. **Iterate** on scoring weights based on results
5. **Integrate** into pre-ralph workflow
