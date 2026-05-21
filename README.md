# Sutra System Documentation

Master documentation for autonomous AI coding with beads, beads_viewer, and sutra.

## Documents

| File | Description |
|------|-------------|
| [GUIDE.md](./GUIDE.md) | Complete operational guide for the integrated system |
| [TOOLS.md](./TOOLS.md) | Catalog of tools and ecosystem context |
| [AI-TRIAGE.md](./AI-TRIAGE.md) | AI-enhanced actionability scoring concept |

## Quick Start

```bash
# 1. Setup project
sutra --init && cd my-project
br init

# 2. Create and organize issues
br create --title "..." --priority 2
bv --robot-triage | jq '.recommendations[:5]'

# 3. Run overnight
sutra --monitor

# 4. Morning review
br list --status closed --since 24h
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
│  sutra               Autonomous loop with safety gates ⭐        │
└──────────────────────────────────────────────────────────────────┘
                              ↑ uses
┌──────────────────────────────────────────────────────────────────┐
│                      INTELLIGENCE                                │
│  beads_viewer (bv)   PageRank + betweenness scoring             │
└──────────────────────────────────────────────────────────────────┘
                              ↑ analyzes
┌──────────────────────────────────────────────────────────────────┐
│                      FOUNDATION                                  │
│  beads (br)          Git-backed issue tracking + dependencies   │
└──────────────────────────────────────────────────────────────────┘
```

**Recommended stack:** beads + bv + sutra (see [TOOLS.md](./TOOLS.md))

## Source Repos

- beads: `/Users/admin/dev/beads`
- beads_viewer: `/Users/admin/dev/beads_viewer`
- sutra: `/Users/admin/dev/ralph`

## Key Insight

> Structured task graphs outperform markdown plans because they're queryable, dependency-aware, and don't require LLMs to waste cycles parsing text.
