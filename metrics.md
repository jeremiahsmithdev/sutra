# Workflow Metrics

Data-driven calibration for the sutra system. Store everything deterministically; analyse qualitatively in the morning.

See also: [[PHILOSOPHY.md]] | [[Harvest.md]] | [[AI-TRIAGE.md]]

---

## Principle

**Store artefacts, not decisions.** Capture metrics at each workflow stage. Compare predictions against actuals after completion. Surface anomalies for human + AI analysis during [[Harvest.md|harvest]].

The data collection is deterministic — no AI needed. The qualitative analysis happens in the morning, with Claude pointed at the data that indicates bottlenecks.

---

## What to Capture

### At Task Selection (outer loop picks a task)

| Field | Source | Description |
|-------|--------|-------------|
| `issue_id` | beads | The bead ID |
| `selected_at` | timestamp | When task was picked |
| `bv_triage_score` | `bv --robot-triage` | Structural importance (0-1) |
| `bv_pagerank` | `bv --robot-insights` | Graph centrality |
| `bv_betweenness` | `bv --robot-insights` | Bottleneck score |
| `priority` | beads | Original P0-P4 |

### At Scout Priming (if scout is used)

| Field | Source | Description |
|-------|--------|-------------|
| `issue_id` | beads | The bead ID |
| `primed_at` | timestamp | When scout ran |
| `actionability_score` | scout | Predicted actionability (0-1) |
| `confidence` | scout | high/medium/low/blocked |
| `difficulty` | scout | trivial/easy/moderate/hard/complex |
| `estimated_minutes` | scout | Predicted time to completion |
| `entry_points` | scout | JSON array of file:line predictions |
| `approach` | scout | One-sentence approach |
| `files_found` | scout recon | Count of referenced files that exist |
| `files_missing` | scout recon | Count of referenced files not found |
| `tests_found` | scout recon | Count of related tests found |

### At Task Completion (inner loop finishes)

| Field | Source | Description |
|-------|--------|-------------|
| `issue_id` | beads | The bead ID |
| `started_at` | timestamp | When inner loop began |
| `completed_at` | timestamp | When task closed |
| `duration_seconds` | derived | Time from start to completion |
| `actual_iterations` | sutra logs | Inner loop turns (secondary metric) |
| `files_modified` | git diff | Files changed during implementation |
| `lines_changed` | git diff | Lines added + removed |
| `tests_added` | git diff | New test files/functions |
| `tests_passed` | test runner | Boolean |
| `entry_point_hit` | comparison | Did implementation touch predicted entry points? |
| `exit_reason` | sutra | complete/blocked/timeout/circuit_breaker |
| `quality_gate_result` | follow-up beads | pass/fail/pending |

### At Harvest (morning review)

| Field | Source | Description |
|-------|--------|-------------|
| `issue_id` | beads | The bead ID |
| `reviewed_at` | timestamp | When human reviewed |
| `verdict` | human | merged/reverted/partial |
| `notes` | human | Free-text observations |

---

## SQLite Schema

```sql
-- .sutra/metrics.db

CREATE TABLE IF NOT EXISTS task_selection (
    issue_id TEXT PRIMARY KEY,
    selected_at TEXT NOT NULL,
    bv_triage_score REAL,
    bv_pagerank REAL,
    bv_betweenness REAL,
    priority INTEGER
);

CREATE TABLE IF NOT EXISTS scout_priming (
    issue_id TEXT PRIMARY KEY,
    primed_at TEXT NOT NULL,
    actionability_score REAL,
    confidence TEXT,
    difficulty TEXT,
    estimated_minutes REAL,
    entry_points TEXT,  -- JSON array
    approach TEXT,
    files_found INTEGER,
    files_missing INTEGER,
    tests_found INTEGER
);

CREATE TABLE IF NOT EXISTS task_completion (
    issue_id TEXT PRIMARY KEY,
    started_at TEXT NOT NULL,
    completed_at TEXT NOT NULL,
    duration_seconds INTEGER,
    actual_iterations INTEGER,
    files_modified INTEGER,
    lines_changed INTEGER,
    tests_added INTEGER,
    tests_passed INTEGER,  -- 0 or 1
    entry_point_hit INTEGER,  -- 0 or 1
    exit_reason TEXT,
    quality_gate_result TEXT
);

CREATE TABLE IF NOT EXISTS harvest_review (
    issue_id TEXT PRIMARY KEY,
    reviewed_at TEXT NOT NULL,
    verdict TEXT,
    notes TEXT
);

-- Composite view for analysis
CREATE VIEW IF NOT EXISTS task_metrics AS
SELECT
    s.issue_id,
    s.selected_at,
    s.bv_triage_score,
    p.actionability_score,
    p.estimated_minutes,
    p.difficulty,
    p.entry_points,
    c.started_at,
    c.completed_at,
    c.duration_seconds,
    ROUND(c.duration_seconds / 60.0, 1) AS actual_minutes,
    c.actual_iterations,
    c.entry_point_hit,
    c.exit_reason,
    c.quality_gate_result,
    h.verdict,
    h.notes,
    -- Derived metrics
    CASE WHEN p.estimated_minutes > 0
         THEN ROUND((c.duration_seconds / 60.0) / p.estimated_minutes, 2)
         ELSE NULL END AS time_ratio,
    CASE WHEN c.entry_point_hit = 1 THEN 'hit' ELSE 'miss' END AS entry_point_accuracy
FROM task_selection s
LEFT JOIN scout_priming p ON s.issue_id = p.issue_id
LEFT JOIN task_completion c ON s.issue_id = c.issue_id
LEFT JOIN harvest_review h ON s.issue_id = h.issue_id;
```

---

## Data Collection Points

### 1. Outer Loop — on task selection

```bash
# After selecting next task, before marking in_progress
sqlite3 .sutra/metrics.db "
INSERT OR REPLACE INTO task_selection
VALUES (
    '$ISSUE_ID',
    '$(date -Iseconds)',
    $(bv --robot-triage | jq -r ".recommendations[] | select(.id==\"$ISSUE_ID\") | .triage_score // 0"),
    $(bv --robot-insights | jq -r ".pagerank[\"$ISSUE_ID\"] // 0"),
    $(bv --robot-insights | jq -r ".betweenness[\"$ISSUE_ID\"] // 0"),
    $(bd show $ISSUE_ID --json | jq -r '.priority // 2')
);"
```

### 2. Scout — on priming

```bash
# After scout prime completes, extract from the report
REPORT=$(cat .beads/scout/${ISSUE_ID}.json)
sqlite3 .sutra/metrics.db "
INSERT OR REPLACE INTO scout_priming
VALUES (
    '$ISSUE_ID',
    '$(echo "$REPORT" | jq -r '.primed_at')',
    $(echo "$REPORT" | jq -r '.analysis.actionability_score'),
    '$(echo "$REPORT" | jq -r '.analysis.confidence')',
    '$(echo "$REPORT" | jq -r '.analysis.difficulty')',
    $(echo "$REPORT" | jq -r '.analysis.estimated_minutes'),
    '$(echo "$REPORT" | jq -c '.analysis.entry_points')',
    '$(echo "$REPORT" | jq -r '.analysis.approach')',
    $(echo "$REPORT" | jq -r '.recon.files_found | length'),
    $(echo "$REPORT" | jq -r '.recon.files_missing | length'),
    $(echo "$REPORT" | jq -r '.recon.tests_found | length')
);"
```

### 3. Inner Loop — on start

```bash
# Record start time when inner loop begins
START_TIME=$(date -Iseconds)
START_EPOCH=$(date +%s)
```

### 4. Inner Loop — on completion

```bash
# After task closes, before injecting quality gates
END_EPOCH=$(date +%s)
DURATION_SECONDS=$((END_EPOCH - START_EPOCH))

MODIFIED_FILES=$(git diff --name-only HEAD~1 | wc -l)
LINES_CHANGED=$(git diff --stat HEAD~1 | tail -1 | grep -oE '[0-9]+' | paste -sd+ | bc)
PREDICTED_ENTRIES=$(sqlite3 .sutra/metrics.db "SELECT entry_points FROM scout_priming WHERE issue_id='$ISSUE_ID'")
ENTRY_HIT=0
for entry in $(echo "$PREDICTED_ENTRIES" | jq -r '.[]' | cut -d: -f1); do
    git diff --name-only HEAD~1 | grep -q "$entry" && ENTRY_HIT=1 && break
done

sqlite3 .sutra/metrics.db "
INSERT OR REPLACE INTO task_completion
VALUES (
    '$ISSUE_ID',
    '$START_TIME',
    '$(date -Iseconds)',
    $DURATION_SECONDS,
    $ACTUAL_ITERATIONS,
    $MODIFIED_FILES,
    $LINES_CHANGED,
    $(git diff --name-only HEAD~1 | grep -cE 'test|spec' || echo 0),
    $([ $TESTS_PASSED = true ] && echo 1 || echo 0),
    $ENTRY_HIT,
    '$EXIT_REASON',
    'pending'
);"
```

### 5. Harvest — on human review

```bash
# Manual or via slash command
sqlite3 .sutra/metrics.db "
INSERT OR REPLACE INTO harvest_review
VALUES (
    '$ISSUE_ID',
    '$(date -Iseconds)',
    '$VERDICT',  -- merged/reverted/partial
    '$NOTES'
);"
```

---

## Bottleneck Queries

### Scout accuracy — time estimates

```sql
-- How accurate are scout time predictions?
SELECT
    difficulty,
    COUNT(*) as count,
    ROUND(AVG(estimated_minutes), 1) as avg_predicted,
    ROUND(AVG(actual_minutes), 1) as avg_actual,
    ROUND(AVG(time_ratio), 2) as avg_ratio
FROM task_metrics
WHERE actual_minutes IS NOT NULL AND estimated_minutes IS NOT NULL
GROUP BY difficulty;

-- Ratio > 2.0 means scout underestimated by 2x+
-- Ratio < 0.5 means scout overestimated by 2x+
```

### Time distribution by difficulty

```sql
-- Actual completion times to calibrate future estimates
SELECT
    difficulty,
    COUNT(*) as count,
    ROUND(MIN(actual_minutes), 1) as min_minutes,
    ROUND(AVG(actual_minutes), 1) as avg_minutes,
    ROUND(MAX(actual_minutes), 1) as max_minutes
FROM task_metrics
WHERE actual_minutes IS NOT NULL
GROUP BY difficulty;
```

### Scout accuracy — entry point predictions

```sql
-- How often do predicted entry points get touched?
SELECT
    COUNT(*) as total,
    SUM(entry_point_hit) as hits,
    ROUND(100.0 * SUM(entry_point_hit) / COUNT(*), 1) as hit_rate_pct
FROM task_metrics
WHERE entry_point_hit IS NOT NULL;
```

### Workflow bottlenecks — where tasks fail

```sql
-- Exit reasons breakdown
SELECT
    exit_reason,
    COUNT(*) as count,
    AVG(actual_iterations) as avg_iterations
FROM task_completion
GROUP BY exit_reason
ORDER BY count DESC;
```

### Score calibration — do high scores complete faster?

```sql
-- Correlation between scores and outcomes
SELECT
    CASE
        WHEN bv_triage_score >= 0.7 THEN 'high'
        WHEN bv_triage_score >= 0.4 THEN 'medium'
        ELSE 'low'
    END as score_band,
    COUNT(*) as count,
    ROUND(AVG(actual_minutes), 1) as avg_minutes,
    SUM(CASE WHEN verdict = 'merged' THEN 1 ELSE 0 END) as merged,
    SUM(CASE WHEN verdict = 'reverted' THEN 1 ELSE 0 END) as reverted
FROM task_metrics
GROUP BY score_band;
```

### Actionability vs outcome

```sql
-- Does high actionability predict faster completion?
SELECT
    CASE
        WHEN actionability_score >= 0.7 THEN 'high'
        WHEN actionability_score >= 0.4 THEN 'medium'
        ELSE 'low'
    END as actionability_band,
    COUNT(*) as count,
    ROUND(AVG(actual_minutes), 1) as avg_minutes,
    ROUND(100.0 * SUM(CASE WHEN verdict = 'merged' THEN 1 ELSE 0 END) / COUNT(*), 1) as merge_rate_pct
FROM task_metrics
WHERE actionability_score IS NOT NULL
GROUP BY actionability_band;
```

---

## Harvest Integration

The morning [[Harvest.md|harvest]] uses this data in two phases:

### Phase 1: Data surfaces anomalies (deterministic)

```bash
# Quick anomaly check — issues where time predictions were way off
sqlite3 .sutra/metrics.db "
SELECT issue_id, difficulty, estimated_minutes, actual_minutes, time_ratio
FROM task_metrics
WHERE time_ratio > 3.0 OR time_ratio < 0.3
ORDER BY time_ratio DESC;"
```

### Phase 2: AI analyses anomalies (qualitative)

A slash command (e.g., `/harvest-analysis`) points Claude at:
1. The anomalies surfaced above
2. The scout reports for those issues
3. The git diffs from those tasks

Claude then identifies:
- Why the scout's prediction was wrong
- Patterns in scout miscalibration (e.g., always underestimates refactoring tasks)
- Prompt improvements to prevent recurrence
- Whether the scout's entity extraction or recon logic needs adjustment

---

## File Location

```
.sutra/
├── metrics.db          # SQLite database
├── metrics-schema.sql  # Schema for reference
└── logs/
    └── sutra.log
```

The database lives in `.sutra/` alongside other sutra state. It's gitignored (local to the machine running sutra) but can be exported for analysis.

---

## Design Notes

**Why SQLite?**
- Deterministic, no external dependencies
- Queryable with standard SQL
- Single file, easy to backup/restore
- Fits the philosophy: no AI in the data layer

**Why separate tables?**
- Each stage happens at a different time
- Not all tasks go through all stages (scout is optional)
- Allows partial data (completion without scout priming)

**Why a view?**
- Single query surface for analysis
- Joins handled once, used everywhere
- Easy to extend with derived metrics
