You're right, apologies — the context got compacted mid-research and the synthesis never made it through. I already have all the research findings though. Let me deliver the complete output now.

Here's the full picture on outer loop orchestrator options for your sutra + beads setup:

---

## The Core Architecture

You're looking at a **two-loop structure**:
- **Inner loop**: Claude (Opus 4.5 via Claude Code on Max plan) — does the actual implementation work
- **Outer loop**: Orchestrator that selects tasks, delegates to the inner loop, waits for completion, then queues the next task (including injecting quality gates like "review implementation", "test implementation")

The key question is: should that outer loop be deterministic (bash), a lightweight AI model, or something else?

## What Practitioners Actually Ship

**The overwhelming consensus from practitioners is: keep the outer loop dumb.**

Chris McDowell (who runs this in production with beads) wrote a whole post titled "Your Agent Orchestrator Is Too Clever" making the case that elaborate multi-agent systems get surpassed by simpler methods with better models. His outer loop is literally a bash script that polls beads:

(Note: "ralph" in the context of practitioners below refers to Geoffrey Huntley's original ralph bash-loop pattern, not this tool (now called sutra).)

```bash
READY_COUNT=$(bd count --status open 2>/dev/null || echo "0")
IN_PROGRESS=$(bd count --status in_progress 2>/dev/null || echo "0")
if [ "$READY_COUNT" = "0" ] && [ "$IN_PROGRESS" = "0" ]; then
    echo "No beads available. Waiting 20s for new work..."
    sleep 20
    continue
fi
```

Geoffrey Huntley (ralph's creator) reinforces this: *"While I was in SFO, everyone seemed to be trying to crack on multi-agent, agent-to-agent communication and multiplexing. At this stage, it's not needed."* He explicitly describes ralph as monolithic — a single process, single repo, one task per loop. The opposite of microservices, because non-deterministic microservices are "a red hot mess."

Richard Sutton's **bitter lesson** keeps proving true here: general methods that scale with computation beat specialised approaches that encode human knowledge.

## Your Three Options (Ranked)

### Option A: Deterministic Bash + Beads-BV (Recommended)

**Cost**: $0/day (compute only)
**Complexity**: ~100 lines of bash
**Reliability**: Highest — no API failures, no model hallucinations in orchestration layer

The beads-viewer (`bv`) tool has a `--robot-triage` flag that uses **graph algorithms** (PageRank + betweenness centrality + blocker analysis) to produce a composite score for task priority. No AI needed — it's pure deterministic graph analysis outputting JSON with ranked tasks, actionable items, and quick wins.

```bash
#!/bin/bash
# ralph-outer-loop.sh

while true; do
    # Get next task via graph-based scoring
    NEXT_TASK=$(bv --robot-triage | jq -r '.triage.recommendations[0].id')
    
    if [ -z "$NEXT_TASK" ] || [ "$NEXT_TASK" = "null" ]; then
        echo "No tasks ready. Waiting 20s..."
        sleep 20
        continue
    fi
    
    TASK_TITLE=$(bd show "$NEXT_TASK" | jq -r '.title')
    TASK_BODY=$(bd show "$NEXT_TASK" | jq -r '.body')
    
    # Mark in progress
    bd update "$NEXT_TASK" --status in_progress
    
    # Inner loop: Claude does the work
    claude -p "Implement the following task. When complete, output <promise>COMPLETE</promise>.
    
    Task: $TASK_TITLE
    Details: $TASK_BODY" --max-turns 50
    
    # Mark complete
    bd update "$NEXT_TASK" --status closed
    
    # Deterministic quality gate injection
    bd create --title "Review: $TASK_TITLE" \
      --type review --parent "$NEXT_TASK" --label ralph \
      --description "Verify implementation meets requirements, check edge cases, review code quality"
    
    bd create --title "Test: $TASK_TITLE" \
      --type test --parent "$NEXT_TASK" --label ralph \
      --description "Run test suite, verify coverage >80%, check integration tests pass"
    
    # Commit checkpoint
    git add -A && git commit -m "ralph: completed $TASK_TITLE"
done
```

Quality gates are injected **deterministically** — no AI needed to decide "after implementation, we should review and test." That's just a workflow rule.

### Option B: Hybrid (Deterministic + Occasional GPT-4o-mini)

**Cost**: ~$1-3/day
**Complexity**: ~300 lines (bash + API calls)

Uses beads-BV for 95% of decisions, but calls a cheap model for ambiguous situations:
- Breaking down a bead that's too large for a single inner loop iteration
- Generating specific quality gate descriptions based on what was actually implemented
- Resolving priority conflicts when multiple tasks have similar scores

```bash
# Only call AI when deterministic scoring is ambiguous
TOP_SCORES=$(bv --robot-triage | jq '[.triage.recommendations[:3] | .[].score]')
SPREAD=$(echo "$TOP_SCORES" | jq '.[0] - .[2]')

if (( $(echo "$SPREAD < 0.1" | bc -l) )); then
    # Scores too close — ask cheap model to break the tie
    DECISION=$(curl -s https://api.openai.com/v1/chat/completions \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -d '{
        "model": "gpt-4o-mini",
        "response_format": {"type": "json_object"},
        "messages": [{"role": "user", "content": "Given these 3 tasks with similar priority scores, which should be done first and why? Return JSON with {\"task_id\": \"...\", \"reason\": \"...\"}. Tasks: '"$(bv --robot-triage | jq '.triage.recommendations[:3]')"'"}]
      }' | jq -r '.choices[0].message.content')
    NEXT_TASK=$(echo "$DECISION" | jq -r '.task_id')
else
    NEXT_TASK=$(bv --robot-triage | jq -r '.triage.recommendations[0].id')
fi
```

### Option C: Full AI Orchestrator (GPT-4o-mini or Gemini Flash-Lite)

**Cost**: $0.25-$0.75/day
**Complexity**: Higher — needs robust prompt engineering

Every routing decision goes through a lightweight model. The model receives a minimal context (agent roster, current beads state, recent completion log) and returns JSON routing decisions.

**Cost comparison** for ~10K orchestration decisions/day at ~500 tokens average:

| Model | Input Cost/1M | Output Cost/1M | Est. Daily Cost |
|---|---|---|---|
| Deterministic (Bash+BV) | $0 | $0 | **$0** |
| Gemini Flash-Lite | $0.10 | $0.40 | **~$0.25** |
| GPT-4o-mini | $0.15 | $0.60 | **~$0.75** |
| Claude Haiku 4.5 | $1.00 | $5.00 | **~$5.00** |
| Ollama (local) | $0 | $0 | **$0** (+ electricity) |

## What I'd Recommend for You

**Go with Option A (deterministic bash + beads-BV)** and here's why:

1. **Your whole goal is to avoid wasting Claude Max on orchestration.** A deterministic outer loop uses zero tokens, zero API calls, zero model capacity for routing decisions.

2. **BV's graph algorithms are genuinely smart** — PageRank for task centrality, betweenness for bottleneck detection, blocker analysis. This isn't a dumb FIFO queue; it's algorithmically sophisticated task selection without being AI-expensive.

3. **Quality gates don't need AI to create.** "After implementing X, review X and test X" is a deterministic workflow rule. You can get fancier later (having the review task's description reflect what was actually built) but start simple.

4. **The bitter lesson applies.** Every practitioner who tried complex multi-agent orchestration has simplified back toward bash loops. The models are good enough that a for-loop is a legitimate orchestration strategy.

5. **You can always upgrade.** If you hit cases where deterministic selection fails (maybe 1 in 20 tasks), bolt on a GPT-4o-mini call for just those cases (Option B). You'll know when you need it because you'll see the outer loop picking suboptimal tasks.

## Existing Tools Worth Knowing About

These are external tools in the ecosystem (not sutra):

- **ralph-tui** (github.com/subsy/ralph-tui): TypeScript TUI orchestrator with native beads support (`--epic my-epic-id`), headless mode, session persistence, crash recovery, sandbox isolation. Supports Claude Code, OpenCode, Gemini CLI, Codex, Kiro CLI. This is probably the most polished outer loop implementation.

- **ralph-orchestrator** (github.com/mikeyobrien/ralph-orchestrator): Hat-based system with backpressure gates (tests, lint, typecheck must pass), Telegram integration for human-in-loop, 31 presets. Multi-backend support.

- **ralph-kit** (Josh Chisholm): Ready-to-use template combining ralph loops with beads specifically.

The simplest path: write ~100 lines of bash that polls beads-BV for the next task, spawns Claude Code, waits for completion, injects quality gate beads, and loops. That's the whole thing — and that's essentially what sutra is.
