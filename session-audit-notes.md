# Ralph Session Audit Notes — 2026-04-14

Issues discovered during a session focused on heredoc extraction, stress testing, and `playlist create` debugging. These notes are intended to inform a systematic audit of the entire ralph codebase for similar patterns.

---

## Issue 1: Heredocs exceeding 5-line extraction threshold

**Where found:** `lib/playlist.sh`, `lib/utils.sh`
**What:** Inline heredocs >5 lines violating the template extraction rule in CLAUDE.md.
**Fix applied:** Extracted to `templates/prompt_playlist_validate.txt`, `templates/state.txt`, `templates/state_playlist.txt`. Functions refactored to use `render_template()`.
**Audit pattern:** Search all `.sh` files for `<<EOF` or `<<'EOF'` and count lines between delimiters. Any heredoc >5 lines should be extracted to `templates/`.

---

## Issue 2: `playlist create --epic` arg parsing failure

**Where found:** `lib/args.sh`, `parse_arg_flags()`, line ~62
**What:** `parse_playlist_create_args "$@"` consumes all remaining args internally via `shift`, but those shifts are local to its scope. When it returns, the caller's `while` loop still sees `--epic` as `$1` and rejects it as unknown.
**Fix applied:** Added `return` after `parse_playlist_create_args "$@"` to exit the parsing loop.
**Audit pattern:** Any function called inside the `while/case` arg-parsing loop that receives `"$@"` and consumes args via `shift` has this bug. The caller's positional parameters are unaffected by the callee's shifts. Check all call sites inside `parse_arg_flags` that pass `"$@"` to sub-parsers.

---

## Issue 3: Early-exit commands crash on unbound variables

**Where found:** `lib/args.sh`, `dispatch_early_exit_action()`; `lib/invoke.sh`, line 81
**What:** `playlist_init` and `playlist_create` dispatch as early exits inside `parse_args()`, which runs before `load_state()` and `init_invoke()` in `initialize()`. When these commands call `invoke_claude`, globals like `total_loops`, `TIMEOUT_SECS`, `SESSION_NAME` are unbound, causing `set -u` failures.
**Fix applied:** Added `init_for_early_claude()` (calls `check_prereqs`, `load_state`, `init_invoke`) to `dispatch_early_exit_action` before Claude-needing actions.
**Audit pattern:** Any early-exit action in `dispatch_early_exit_action` that calls `invoke_claude` (directly or transitively) needs the invoke infrastructure initialized. Check all `ACTION` handlers for transitive Claude invocation. Also check whether any other globals assumed to be set by `initialize()` are referenced by early-exit paths.

---

## Issue 4: Bead descriptions leaking ralph internals into Claude prompts

**Where found:** `lib/playlist_init.sh`, `build_playlist_create_prompt()`; `lib/playlist.sh`, `build_playlist_semantic_prompt()`
**What:** Both functions passed full bead `description` fields to Claude. These descriptions contain implementation details (function names, file paths, acceptance criteria) meant for the implementing agent, not for the playlist-ordering or validation agent. Claude's task is to order beads and check file existence — it only needs titles and dependency IDs.
**Fix applied:** Both functions now extract only `title`, `parent`, and `dependencies` from bead JSON. Full descriptions omitted.
**Audit pattern:** Search for `br show .* --json` piped through `jq` extracting `.description`. Every call site should be evaluated: does the consumer actually need the full description, or just the title/metadata? The full description is appropriate when building a task execution prompt (e.g., `build_prompt` in `prompt.sh`) but not for ordering, validation, or display contexts.

---

## Issue 5: Output file written with input prompt instead of Claude's response

**Where found:** `lib/playlist_init.sh`, `run_playlist_create()`, line ~287
**What:** After `invoke_claude`, the code wrote `$prompt` to the output file. But `$prompt` holds the INPUT sent to Claude, not Claude's output. Claude's response goes to the stream-json log (`$INVOKE_LOG`). The output file ended up containing the entire prompt template + bead details, which then failed validation (every line of the prompt was treated as a bead ID).
**Fix applied:** Added `extract_playlist_from_log()` which parses `$INVOKE_LOG` for assistant text blocks via jq, extracts content from code fences, and writes that to the output file.
**Audit pattern:** Search for any code path that uses `$prompt` after `invoke_claude` returns. The `$prompt` global is write-before-invoke — it should never be read after invocation as if it contains the response. Any such read is a bug. Also check whether other `invoke_claude` callers need to capture output (currently only `playlist_create` does).

---

## Issue 6: Duplicated responsibilities between outer loop and inner loop

**Where found:** `templates/prompt_playlist_validate.txt` (original); `lib/playlist.sh`, `build_playlist_semantic_prompt()`
**What:** The Phase 2 semantic validation prompt told Claude to "add validation marker at the top of the playlist" — but `add_validation_marker()` in the outer loop already does this. Both tried to do the same job. Claude, running with `--dangerously-skip-permissions`, created a stray `playlist-validation-efficiency.playlist` instead of editing the correct file. The issue is NOT that Claude wrote a file (Claude writes files — that's its job). The issue is that the outer loop and the prompt gave Claude overlapping instructions, causing Claude to create a duplicate.
**Fix applied:** Removed the duplicated "add validation marker" instruction from the template. Claude still reads files to verify paths and can modify the playlist to add gate context — it just no longer duplicates what the outer loop handles mechanically.
**Audit pattern:** Review all prompt templates in `templates/` for instructions that duplicate outer-loop logic. If the outer loop already handles something deterministically (marker injection via `add_validation_marker()`, gate injection via `playlist_inject_gates()`), the prompt should not also ask Claude to do it. The principle: don't give Claude and the outer loop the same job. Claude handles judgment calls (verification, context-aware edits, implementation). The outer loop handles deterministic mechanical operations that don't require AI. Check `templates/prompt_bead.txt`, `templates/prompt_raw.txt`, and `templates/prompt_report.txt` for similar overlaps.

---

## Issue 7: Dry-run creating git branches as a side effect

**Where found:** `lib/lifecycle.sh`, `initialize()`, line 37
**What:** `ensure_correct_branch` ran unconditionally, even in `--dry-run` mode. Each dry-run playlist test created a new git branch (e.g., `simple.playlist`, `mixed.playlist`, etc.). Since `git checkout -b` carries dirty files forward, the user ended up stranded on an unrelated branch with no easy way back. `git checkout master` then failed because master had different file versions, and `git stash pop` produced merge conflicts.
**Fix applied:** Wrapped `ensure_correct_branch` in `if [[ "$DRY_RUN" != "true" ]]`.
**Audit pattern:** Review all side effects in `initialize()` and evaluate whether they should be skipped in dry-run mode. Candidates: branch creation, state file writes, log directory creation, session log capture (`exec > >(tee ...)`). The principle: `--dry-run` should be read-only with zero side effects on git state, filesystem state, and ralph state.

---

## Issue 8: Trailing newline eaten by command substitution

**Where found:** `lib/playlist_init.sh`, `build_playlist_create_prompt()`
**What:** `bead_details+=$(printf '%s\n' "$line")` — the `$()` command substitution strips trailing newlines, so bead entries were concatenated without separators. This caused the prompt to display all beads on one line.
**Fix applied:** Changed to direct string concatenation: `bead_details+="$line"$'\n'`
**Audit pattern:** Search for `+=$(printf` patterns across the codebase. Any string accumulation using `$(printf '%s\n' ...)` inside command substitution will lose its trailing newline. The fix is always the same: use `+=` with `$'\n'` directly.

---

## Cross-cutting themes for the auditor

1. **Outer loop vs inner loop boundary confusion** — Issue 4: the outer loop leaked its own implementation details (function names, file paths from bead descriptions) into prompts where Claude only needed titles and dependencies. Issue 6: the outer loop and prompt both told Claude to add a validation marker, duplicating responsibility. The principle: don't leak outer-loop internals into prompts, and don't give Claude and the outer loop the same job. Claude writes files and implements tasks — that's its purpose. But it shouldn't be told to do something the outer loop already handles deterministically. Audit all prompt templates for both patterns.

2. **Early-exit paths bypassing initialization** — Issue 3. Any new early-exit action added to `dispatch_early_exit_action` that transitively calls `invoke_claude` will hit the same unbound variable crash. Consider whether `init_for_early_claude` covers all needed state.

3. **`$prompt` is input-only after `invoke_claude`** — Issue 5. This is a naming/convention problem. `$prompt` is reused as both "what to send" and implicitly assumed to contain "what came back." Any new feature that needs Claude's output must extract it from the stream-json log.

4. **Dry-run purity** — Issue 7. Dry-run should have zero side effects. Audit all code paths that run during `--dry-run` for unintended writes (git, filesystem, state).

5. **Bash scoping gotchas** — Issues 2 and 8. `shift` inside a called function doesn't affect the caller. `$()` strips trailing newlines. These are bash fundamentals but easy to miss in a growing codebase.
