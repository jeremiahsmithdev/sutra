# Scout CLI — Dispatching Scouts for Issue Triage

CLI for dispatching **scouts** — LLM agents that investigate bead issues before execution. Each scout primes one issue with reconnaissance and actionability assessment.

See also: [[prediction.md]] | [[conf.md]] | [[ralph-scout.md]]

## Terminology

- **Scout** — An LLM agent (Claude Haiku) investigating a single bead issue
- **Scout CLI** — This script; dispatches and manages scouts
- **Priming** — The process of a scout investigating an issue and storing its report

## Flow per Scout

1. Receive one bead issue to investigate
2. Mechanical reconnaissance (file existence, grep, git log, test coverage, WIP conflicts)
3. Package evidence as JSON
4. Scout agent synthesizes findings → actionability score, entry points, briefing
5. Time prediction via formula (or scout estimate if cold start) — see [[prediction.md]]
6. Store structured report in `.beads/scout/<id>.json`

## Commands

| Command | Description |
|---|---|
| `scout prime bd-a3f8e9` | Prime a specific issue |
| `scout prime --unprimed` | Prime all open issues lacking scout data |
| `scout prime --all` | Re-prime all open issues |
| `scout prime --stale` | Re-prime issues with expired scans |
| `scout prime --top 5` | Prime top 5 by BV triage score |
| `scout status` | Board view of all issues with scores |
| `scout report bd-a3f8e9` | Full JSON report |
| `scout briefing bd-a3f8e9` | Just the briefing text (for prompt injection) |
| `scout score bd-a3f8e9` | Just the actionability score (for scripting) |
| `scout clear bd-a3f8e9` | Clear scout data for an issue |
| `scout clear --all` | Clear all scout data |

## Source

```bash
#!/usr/bin/env bash
# ===========================================================================
# scout - AI-enhanced issue triage for beads
# ===========================================================================
#
# Primes beads issues with AI reconnaissance to assess actionability
# before passing to a ralph loop for implementation.
#
# The scout does two things:
#   1. Mechanical reconnaissance (grep, find, git log) - collects evidence
#   2. AI synthesis (Haiku) - produces a structured actionability assessment
#
# The output is stored in .beads/scout/<id>.json and used to:
#   - Enrich triage scoring (structural + semantic)
#   - Provide entry-point briefings for the implementing agent
#   - Surface stale issues, hidden blockers, and quick wins
#
# Usage: scout help
# ===========================================================================

set -euo pipefail

VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCOUT_API_KEY="${SCOUT_API_KEY:-${ANTHROPIC_API_KEY:-}}"
SCOUT_MODEL="${SCOUT_MODEL:-claude-haiku-4-5-20251001}"
SCOUT_SRC_DIRS="${SCOUT_SRC_DIRS:-app src lib}"
SCOUT_TEST_DIRS="${SCOUT_TEST_DIRS:-tests test spec}"
SCOUT_SCAN_TTL="${SCOUT_SCAN_TTL:-24}"
SCOUT_QUIET="${SCOUT_QUIET:-false}"
SCOUT_DATA_DIR="${SCOUT_DATA_DIR:-.beads/scout}"
SCOUT_MAX_ISSUES="${SCOUT_MAX_ISSUES:-20}"
SCOUT_FILE_EXTS="${SCOUT_FILE_EXTS:-py html js ts css jsx tsx vue}"

# Load config (project-local takes precedence)
for conf in "$SCRIPT_DIR/scout.conf" "$HOME/.scout.conf" ".scout.conf" "scout.conf"; do
    [[ -f "$conf" ]] && source "$conf"
done

# ---------------------------------------------------------------------------
# Logging & colours
# ---------------------------------------------------------------------------
if [[ "$SCOUT_QUIET" == "true" ]] || [[ ! -t 2 ]]; then
    R="" G="" Y="" B="" C="" BOLD="" DIM="" RST=""
else
    R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m'
    B='\033[0;34m' C='\033[0;36m' BOLD='\033[1m'
    DIM='\033[2m' RST='\033[0m'
fi

log()      { [[ "$SCOUT_QUIET" != "true" ]] && echo -e "$@" >&2 || true; }
step()     { log "  ${C}→${RST} $1"; }
ok()       { log "  ${G}✓${RST} $1"; }
warn()     { log "  ${Y}⚠${RST} $1"; }
err()      { log "  ${R}✗${RST} $1"; }
header()   { log "\n${BOLD}${B}🔍 $1${RST}"; }

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

# Portable date-to-epoch (works on both GNU and BSD/macOS date)
date_to_epoch() {
    date -d "$1" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S%z" "$1" +%s 2>/dev/null || echo 0
}

# Convert a list of strings to a JSON array
to_json_array() {
    if [[ $# -eq 0 ]]; then
        echo '[]'
    else
        printf '%s\n' "$@" | jq -R . | jq -s .
    fi
}

# Require a command or exit
require() {
    command -v "$1" >/dev/null 2>&1 || { err "Required command not found: $1"; exit 1; }
}

# ---------------------------------------------------------------------------
# Beads Interface
# ---------------------------------------------------------------------------

# Read a bead's details. Tries bd CLI first, falls back to reading the file.
# Outputs JSON: { id, title, body, status }
read_bead() {
    local id="$1"

    # Strategy 1: bd show (if it supports some parseable output)
    local raw
    raw=$(bd show "$id" 2>/dev/null || true)

    if [[ -n "$raw" ]]; then
        # If bd outputs JSON natively, use it
        if echo "$raw" | jq -e '.title' >/dev/null 2>&1; then
            echo "$raw" | jq --arg id "$id" '{
                id: $id,
                title: (.title // ""),
                body: (.description // .body // ""),
                status: (.status // "open")
            }'
            return 0
        fi
    fi

    # Strategy 2: Read the issue file directly from .beads/
    local file=""
    for candidate in ".beads/issues/${id}.md" ".beads/${id}.md"; do
        [[ -f "$candidate" ]] && file="$candidate" && break
    done

    # Broader search
    if [[ -z "$file" ]]; then
        file=$(find .beads -name "${id}*" -type f 2>/dev/null | head -1)
    fi

    if [[ -n "$file" ]] && [[ -f "$file" ]]; then
        # Parse YAML frontmatter
        local title status body
        title=$(awk '/^---$/{n++; next} n==1 && /^title:/{sub(/^title:[[:space:]]*/, ""); print; exit}' "$file")
        status=$(awk '/^---$/{n++; next} n==1 && /^status:/{sub(/^status:[[:space:]]*/, ""); print; exit}' "$file")
        body=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$file")

        jq -n --arg id "$id" --arg title "$title" --arg status "$status" --arg body "$body" \
            '{id: $id, title: $title, body: $body, status: $status}'
        return 0
    fi

    # Strategy 3: Use raw bd show output as text
    if [[ -n "$raw" ]]; then
        local title=$(echo "$raw" | head -1 | sed 's/^#* *//')
        jq -n --arg id "$id" --arg title "$title" --arg body "$raw" --arg status "open" \
            '{id: $id, title: $title, body: $body, status: $status}'
        return 0
    fi

    return 1
}

# List open bead IDs
list_open_beads() {
    # Try bd list first
    local ids
    ids=$(bd list --status open 2>/dev/null | grep -oE 'bd-[a-f0-9]+' || true)

    if [[ -z "$ids" ]]; then
        # Fall back to reading .beads/ directory
        ids=$(find .beads/issues -name 'bd-*.md' 2>/dev/null \
            | xargs grep -l 'status:.*open' 2>/dev/null \
            | grep -oE 'bd-[a-f0-9]+' || true)
    fi

    echo "$ids"
}

# ---------------------------------------------------------------------------
# Entity Extraction
# ---------------------------------------------------------------------------

extract_entities() {
    local text="$1"
    local prefix="$2"  # variable prefix for nameref arrays

    # File paths — match common source file extensions
    local ext_re
    ext_re=$(echo "$SCOUT_FILE_EXTS" | tr ' ' '|')
    mapfile -t "${prefix}_files" < <(
        echo "$text" | grep -oE '[a-zA-Z0-9_./-]+\.('"$ext_re"')' | sort -u 2>/dev/null || true
    )

    # Function / class names — explicit definitions
    mapfile -t "${prefix}_funcs" < <(
        {
            # Python: def func_name, class ClassName
            echo "$text" | grep -oE '(def |class )[a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^def //;s/^class //'
            # Backtick-quoted identifiers (common in issue markdown)
            echo "$text" | grep -oE '`[a-zA-Z_][a-zA-Z0-9_.]*`' | tr -d '`'
            # CamelCase identifiers (likely class/component names)
            echo "$text" | grep -oE '\b[A-Z][a-z]+([A-Z][a-z]+)+\b'
        } 2>/dev/null | sort -u || true
    )

    # Route patterns
    mapfile -t "${prefix}_routes" < <(
        echo "$text" | grep -oE '(GET|POST|PUT|PATCH|DELETE)?\s*/[a-z][a-z0-9_/-]*' | sed 's/^[A-Z]* *//' | sort -u 2>/dev/null || true
    )
}

# ---------------------------------------------------------------------------
# Mechanical Reconnaissance
# ---------------------------------------------------------------------------

recon_check_files() {
    local -a found=() missing=()
    for f in "$@"; do
        [[ -z "$f" ]] && continue
        if [[ -f "$f" ]]; then
            found+=("$f")
        else
            # Search in source dirs
            local hit=""
            for dir in $SCOUT_SRC_DIRS; do
                [[ -d "$dir" ]] || continue
                hit=$(find "$dir" -name "$(basename "$f")" -type f 2>/dev/null | head -1)
                [[ -n "$hit" ]] && break
            done
            if [[ -n "$hit" ]]; then
                found+=("$hit")
            else
                missing+=("$f")
            fi
        fi
    done
    jq -n --argjson found "$(to_json_array "${found[@]+"${found[@]}"}")" \
          --argjson missing "$(to_json_array "${missing[@]+"${missing[@]}"}")" \
          '{found: $found, missing: $missing}'
}

recon_grep_functions() {
    local -a results=()
    for fn in "$@"; do
        [[ -z "$fn" ]] && continue
        for dir in $SCOUT_SRC_DIRS; do
            [[ -d "$dir" ]] || continue
            while IFS= read -r match; do
                [[ -n "$match" ]] && results+=("$match")
            done < <(grep -rn --include="*.py" --include="*.html" --include="*.js" \
                "$fn" "$dir" 2>/dev/null | head -5 | sed 's/:/ → /' || true)
        done
    done
    to_json_array "${results[@]+"${results[@]}"}"
}

recon_git_activity() {
    local -a activity=()
    for f in "$@"; do
        [[ -z "$f" ]] || [[ ! -f "$f" ]] && continue
        local log_output
        log_output=$(git log --oneline -3 -- "$f" 2>/dev/null || true)
        [[ -n "$log_output" ]] && activity+=("$f: $log_output")
    done
    to_json_array "${activity[@]+"${activity[@]}"}"
}

recon_find_tests() {
    local -a tests=()
    for f in "$@"; do
        [[ -z "$f" ]] && continue
        local base
        base=$(basename "$f" | sed 's/\.[^.]*$//')
        for dir in $SCOUT_TEST_DIRS; do
            [[ -d "$dir" ]] || continue
            while IFS= read -r t; do
                [[ -n "$t" ]] && tests+=("$t")
            done < <(find "$dir" -name "*${base}*" -type f 2>/dev/null)
        done
    done
    to_json_array "${tests[@]+"${tests[@]}"}"
}

recon_check_wip() {
    local -a conflicts=()
    local in_progress
    in_progress=$(bd list --status in_progress 2>/dev/null || true)

    for f in "$@"; do
        [[ -z "$f" ]] && continue
        local base
        base=$(basename "$f")
        if echo "$in_progress" | grep -qi "$base" 2>/dev/null; then
            conflicts+=("$f — may conflict with in-progress work")
        fi
    done
    to_json_array "${conflicts[@]+"${conflicts[@]}"}"
}

# ---------------------------------------------------------------------------
# AI Analysis (Anthropic Messages API)
# ---------------------------------------------------------------------------

analyze_with_ai() {
    local title="$1"
    local body="$2"
    local recon_json="$3"

    local fallback='{"actionability_score":0.5,"confidence":"low","difficulty":"unknown","entry_points":[],"approach":"No AI analysis available","blockers":[],"risks":[],"estimated_minutes":10,"briefing":"No AI analysis. Manual investigation recommended."}'

    if [[ -z "$SCOUT_API_KEY" ]]; then
        warn "No API key — skipping AI analysis (set SCOUT_API_KEY)"
        echo "$fallback"
        return 0
    fi

    local prompt
    prompt="You are a code scout assessing an issue's actionability. Based on the issue and the mechanical reconnaissance findings below, produce a structured assessment.

ISSUE: $title

DESCRIPTION:
$body

RECONNAISSANCE FINDINGS:
$recon_json

Assess:
1. How actionable is this issue? (0.0 = needs major clarification, 1.0 = fix is obvious)
2. Difficulty level for an AI coding agent to implement
3. Best entry points in the codebase
4. Any blockers or risks
5. Estimated wall-clock time for an AI agent to complete (trivial=2-5min, easy=5-15min, moderate=15-30min, hard=30-60min, complex=60+min)
6. A 2-3 sentence briefing that will be injected into the implementing agent's prompt

Respond with ONLY valid JSON — no markdown fences, no preamble:
{
  \"actionability_score\": 0.0-1.0,
  \"confidence\": \"high|medium|low|blocked\",
  \"difficulty\": \"trivial|easy|moderate|hard|complex\",
  \"entry_points\": [\"file:line\"],
  \"approach\": \"one-sentence implementation approach\",
  \"blockers\": [\"description\"],
  \"risks\": [\"description\"],
  \"estimated_minutes\": 2-90,
  \"briefing\": \"2-3 sentence briefing for the implementing agent\"
}"

    local payload
    payload=$(jq -n \
        --arg model "$SCOUT_MODEL" \
        --arg prompt "$prompt" \
        '{
            model: $model,
            max_tokens: 1024,
            messages: [{role: "user", content: $prompt}]
        }')

    local response
    response=$(curl -s --max-time 30 \
        "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: $SCOUT_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$payload" 2>/dev/null) || {
            err "API request failed"
            echo "$fallback"
            return 0
        }

    # Extract text content
    local content
    content=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null)

    if [[ -z "$content" ]]; then
        local api_err
        api_err=$(echo "$response" | jq -r '.error.message // "Unknown API error"' 2>/dev/null)
        err "API error: $api_err"
        echo "$fallback"
        return 0
    fi

    # Strip any markdown fences the model might sneak in
    content=$(echo "$content" | sed '/^```/d' | tr '\n' ' ' | sed 's/^[[:space:]]*//')

    # Validate JSON
    if echo "$content" | jq . >/dev/null 2>&1; then
        echo "$content"
    else
        err "AI returned invalid JSON — using fallback"
        echo "$fallback"
    fi
}

# ---------------------------------------------------------------------------
# Storage (.beads/scout/<id>.json)
# ---------------------------------------------------------------------------

ensure_dir() { mkdir -p "$SCOUT_DATA_DIR"; }

save_report() {
    ensure_dir
    echo "$2" | jq '.' > "$SCOUT_DATA_DIR/${1}.json"
}

load_report() {
    local file="$SCOUT_DATA_DIR/${1}.json"
    [[ -f "$file" ]] && cat "$file" || true
}

is_primed() { [[ -f "$SCOUT_DATA_DIR/${1}.json" ]]; }

is_stale() {
    local file="$SCOUT_DATA_DIR/${1}.json"
    [[ ! -f "$file" ]] && return 0

    local primed_at
    primed_at=$(jq -r '.primed_at // ""' "$file" 2>/dev/null)
    [[ -z "$primed_at" ]] && return 0

    local primed_epoch now_epoch age_hours
    primed_epoch=$(date_to_epoch "$primed_at")
    now_epoch=$(date +%s)
    age_hours=$(( (now_epoch - primed_epoch) / 3600 ))

    (( age_hours >= SCOUT_SCAN_TTL ))
}

# ---------------------------------------------------------------------------
# Core: Prime a Single Issue
# ---------------------------------------------------------------------------

prime_issue() {
    local id="$1"

    # Read the bead
    local bead_json
    bead_json=$(read_bead "$id") || { err "Cannot read bead $id"; return 1; }

    local title body
    title=$(echo "$bead_json" | jq -r '.title')
    body=$(echo "$bead_json" | jq -r '.body')

    header "Scouting $id: \"$title\""

    # --- Extract entities ---
    step "Extracting entities..."
    local ent_files=() ent_funcs=() ent_routes=()
    extract_entities "$title $body" ent
    ok "${#ent_files[@]} files, ${#ent_funcs[@]} functions, ${#ent_routes[@]} routes"

    # --- Mechanical recon ---
    step "Running reconnaissance..."

    local file_check
    file_check=$(recon_check_files "${ent_files[@]+"${ent_files[@]}"}")
    local found_files_json=$(echo "$file_check" | jq '.found')
    local missing_files_json=$(echo "$file_check" | jq '.missing')

    # Get found files as bash array for downstream checks
    local -a found_files_arr=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && found_files_arr+=("$f")
    done < <(echo "$found_files_json" | jq -r '.[]' 2>/dev/null)

    local funcs_json
    funcs_json=$(recon_grep_functions "${ent_funcs[@]+"${ent_funcs[@]}"}")

    local git_json
    git_json=$(recon_git_activity "${found_files_arr[@]+"${found_files_arr[@]}"}")

    local tests_json
    tests_json=$(recon_find_tests "${found_files_arr[@]+"${found_files_arr[@]}"}")

    local wip_json
    wip_json=$(recon_check_wip "${found_files_arr[@]+"${found_files_arr[@]}"}")

    local n_found n_missing n_funcs n_tests
    n_found=$(echo "$found_files_json" | jq 'length')
    n_missing=$(echo "$missing_files_json" | jq 'length')
    n_funcs=$(echo "$funcs_json" | jq 'length')
    n_tests=$(echo "$tests_json" | jq 'length')

    ok "Files: ${n_found} found, ${n_missing} missing"
    ok "Functions: ${n_funcs} located"
    ok "Tests: ${n_tests} found"

    local n_wip
    n_wip=$(echo "$wip_json" | jq 'length')
    (( n_wip > 0 )) && warn "WIP conflicts: $n_wip"

    # Package recon as JSON
    local recon_json
    recon_json=$(jq -n \
        --argjson files_found "$found_files_json" \
        --argjson files_missing "$missing_files_json" \
        --argjson functions_found "$funcs_json" \
        --argjson git_activity "$git_json" \
        --argjson tests_found "$tests_json" \
        --argjson wip_conflicts "$wip_json" \
        '{
            files_found: $files_found,
            files_missing: $files_missing,
            functions_found: $functions_found,
            git_activity: $git_activity,
            tests_found: $tests_found,
            wip_conflicts: $wip_conflicts
        }')

    # --- AI analysis ---
    step "AI analysis (${SCOUT_MODEL})..."
    local analysis
    analysis=$(analyze_with_ai "$title" "$body" "$recon_json")
    ok "Analysis complete"

    # --- Store report ---
    local report
    report=$(jq -n \
        --arg id "$id" \
        --arg title "$title" \
        --arg primed_at "$(date -Iseconds)" \
        --arg model "$SCOUT_MODEL" \
        --arg version "$VERSION" \
        --argjson recon "$recon_json" \
        --argjson analysis "$analysis" \
        '{
            id: $id,
            title: $title,
            primed_at: $primed_at,
            scout_version: $version,
            model: $model,
            recon: $recon,
            analysis: $analysis
        }')

    save_report "$id" "$report"
    ok "Stored → $SCOUT_DATA_DIR/${id}.json"

    # --- Summary ---
    if [[ "$SCOUT_QUIET" != "true" ]]; then
        local score conf diff approach est
        score=$(echo "$analysis" | jq -r '.actionability_score // "?"')
        conf=$(echo "$analysis" | jq -r '.confidence // "?"')
        diff=$(echo "$analysis" | jq -r '.difficulty // "?"')
        approach=$(echo "$analysis" | jq -r '.approach // "?"')
        est=$(echo "$analysis" | jq -r '.estimated_minutes // "?"')

        echo ""
        log "  ${BOLD}📋 Assessment:${RST}"
        log "  Actionability: ${BOLD}${score}${RST} (${conf} confidence)"
        log "  Difficulty:    ${diff}"
        log "  Approach:      ${approach}"
        log "  Est. time: ${est} min"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_prime() {
    require jq
    require curl

    local mode="specific"
    local -a ids=()
    local top_n=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --unprimed)   mode="unprimed"; shift ;;
            --all)        mode="all"; shift ;;
            --stale)      mode="stale"; shift ;;
            --top)        mode="top"; top_n="${2:?--top requires N}"; shift 2 ;;
            --quiet|-q)   SCOUT_QUIET="true"; shift ;;
            -*)           err "Unknown flag: $1"; exit 1 ;;
            *)            ids+=("$1"); shift ;;
        esac
    done

    local count=0

    case "$mode" in
        specific)
            if [[ ${#ids[@]} -eq 0 ]]; then
                err "No bead IDs specified."
                echo "Usage: scout prime [--unprimed|--all|--stale|--top N] [ID...]" >&2
                exit 1
            fi
            for id in "${ids[@]}"; do
                prime_issue "$id" && ((count++)) || true
            done
            ;;

        unprimed)
            while IFS= read -r id; do
                [[ -z "$id" ]] && continue
                is_primed "$id" && continue
                prime_issue "$id" && ((count++)) || true
                (( count >= SCOUT_MAX_ISSUES )) && { warn "Hit max issues ($SCOUT_MAX_ISSUES)"; break; }
            done < <(list_open_beads)
            ;;

        all)
            while IFS= read -r id; do
                [[ -z "$id" ]] && continue
                prime_issue "$id" && ((count++)) || true
                (( count >= SCOUT_MAX_ISSUES )) && { warn "Hit max issues ($SCOUT_MAX_ISSUES)"; break; }
            done < <(list_open_beads)
            ;;

        stale)
            while IFS= read -r id; do
                [[ -z "$id" ]] && continue
                is_stale "$id" || continue
                prime_issue "$id" && ((count++)) || true
                (( count >= SCOUT_MAX_ISSUES )) && { warn "Hit max issues ($SCOUT_MAX_ISSUES)"; break; }
            done < <(list_open_beads)
            ;;

        top)
            # Use bv --robot-triage if available, otherwise fall back to list
            if command -v bv >/dev/null 2>&1; then
                while IFS= read -r id; do
                    [[ -z "$id" ]] && continue
                    prime_issue "$id" && ((count++)) || true
                done < <(bv --robot-triage 2>/dev/null \
                    | jq -r ".triage.recommendations[:${top_n}][].id" 2>/dev/null \
                    || list_open_beads | head -n "$top_n")
            else
                warn "bv not found — falling back to bd list (no triage ranking)"
                while IFS= read -r id; do
                    [[ -z "$id" ]] && continue
                    prime_issue "$id" && ((count++)) || true
                done < <(list_open_beads | head -n "$top_n")
            fi
            ;;
    esac

    log "\n${G}✓ Primed ${count} issue(s)${RST}"
}

cmd_status() {
    ensure_dir
    echo ""
    printf "${BOLD}%-14s %-36s %6s  %-10s %-10s${RST}\n" "ID" "TITLE" "SCORE" "CONFIDENCE" "DIFFICULTY"
    printf "%-14s %-36s %6s  %-10s %-10s\n" "──────────" "──────────────────────────────────" "─────" "──────────" "──────────"

    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        local report
        report=$(load_report "$id")

        if [[ -n "$report" ]]; then
            local title score conf diff stale_mark=""
            title=$(echo "$report" | jq -r '.title // "?"' | cut -c1-34)
            score=$(echo "$report" | jq -r '.analysis.actionability_score // "—"')
            conf=$(echo "$report" | jq -r '.analysis.confidence // "—"')
            diff=$(echo "$report" | jq -r '.analysis.difficulty // "—"')
            is_stale "$id" && stale_mark=" (stale)"
            printf "%-14s %-36s %6s  %-10s %-10s%s\n" "$id" "$title" "$score" "$conf" "$diff" "$stale_mark"
        else
            printf "%-14s %-36s %6s  %-10s %-10s\n" "$id" "—" "—" "unprimed" "—"
        fi
    done < <(list_open_beads)
    echo ""
}

cmd_report() {
    local id="${1:?Usage: scout report <bead-id>}"
    local report
    report=$(load_report "$id")
    if [[ -z "$report" ]]; then
        err "No scout report for $id"
        echo "Run: scout prime $id" >&2
        exit 1
    fi
    echo "$report" | jq '.'
}

cmd_briefing() {
    local id="${1:?Usage: scout briefing <bead-id>}"
    local report
    report=$(load_report "$id")
    if [[ -z "$report" ]]; then
        # No briefing available — return empty (safe for prompt injection)
        return 0
    fi
    echo "$report" | jq -r '.analysis.briefing // empty'
}

cmd_score() {
    local id="${1:?Usage: scout score <bead-id>}"
    local report
    report=$(load_report "$id")
    if [[ -z "$report" ]]; then
        echo "0.5"  # Default neutral score for unprimed issues
        return 0
    fi
    echo "$report" | jq -r '.analysis.actionability_score // 0.5'
}

cmd_clear() {
    local target="${1:?Usage: scout clear <bead-id|--all>}"
    if [[ "$target" == "--all" ]]; then
        rm -rf "$SCOUT_DATA_DIR"
        ok "Cleared all scout data"
    else
        rm -f "$SCOUT_DATA_DIR/${target}.json"
        ok "Cleared scout data for $target"
    fi
}

cmd_help() {
    cat <<'HELP'
scout — AI-enhanced issue triage for beads

COMMANDS
    scout prime [ID...]          Prime specific issues
    scout prime --unprimed       Prime open issues that lack scout data
    scout prime --all            Re-prime all open issues
    scout prime --stale          Re-prime issues with expired scans
    scout prime --top N          Prime top N issues by triage score (requires bv)
    scout status                 Show priming status of all open issues
    scout report ID              Show full scout report as JSON
    scout briefing ID            Output briefing text (for prompt injection)
    scout score ID               Output actionability score (for scripting)
    scout clear [ID|--all]       Clear scout data
    scout help                   This help
    scout version                Show version

OPTIONS
    --quiet, -q                  Suppress terminal output (for agentic use)

CONFIGURATION
    Set in scout.conf, .scout.conf, or as environment variables:

    SCOUT_API_KEY          Anthropic API key (falls back to ANTHROPIC_API_KEY)
    SCOUT_MODEL            Model for analysis (default: claude-haiku-4-5-20251001)
    SCOUT_SRC_DIRS         Source directories (default: "app src lib")
    SCOUT_TEST_DIRS        Test directories (default: "tests test spec")
    SCOUT_FILE_EXTS        File extensions to extract (default: "py html js ts css jsx tsx vue")
    SCOUT_SCAN_TTL         Hours before scan is stale (default: 24)
    SCOUT_MAX_ISSUES       Max issues per batch (default: 20)
    SCOUT_DATA_DIR         Where to store reports (default: .beads/scout)

EXAMPLES
    # Day use: prime an issue you just triaged
    scout prime bd-a3f8e9

    # Evening: prime everything before the overnight run
    scout prime --unprimed

    # Check the board
    scout status

    # In a ralph outer loop script
    scout prime --unprimed --quiet
    BRIEFING=$(scout briefing bd-a3f8e9)

    # Get just the score for scripting
    SCORE=$(scout score bd-a3f8e9)

STORAGE
    Scout reports are stored as JSON in .beads/scout/<id>.json
    They are separate from beads data and safe to regenerate at any time.
HELP
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        prime)     cmd_prime "$@" ;;
        status)    cmd_status ;;
        report)    cmd_report "$@" ;;
        briefing)  cmd_briefing "$@" ;;
        score)     cmd_score "$@" ;;
        clear)     cmd_clear "$@" ;;
        help|-h|--help)     cmd_help ;;
        version|-v|--version) echo "scout v$VERSION" ;;
        *)
            err "Unknown command: $cmd"
            echo "Run 'scout help' for usage." >&2
            exit 1
            ;;
    esac
}

main "$@"
```
