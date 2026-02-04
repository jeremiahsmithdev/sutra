# Beads Verification Workflow

A systematic workflow for tracking human verification of closed issues, especially those completed during autonomous coding sessions.

## Overview

When Claude or an autonomous agent closes an issue, the work may not have been human-verified. This workflow ensures nothing slips through without proper testing.

### Prerequisites

The `set-state` command requires "event" as a valid issue type to create audit trail entries. Add it once per project:

```bash
bd config set types.custom "event"
```

This enables beads to create event issues that record state changes with timestamps, actors, and reasons.

### State Machine

```
[issue closed]
      │
      ▼
┌─────────────────────┐
│ verified=needs-review│  ← Set by Claude when closing
│ (awaiting human)     │
└─────────────────────┘
      │
      │ Human tests & confirms
      ▼
┌─────────────────────┐
│ verified=yes        │  ← Set by human after testing
│ (confirmed working) │
└─────────────────────┘
```

### When to Use Each State

| State | Set By | When |
|-------|--------|------|
| `needs-review` | Claude/Agent | Autonomous sessions, untested work, deferred testing |
| `yes` | Human | After manual verification confirms the work |
| (no label) | - | Legacy issues, trivial changes, or verified during implementation |

---

## For Claude / Autonomous Agents

### Marking Issues as Needs-Review

When closing an issue that hasn't been human-verified, **always** set the verification state with test instructions:

```bash
bd close <issue-id>
bd set-state <issue-id> verified=needs-review --reason "$(cat <<'EOF'
VERIFICATION INSTRUCTIONS:
1. [First step to test]
2. [Second step to test]
3. [Expected result]

NOTES: [Any context about what was implemented]
EOF
)"
```

### Example: Feature Implementation

```bash
bd close Chippie-xlu
bd set-state Chippie-xlu verified=needs-review --reason "$(cat <<'EOF'
VERIFICATION INSTRUCTIONS:
1. Create a new quote, expand the Line Items section
2. Add 3+ line items with different types (material, labor, equipment)
3. Enable "Show line items on documents" checkbox
4. Download PDF from quote detail page
5. Verify PDF shows: item type badges, description, qty, unit, rate, line totals
6. Verify footer shows: subtotal, GST (10%), adjustment if any, grand total
7. Create another quote WITHOUT line items - PDF should show simple single-row format

NOTES: Updated templates/pdf/quote_template.html with conditional line items display
EOF
)"
```

### Example: Bug Fix

```bash
bd close Chippie-abc
bd set-state Chippie-abc verified=needs-review --reason "$(cat <<'EOF'
VERIFICATION INSTRUCTIONS:
1. Navigate to /clients and click "Add Client"
2. Submit form with email "test@example.com"
3. Verify no 500 error, client appears in list
4. Check logs: tail -20 logs/chippie-error.log (should be clean)

NOTES: Fixed null pointer in ClientService.create() when company field empty
EOF
)"
```

### Example: Autonomous/Ralph Session

During ralph loops or autonomous sessions, **all closed issues** should be marked:

```bash
# In ralph prompt or agent instructions:
"When closing any issue, always run:
bd set-state <id> verified=needs-review --reason 'VERIFICATION INSTRUCTIONS:\n1. ...\n2. ...\n\nNOTES: ...'"
```

### Guidelines for Test Instructions

Good verification instructions are:

1. **User-focused** - Describe UI actions, not code variables
2. **Specific** - Exact steps, not "test the feature"
3. **Observable** - What to look for, expected outcomes
4. **Complete** - Cover happy path and edge cases if relevant
5. **Reproducible** - Anyone can follow them without reading code

Template:
```
VERIFICATION INSTRUCTIONS:
1. [Navigate to page/feature]
2. [User action to perform - clicks, inputs, selections]
3. [What to observe/verify in the UI]
4. [Edge case to test if applicable]

NOTES: [Files changed, implementation approach, gotchas]
```

**Bad example** (code-focused):
```
1. Set use_line_items=True on quote
2. Verify show_line_items flag renders correctly
```

**Good example** (user-focused):
```
1. Create a quote and expand the Line Items section
2. Add 2-3 line items, enable "Show on documents" checkbox
3. Download PDF and verify line items appear with totals
```

---

## For Humans (Morning Review)

### Quick Review Flow

```bash
# 1. See what needs review
bnr                    # Lists all issues with verified=needs-review

# 2. Select an issue (fzf picker)
#    - Preview panel shows issue details including verification instructions
#    - Press Enter to select

# 3. Perform the verification steps shown in the reason

# 4. Mark as verified
bV                    # Opens picker, select issue, mark as verified=yes
# Or with a note:
bV "Tested on mobile and desktop"
```

### Available Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `bneeds-review` | `bnr` | List issues awaiting verification |
| `bverify` | `bV` | Select and mark issue as verified |
| `bmark-review` | `bmr` | Mark a closed issue as needs-review |
| `bverified` | - | List already-verified issues |
| `bunverified` | `buv` | List closed issues with no verification state |

### Viewing Verification Instructions

The verification instructions are stored in the state change event. To see them:

```bash
# In the fzf preview (automatic)
bnr  # Select issue, preview shows details

# Or manually
bd show <issue-id>     # Full issue details
bd state <issue-id> verified  # Current state and reason
```

### Batch Verification

After a productive autonomous session, you might have many issues to verify:

```bash
bnr                    # See the queue
# Tab to multi-select several issues
# Enter to verify all selected
```

---

## Integration with Ralph/Autonomous Systems

### Ralph Loop Instructions

Add to your ralph prompt or agent configuration:

```
ISSUE CLOSURE PROTOCOL:
When closing any beads issue during this session:

1. Close the issue: bd close <id>

2. Mark for human verification with test instructions:
   bd set-state <id> verified=needs-review --reason "VERIFICATION INSTRUCTIONS:
   1. [Step to reproduce/test]
   2. [Expected behavior]
   3. [How to verify success]

   NOTES: [What was changed and why]"

3. Be specific - the human reviewer should be able to verify
   without reading the code or conversation history.
```

### Session End Summary

At the end of an autonomous session, Claude should summarize:

```
## Issues Closed This Session

| Issue | Title | Verification Status |
|-------|-------|---------------------|
| Chippie-abc | Fix client form | needs-review |
| Chippie-def | Update PDF template | needs-review |

Run `bnr` to see verification instructions for each.
```

---

## Audit Trail

When you use `set-state`, beads creates an **event issue** (e.g., `Chippie-abc.1`) that permanently records the state change. This is the audit trail.

### What gets recorded

Each event issue contains:
- **What changed**: `verified=needs-review` or `verified=yes`
- **When**: Timestamp of the change
- **Who**: Git user who made the change
- **Why**: The `--reason` text (verification instructions or confirmation notes)

### Viewing the audit trail

```bash
# View current state and reason for an issue
bd state <issue-id> verified

# View all events for an issue
bd show <issue-id> --events

# Example output:
# Chippie-abc.1: verified=needs-review (2024-01-15 by claude)
# Chippie-abc.2: verified=yes (2024-01-16 by jeremiah)
```

### Why events matter

- **Accountability**: Know who verified what and when
- **Instructions preserved**: The verification steps are permanently recorded
- **History**: See if something was re-verified after a regression
- **Not just labels**: Labels can be changed without history; events are permanent

---

## Best Practices

### For Claude/Agents

1. **Always mark autonomous work** - If no human watched you test it, mark it
2. **Write clear instructions** - Assume the reviewer has no context
3. **Include negative tests** - "Verify X does NOT happen"
4. **Note file changes** - Help reviewer know where to look if issues arise

### For Human Reviewers

1. **Review daily** - Don't let the queue grow stale
2. **Actually test** - Don't just mark verified without checking
3. **Reopen if broken** - `breopen` if verification reveals issues
4. **Add notes** - `bV "Tested on Safari, works"` creates audit trail

### For Mixed Sessions

During interactive sessions with Claude:
- Trivial changes verified during implementation → no label needed
- Complex changes you'll test later → ask Claude to mark `needs-review`
- End of session → review what's unmarked, decide if needs verification

---

## Troubleshooting

### "I have old closed issues with no verification state"

They're in limbo - neither verified nor needs-review. Options:
1. Ignore them (legacy)
2. Batch mark as verified if you trust them: `bd label add <id> verified:yes`
3. Review and verify properly

### "The verification instructions are unclear"

Reopen and ask Claude to provide better instructions, or verify based on the issue description and close with your own notes.

### "I verified but it's actually broken"

```bash
breopen <issue-id>     # Reopen the issue
# Fix the problem
bd close <issue-id>
bd set-state <issue-id> verified=needs-review --reason "..."
```
