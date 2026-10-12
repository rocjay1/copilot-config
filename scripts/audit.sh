#!/usr/bin/env bash
# Inventory what GitHub Copilot CLI would load for a repository, and flag likely problems.
#
#   scripts/audit.sh [REPO_PATH]      default: current directory
#
# Read-only. Checks personal config in $COPILOT_HOME (or ~/.copilot) plus ~/.claude and
# ~/.agents skill directories, and the repo's instruction, skill, agent, and hook files.
#
# Word counts are a rough proxy for context cost (~1.3 tokens per word for English prose).

set -uo pipefail

REPO="$(cd "${1:-.}" && pwd)"
CH="${COPILOT_HOME:-$HOME/.copilot}"
BUDGET_PERSONAL=300
BUDGET_REPO=500
WARNINGS=""
warn() { WARNINGS="${WARNINGS}  ! $1"$'\n'; }

words() { wc -w < "$1" | tr -d ' '; }

# Print a top-level frontmatter value. Handles single-line values and folded/literal blocks.
fm() {
  awk -v key="$2" '
    NR==1 && $0!="---" { exit }
    NR==1 { infm=1; next }
    infm && $0=="---" { exit }
    infm {
      if (collecting) {
        if ($0 ~ /^[ \t]+/) { sub(/^[ \t]+/, ""); val = val (val==""?"":" ") $0; next }
        else { print val; exit }
      }
      if (index($0, key ":") == 1) {
        v = substr($0, length(key) + 2); sub(/^[ \t]+/, "", v)
        if (v == ">" || v == "|" || v == ">-" || v == "|-") { collecting=1; val=""; next }
        gsub(/^["\x27]|["\x27]$/, "", v); print v; exit
      }
    }
    END { if (collecting) print val }
  ' "$1"
}

rel() { case "$1" in "$REPO"/*) echo "${1#$REPO/}" ;; "$HOME"/*) echo "~/${1#$HOME/}" ;; *) echo "$1" ;; esac; }

PRUNE='-name .git -o -name node_modules -o -name .terraform -o -name vendor -o -name .venv'

echo "Copilot CLI config audit"
echo "  repo:         $REPO"
echo "  copilot home: $(rel "$CH")"
echo

# ---------------------------------------------------------------------------
echo "== Always-on instructions =="
personal_total=0; repo_total=0; root_files=0

if [ -f "$CH/copilot-instructions.md" ]; then
  w=$(words "$CH/copilot-instructions.md"); personal_total=$((personal_total + w))
  printf '  %6s words  %s  (personal)\n' "$w" "$(rel "$CH/copilot-instructions.md")"
fi

for f in .github/copilot-instructions.md AGENTS.md CLAUDE.md .claude/CLAUDE.md GEMINI.md; do
  if [ -f "$REPO/$f" ]; then
    w=$(words "$REPO/$f"); repo_total=$((repo_total + w)); root_files=$((root_files + 1))
    printf '  %6s words  %s\n' "$w" "$f"
    inc=$(grep -nE '(^|[[:space:]])@[./A-Za-z0-9_-]+\.[A-Za-z0-9]+' "$REPO/$f" | head -5)
    if [ -n "$inc" ]; then
      echo "             includes (@):"; echo "$inc" | sed 's/^/               /'
      warn "$f pulls in other files with @. Their contents are always-on too; check their size."
    fi
  fi
done

# Path-scoped files with applyTo "**" are effectively always-on.
for dir in "$CH/instructions" "$REPO/.github/instructions"; do
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    at="$(fm "$f" applyTo)"
    if [ "$at" = "**" ] || [ "$at" = "**/*" ]; then
      w=$(words "$f")
      case "$f" in "$CH"/*) personal_total=$((personal_total + w)) ;; *) repo_total=$((repo_total + w)) ;; esac
      printf '  %6s words  %s  (applyTo "%s")\n' "$w" "$(rel "$f")" "$at"
      warn "$(rel "$f") has applyTo \"$at\", so it's always-on. Move it to the root file or narrow the glob."
    fi
  done < <(find "$dir" -type f -name '*.instructions.md' | sort)
done

if [ -n "${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:-}" ]; then
  echo "  COPILOT_CUSTOM_INSTRUCTIONS_DIRS is set:"
  IFS=':,' read -r -a extra_dirs <<< "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS"
  for d in "${extra_dirs[@]}"; do
    [ -d "$d" ] || { echo "    (missing) $d"; continue; }
    while IFS= read -r f; do
      printf '  %6s words  %s  (custom dir; scope varies by version)\n' "$(words "$f")" "$(rel "$f")"
    done < <(find "$d" -type f \( -name AGENTS.md -o -name '*.instructions.md' \) | sort)
  done
  warn "COPILOT_CUSTOM_INSTRUCTIONS_DIRS is set. Its global/path scoping changed after v1.0.65; prefer ~/.copilot/copilot-instructions.md for always-on rules."
fi

echo "  -----"
printf '  personal: %s / %s words    repo: %s / %s words\n' "$personal_total" "$BUDGET_PERSONAL" "$repo_total" "$BUDGET_REPO"
[ "$personal_total" -gt "$BUDGET_PERSONAL" ] && warn "Personal always-on instructions are over budget ($personal_total > $BUDGET_PERSONAL words)."
[ "$repo_total" -gt "$BUDGET_REPO" ] && warn "Repo always-on instructions are over budget ($repo_total > $BUDGET_REPO words)."
[ "$root_files" -gt 1 ] && warn "$root_files root-level instruction files are combined. Overlapping or conflicting rules across them are a common cause of erratic behavior. Consolidate into one."
echo

# ---------------------------------------------------------------------------
echo "== Path-scoped instructions (loaded when applyTo matches) =="
found=0
for dir in "$CH/instructions" "$REPO/.github/instructions"; do
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    at="$(fm "$f" applyTo)"
    [ "$at" = "**" ] || [ "$at" = "**/*" ] && continue
    found=1
    printf '  %6s words  %s  applyTo: %s\n' "$(words "$f")" "$(rel "$f")" "${at:-<none>}"
    [ -z "$at" ] && warn "$(rel "$f") has no applyTo."
  done < <(find "$dir" -type f -name '*.instructions.md' | sort)
done
[ "$found" -eq 0 ] && echo "  (none)"
echo

# ---------------------------------------------------------------------------
echo "== Nested agent instruction files (below repo root) =="
nested="$(find "$REPO" \( $PRUNE \) -prune -o -mindepth 2 -type f \( -name AGENTS.md -o -name CLAUDE.md -o -name GEMINI.md \) -print 2>/dev/null \
  | grep -v "^$REPO/.claude/CLAUDE.md$" | sort)"
if [ -n "$nested" ]; then
  while IFS= read -r f; do printf '  %6s words  %s\n' "$(words "$f")" "$(rel "$f")"; done <<< "$nested"
  warn "Nested AGENTS.md/CLAUDE.md files add instructions when working in those directories. Make sure they don't contradict the root."
else
  echo "  (none)"
fi
echo

# ---------------------------------------------------------------------------
echo "== Skills (descriptions are always visible; bodies load on demand) =="
skill_count=0; desc_total=0; names=""
for dir in "$REPO/.github/skills" "$REPO/.claude/skills" "$REPO/.agents/skills" \
           "$CH/skills" "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    skill_count=$((skill_count + 1))
    d="$(dirname "$f")"; dname="$(basename "$d")"
    name="$(fm "$f" name)"; desc="$(fm "$f" description)"
    dw=$(printf '%s' "$desc" | wc -w | tr -d ' '); desc_total=$((desc_total + dw))
    extra=$(find "$d" -type f ! -name SKILL.md | wc -l | tr -d ' ')
    printf '  %-28s desc %3sw  body %5sw  +%s files  %s\n' "${name:-<no name>}" "$dw" "$(words "$f")" "$extra" "$(rel "$d")"
    [ -z "$name" ] && warn "$(rel "$f") has no name in frontmatter."
    [ -z "$desc" ] && warn "$(rel "$f") has no description; the model can't tell when to use it."
    [ -n "$name" ] && [ "$name" != "$dname" ] && warn "Skill name '$name' doesn't match its directory '$dname'."
    names="${names}${name:-$dname}"$'\n'
  done < <(find "$dir" -mindepth 2 -maxdepth 2 -type f -name SKILL.md | sort)
done
[ "$skill_count" -eq 0 ] && echo "  (none)"
echo "  -----"
echo "  $skill_count skills, $desc_total words of descriptions"
dups="$(printf '%s' "$names" | sed '/^$/d' | sort | uniq -d)"
[ -n "$dups" ] && warn "Duplicate skill names (same skill in more than one location): $(echo $dups)"
[ "$skill_count" -gt 15 ] && warn "$skill_count skills is a lot to choose between. Check for overlapping descriptions."
echo

# ---------------------------------------------------------------------------
echo "== Custom agents =="
found=0
for dir in "$REPO/.github/agents" "$CH/agents"; do
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    found=1
    printf '  %-28s %5sw  tools: %s  %s\n' "$(fm "$f" name)" "$(words "$f")" "$(fm "$f" tools)" "$(rel "$f")"
  done < <(find "$dir" -type f -name '*.agent.md' | sort)
done
[ "$found" -eq 0 ] && echo "  (none)"
echo

# ---------------------------------------------------------------------------
echo "== Hooks =="
found=0
for dir in "$REPO/.github/hooks" "$CH/hooks"; do
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    found=1
    if command -v python3 >/dev/null 2>&1; then
      events="$(python3 -I -c '
import json, sys
try:
    h = json.load(open(sys.argv[1])).get("hooks", {})
    print(", ".join(f"{k} x{len(v)}" for k, v in h.items()) or "(no hooks)")
except Exception as e:
    print(f"INVALID JSON: {e}")
' "$f")"
    else
      events="$(grep -oE '"(pre|post|session|user|notification|permission|agent|error|stop)[A-Za-z]*"[[:space:]]*:' "$f" | tr -d '":' | sort -u | tr '\n' ' ')"
    fi
    printf '  %s: %s\n' "$(rel "$f")" "$events"
    case "$events" in INVALID*) warn "$(rel "$f") is not valid JSON; its hooks won't load." ;; esac
  done < <(find "$dir" -maxdepth 1 -type f -name '*.json' | sort)
done
[ "$found" -eq 0 ] && echo "  (none)"
echo

# ---------------------------------------------------------------------------
echo "== MCP servers (tool definitions add to context) =="
mcp="$CH/mcp-config.json"
if [ -f "$mcp" ]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 -I -c '
import json, sys
try:
    s = json.load(open(sys.argv[1])).get("mcpServers", {})
    print(f"  {len(s)} configured: " + (", ".join(s) or "(none)"))
except Exception as e:
    print(f"  INVALID JSON: {e}")
' "$mcp"
  else
    echo "  $(rel "$mcp") present (install python3 to list servers)"
  fi
else
  echo "  (no $(rel "$mcp"))"
fi
echo "  Note: the GitHub MCP server and any --additional-mcp-config flags aren't shown here."
echo

# ---------------------------------------------------------------------------
echo "== Findings =="
if [ -n "$WARNINGS" ]; then printf '%s' "$WARNINGS"; else echo "  No issues flagged."; fi
echo
echo "Next: start a fresh session in this repo and run /context to see the real starting load."
