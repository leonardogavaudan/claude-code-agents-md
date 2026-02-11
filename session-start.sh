#!/bin/bash
# agents-md-session-start.sh
# SessionStart hook: loads project-root AGENTS.md if no CLAUDE.md equivalent exists.
# Stdout from SessionStart hooks is injected into Claude's context automatically.
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')

# If any CLAUDE.md equivalent exists at project root, Claude Code handles it natively — skip.
if [[ -f "$CWD/CLAUDE.md" ]] || [[ -f "$CWD/.claude/CLAUDE.md" ]]; then
  exit 0
fi

# Check for AGENTS.md variants (dir/AGENTS.md takes priority over dir/.agents/AGENTS.md).
for candidate in "$CWD/AGENTS.md" "$CWD/.agents/AGENTS.md"; do
  if [[ -f "$candidate" ]]; then
    REL="${candidate#"$CWD"/}"
    echo ""
    echo "# Project Instructions (from $REL)"
    echo ""
    cat "$candidate"
    exit 0
  fi
done

exit 0
