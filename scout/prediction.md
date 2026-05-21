# Time Prediction

Baseline predictions for scout to consider alongside raw data.

See also: [[scout-cli.md]] | [[../metrics.md]] | [[../Harvest.md]]

---

## How It Works

1. **Compute baselines** — Multiple formulas each produce a prediction
2. **Pass to scout** — Baselines + raw metrics provided as context
3. **Scout decides** — Makes final prediction using baselines + qualitative judgment
4. **Track all** — Store each formula's prediction for comparison
5. **Harvest review** — Compare formula accuracy, eventually pick winner

---

## Formulas

All formulas use historical averages by difficulty as the foundation:

```
base[difficulty] = AVG(actual_minutes) WHERE difficulty = X
```

### Formula A: Difficulty Only (default)

```
prediction = base[difficulty]
```

Simplest baseline. No adjustments.

### Formula B: Actionability-Adjusted

```
prediction = base[difficulty] × (2 - actionability_score)
```

Low actionability (0.3) → multiply by 1.7
High actionability (0.9) → multiply by 1.1

### Formula C: Triage-Adjusted

```
prediction = base[difficulty] × (2 - triage_score)
```

Same logic but using structural importance from bv.

### Formula D: Combined

```
prediction = base[difficulty] × (1.5 - (actionability_score + triage_score) / 4)
```

Blends both scores. High scores → lower multiplier.

### Formula E: Recon-Based

```
prediction = base[difficulty] + (files_missing × 5) - (tests_found × 2)
```

Adjusts based on reconnaissance findings. Missing files add time, existing tests reduce it.

---

## Storage

In `.sutra/prediction-baselines.json`:

```json
{
  "base_minutes": {
    "trivial": 4,
    "easy": 12,
    "moderate": 28,
    "hard": 52,
    "complex": 90
  },
  "updated_at": "2026-02-01T10:00:00Z",
  "sample_size": 47
}
```

Updated at harvest from historical data:

```bash
sqlite3 .sutra/metrics.db "
SELECT difficulty, ROUND(AVG(actual_minutes)) as base
FROM task_metrics
WHERE actual_minutes IS NOT NULL
GROUP BY difficulty"
```

---

## Scout Prompt Context

The scout receives:

```
HISTORICAL BASELINES:
- Formula A (difficulty only): 28 min
- Formula B (actionability-adjusted): 34 min
- Formula C (triage-adjusted): 31 min
- Formula D (combined): 32 min
- Formula E (recon-based): 38 min

RAW METRICS:
- difficulty: moderate
- triage_score: 0.65
- actionability_score: 0.72
- files_found: 3
- files_missing: 2
- tests_found: 1

Make your prediction considering these baselines and your qualitative assessment.
```

The scout weighs the baselines against its investigation findings and predicts.

---

## Tracking

Store each formula's prediction in metrics:

```sql
CREATE TABLE IF NOT EXISTS prediction_tracking (
    issue_id TEXT,
    formula TEXT,
    predicted_minutes REAL,
    PRIMARY KEY (issue_id, formula)
);
```

At completion, compute error for each:

```sql
SELECT
    formula,
    COUNT(*) as n,
    ROUND(AVG(ABS(predicted_minutes - actual_minutes)), 1) as avg_error,
    ROUND(AVG(predicted_minutes / actual_minutes), 2) as avg_ratio
FROM prediction_tracking p
JOIN task_metrics m ON p.issue_id = m.issue_id
WHERE actual_minutes IS NOT NULL
GROUP BY formula
ORDER BY avg_error;
```

---

## Harvest: Pick Winner

After enough data (20+ completions), review formula performance:

```bash
sqlite3 .sutra/metrics.db "
SELECT formula, COUNT(*) as n,
       ROUND(AVG(ABS(predicted_minutes - actual_minutes)), 1) as avg_error
FROM prediction_tracking p
JOIN task_metrics m ON p.issue_id = m.issue_id
WHERE actual_minutes IS NOT NULL
GROUP BY formula
ORDER BY avg_error
LIMIT 1"
```

Once a formula consistently wins, set it as primary and drop the comparisons.

---

## Cold Start

No historical data → no baselines. Scout predicts based on:
- Triage score
- Difficulty assessment from recon
- Qualitative factors

These predictions seed the database.
