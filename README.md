# Ralph System Documentation

Master documentation for autonomous AI coding with beads, beads_viewer, and ralph-claude-code.

## Documents

| File | Description |
|------|-------------|
| [GUIDE.md](./GUIDE.md) | Complete operational guide for the integrated system |
| [TOOLS.md](./TOOLS.md) | Catalog of all tools with recommendations |
| [AI-TRIAGE.md](./AI-TRIAGE.md) | AI-enhanced actionability scoring concept |

## Quick Start

```bash
# 1. Setup project
ralph-setup my-project && cd my-project
bd init

# 2. Create and organize issues
bd create --title "..." --priority 2
bv --robot-triage | jq '.recommendations[:5]'

# 3. Run overnight
ralph --monitor

# 4. Morning review
bd list --status closed --since 24h
```

## The Stack

```
┌──────────────────────────────────────────────────────────────────┐
│                      ORCHESTRATION                               │
│  gastown           Multi-agent, multi-repo (enterprise)         │
│  choo-choo-ralph   5-phase workflow with harvesting             │
└──────────────────────────────────────────────────────────────────┘
                              ↑ optional
┌──────────────────────────────────────────────────────────────────┐
│                      EXECUTION                                   │
│  ralph-claude-code   Autonomous loop with safety gates ⭐        │
└──────────────────────────────────────────────────────────────────┘
                              ↑ uses
┌──────────────────────────────────────────────────────────────────┐
│                      INTELLIGENCE                                │
│  beads_viewer (bv)   PageRank + betweenness scoring             │
└──────────────────────────────────────────────────────────────────┘
                              ↑ analyzes
┌──────────────────────────────────────────────────────────────────┐
│                      FOUNDATION                                  │
│  beads (bd)          Git-backed issue tracking + dependencies   │
└──────────────────────────────────────────────────────────────────┘
```

**Recommended stack:** beads + bv + ralph-claude-code (see [TOOLS.md](./TOOLS.md))

## Source Repos

- beads: `/Users/admin/dev/beads`
- beads_viewer: `/Users/admin/dev/beads_viewer`
- ralph-claude-code: `/Users/admin/dev/ralph-claude-code`

## Key Insight

> Structured task graphs outperform markdown plans because they're queryable, dependency-aware, and don't require LLMs to waste cycles parsing text.
