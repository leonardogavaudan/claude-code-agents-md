#!/bin/bash
# Integration tests for agents-md hooks.
# Run: bash ~/.claude/hooks/agents-md/test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOADER="$SCRIPT_DIR/loader.sh"
SESSION_START="$SCRIPT_DIR/session-start.sh"

PASS=0
FAIL=0

assert_contains() {
  local label="$1" file="$2" pattern="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $label"
    ((PASS++))
  else
    echo "  FAIL: $label (expected pattern: $pattern)"
    echo "  --- actual output ---"
    cat "$file"
    echo "  ---"
    ((FAIL++))
  fi
}

assert_not_contains() {
  local label="$1" file="$2" pattern="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  FAIL: $label (unexpected pattern found: $pattern)"
    echo "  --- actual output ---"
    cat "$file"
    echo "  ---"
    ((FAIL++))
  else
    echo "  PASS: $label"
    ((PASS++))
  fi
}

assert_empty() {
  local label="$1" file="$2"
  if [[ ! -s "$file" ]]; then
    echo "  PASS: $label"
    ((PASS++))
  else
    echo "  FAIL: $label (expected empty output)"
    echo "  --- actual output ---"
    cat "$file"
    echo "  ---"
    ((FAIL++))
  fi
}

# --- Setup test fixture ---
TMPDIR=$(mktemp -d)
PROJECT="$TMPDIR/project"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$PROJECT/sub"
mkdir -p "$PROJECT/sub2"
mkdir -p "$PROJECT/sub3/.agents"
mkdir -p "$PROJECT/deep/nested/dir"
mkdir -p "$PROJECT/both-variants/.agents"

echo "# Root agents instructions"           > "$PROJECT/AGENTS.md"
echo "# Sub instructions"                   > "$PROJECT/sub/AGENTS.md"
echo "content"                               > "$PROJECT/sub/file.txt"
echo "# Claude instructions"                > "$PROJECT/sub2/CLAUDE.md"
echo "# Agents instructions (should skip)"  > "$PROJECT/sub2/AGENTS.md"
echo "content"                               > "$PROJECT/sub2/file.txt"
echo "# Dot-agents instructions"            > "$PROJECT/sub3/.agents/AGENTS.md"
echo "content"                               > "$PROJECT/sub3/file.txt"
echo "# Deep instructions"                  > "$PROJECT/deep/AGENTS.md"
echo "content"                               > "$PROJECT/deep/nested/dir/file.txt"
echo "# Variant A"                          > "$PROJECT/both-variants/AGENTS.md"
echo "# Variant B"                          > "$PROJECT/both-variants/.agents/AGENTS.md"
echo "content"                               > "$PROJECT/both-variants/file.txt"

# Equivalence matrix: every combination of CLAUDE.md variant blocking AGENTS.md variant
# eq1: dir/CLAUDE.md blocks dir/AGENTS.md (already covered by sub2, but explicit)
mkdir -p "$PROJECT/eq1"
echo "# eq1 claude"                         > "$PROJECT/eq1/CLAUDE.md"
echo "# eq1 agents (should skip)"           > "$PROJECT/eq1/AGENTS.md"
echo "content"                               > "$PROJECT/eq1/file.txt"

# eq2: dir/.claude/CLAUDE.md blocks dir/AGENTS.md
mkdir -p "$PROJECT/eq2/.claude"
echo "# eq2 claude hidden"                  > "$PROJECT/eq2/.claude/CLAUDE.md"
echo "# eq2 agents (should skip)"           > "$PROJECT/eq2/AGENTS.md"
echo "content"                               > "$PROJECT/eq2/file.txt"

# eq3: dir/CLAUDE.md blocks dir/.agents/AGENTS.md
mkdir -p "$PROJECT/eq3/.agents"
echo "# eq3 claude"                         > "$PROJECT/eq3/CLAUDE.md"
echo "# eq3 dot-agents (should skip)"       > "$PROJECT/eq3/.agents/AGENTS.md"
echo "content"                               > "$PROJECT/eq3/file.txt"

# eq4: dir/.claude/CLAUDE.md blocks dir/.agents/AGENTS.md
mkdir -p "$PROJECT/eq4/.claude" "$PROJECT/eq4/.agents"
echo "# eq4 claude hidden"                  > "$PROJECT/eq4/.claude/CLAUDE.md"
echo "# eq4 dot-agents (should skip)"       > "$PROJECT/eq4/.agents/AGENTS.md"
echo "content"                               > "$PROJECT/eq4/file.txt"

git init "$PROJECT" >/dev/null 2>&1

# Helper: run loader hook with given session ID and file path
run_loader() {
  local sid="$1" fpath="$2" out="$3"
  printf '{"session_id":"%s","cwd":"%s","tool_name":"Read","tool_input":{"file_path":"%s"}}' \
    "$sid" "$PROJECT" "$fpath" \
    | bash "$LOADER" > "$out" 2>/dev/null
}

# Helper: run session-start hook
run_session_start() {
  local cwd="$1" out="$2"
  printf '{"session_id":"ss","cwd":"%s"}' "$cwd" \
    | bash "$SESSION_START" > "$out" 2>/dev/null
}

OUT="$TMPDIR/out"

# ============================================================
echo "=== PreToolUse Loader Tests ==="
# ============================================================

echo ""
echo "1. AGENTS.md injected from subdirectory"
run_loader "s1" "$PROJECT/sub/file.txt" "$OUT"
assert_contains "sub/AGENTS.md content present"   "$OUT" "Sub instructions"
assert_contains "root AGENTS.md also collected"    "$OUT" "Root agents instructions"
assert_contains "additionalContext key present"    "$OUT" "additionalContext"

echo ""
echo "2. Dedup — second read same session"
run_loader "s1" "$PROJECT/sub/file.txt" "$OUT"
assert_empty "no re-injection on second read"      "$OUT"

echo ""
echo "3. Equivalence: dir/CLAUDE.md blocks dir/AGENTS.md"
run_loader "eq1" "$PROJECT/eq1/file.txt" "$OUT"
assert_not_contains "eq1/AGENTS.md skipped"        "$OUT" "eq1 agents"
assert_contains "root AGENTS.md still loads"       "$OUT" "Root agents instructions"

echo ""
echo "3b. Equivalence: dir/.claude/CLAUDE.md blocks dir/AGENTS.md"
run_loader "eq2" "$PROJECT/eq2/file.txt" "$OUT"
assert_not_contains "eq2/AGENTS.md skipped"        "$OUT" "eq2 agents"
assert_contains "root AGENTS.md still loads"       "$OUT" "Root agents instructions"

echo ""
echo "3c. Equivalence: dir/CLAUDE.md blocks dir/.agents/AGENTS.md"
run_loader "eq3" "$PROJECT/eq3/file.txt" "$OUT"
assert_not_contains "eq3/.agents/AGENTS.md skipped" "$OUT" "eq3 dot-agents"
assert_contains "root AGENTS.md still loads"       "$OUT" "Root agents instructions"

echo ""
echo "3d. Equivalence: dir/.claude/CLAUDE.md blocks dir/.agents/AGENTS.md"
run_loader "eq4" "$PROJECT/eq4/file.txt" "$OUT"
assert_not_contains "eq4/.agents/AGENTS.md skipped" "$OUT" "eq4 dot-agents"
assert_contains "root AGENTS.md still loads"       "$OUT" "Root agents instructions"

echo ""
echo "4. .agents/AGENTS.md variant loaded"
run_loader "s4" "$PROJECT/sub3/file.txt" "$OUT"
assert_contains ".agents/AGENTS.md content present" "$OUT" "Dot-agents instructions"

echo ""
echo "5. No path provided (Glob without path) — no-op"
printf '{"session_id":"s5","cwd":"%s","tool_name":"Glob","tool_input":{"pattern":"**/*.txt"}}' \
  "$PROJECT" | bash "$LOADER" > "$OUT" 2>/dev/null
assert_empty "no output when no path"              "$OUT"

echo ""
echo "6. Deep nesting — ancestor AGENTS.md collected"
run_loader "s6" "$PROJECT/deep/nested/dir/file.txt" "$OUT"
assert_contains "deep/AGENTS.md from ancestor"     "$OUT" "Deep instructions"
assert_contains "root AGENTS.md also collected"    "$OUT" "Root agents instructions"

echo ""
echo "6b. Mid-path AGENTS.md — reading file two levels below"
mkdir -p "$PROJECT/api/test/hey"
echo "# Test layer instructions"              > "$PROJECT/api/test/AGENTS.md"
echo "content"                                 > "$PROJECT/api/test/hey/file.txt"
run_loader "s6b" "$PROJECT/api/test/hey/file.txt" "$OUT"
assert_contains "mid-path AGENTS.md found"     "$OUT" "Test layer instructions"
assert_contains "root AGENTS.md also found"    "$OUT" "Root agents instructions"

echo ""
echo "7. Both AGENTS.md and .agents/AGENTS.md — first variant wins"
run_loader "s7" "$PROJECT/both-variants/file.txt" "$OUT"
assert_contains "AGENTS.md (not .agents/) loaded"  "$OUT" "Variant A"
assert_not_contains ".agents/ variant skipped"      "$OUT" "Variant B"

echo ""
echo "8. Grep tool — path extraction works"
printf '{"session_id":"s8","cwd":"%s","tool_name":"Grep","tool_input":{"pattern":"content","path":"%s/sub"}}' \
  "$PROJECT" "$PROJECT" | bash "$LOADER" > "$OUT" 2>/dev/null
assert_contains "Grep path triggers loader"        "$OUT" "Sub instructions"

# ============================================================
echo ""
echo "=== SessionStart Tests ==="
# ============================================================

echo ""
echo "9. Root AGENTS.md loaded at session start"
run_session_start "$PROJECT" "$OUT"
assert_contains "root AGENTS.md in output"         "$OUT" "Root agents instructions"

echo ""
echo "10. Skipped when CLAUDE.md exists at root"
echo "# Claude root" > "$PROJECT/CLAUDE.md"
run_session_start "$PROJECT" "$OUT"
assert_empty "no output when CLAUDE.md at root"    "$OUT"
rm "$PROJECT/CLAUDE.md"

echo ""
echo "11. .claude/CLAUDE.md also blocks"
mkdir -p "$PROJECT/.claude"
echo "# Claude hidden" > "$PROJECT/.claude/CLAUDE.md"
run_session_start "$PROJECT" "$OUT"
assert_empty "no output when .claude/CLAUDE.md"    "$OUT"
rm -rf "$PROJECT/.claude"

# ============================================================
echo ""
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==========================================="

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
