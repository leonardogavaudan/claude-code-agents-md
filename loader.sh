#!/bin/bash
# agents-md-loader.sh
# PreToolUse hook: lazy-loads AGENTS.md files from directory ancestors on first access.
# Fires on Read, Grep, Glob. Injects content via additionalContext JSON output.
#
# Equivalence: for any directory, CLAUDE.md / .claude/CLAUDE.md / AGENTS.md / .agents/AGENTS.md
# are conceptual equivalents. If a CLAUDE.md variant exists, Claude Code handles it natively
# and we skip. Otherwise, we inject the first AGENTS.md variant found.
#
# Session state is tracked in /tmp/claude-agents-md-seen-{session_id} to avoid re-injection.
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

# --- Extract target path from tool_input ---
case "$TOOL_NAME" in
  Read)   TARGET=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') ;;
  Grep)   TARGET=$(echo "$INPUT" | jq -r '.tool_input.path // empty') ;;
  Glob)   TARGET=$(echo "$INPUT" | jq -r '.tool_input.path // empty') ;;
  *)      exit 0 ;;
esac

# No target path → nothing to do.
[[ -z "$TARGET" ]] && exit 0

# Resolve to absolute path.
[[ "$TARGET" != /* ]] && TARGET="$CWD/$TARGET"

# Get the directory (file → parent, directory → itself, nonexistent → parent).
if [[ -d "$TARGET" ]]; then
  DIR="$TARGET"
else
  DIR=$(dirname "$TARGET")
fi

# Resolve symlinks and normalize. Exit gracefully if directory doesn't exist.
DIR=$(cd "$DIR" 2>/dev/null && pwd -P) || exit 0

# --- Determine ceiling (project root) ---
# Prefer git root, fall back to cwd.
CEILING=$(cd "$DIR" && git rev-parse --show-toplevel 2>/dev/null) || CEILING="$CWD"

# --- Session state file ---
STATE_FILE="/tmp/claude-agents-md-seen-${SESSION_ID}"
touch "$STATE_FILE"

# --- Walk from DIR up to CEILING, collecting AGENTS.md content ---
COLLECTED=""
CURRENT="$DIR"

while true; do
  # Stop if we've gone above the ceiling.
  case "$CURRENT" in
    "$CEILING"/*|"$CEILING") ;;  # at or below ceiling
    *) break ;;
  esac

  # Skip already-processed directories.
  if ! grep -qxF "$CURRENT" "$STATE_FILE" 2>/dev/null; then
    # Mark as seen immediately (minimizes race window with concurrent hooks).
    echo "$CURRENT" >> "$STATE_FILE"

    # Check equivalence group: CLAUDE.md variants → skip (native handling).
    if [[ ! -f "$CURRENT/CLAUDE.md" ]] && [[ ! -f "$CURRENT/.claude/CLAUDE.md" ]]; then
      # No CLAUDE.md equivalent. Check for AGENTS.md variants.
      AGENTS_FILE=""
      if [[ -f "$CURRENT/AGENTS.md" ]]; then
        AGENTS_FILE="$CURRENT/AGENTS.md"
      elif [[ -f "$CURRENT/.agents/AGENTS.md" ]]; then
        AGENTS_FILE="$CURRENT/.agents/AGENTS.md"
      fi

      if [[ -n "$AGENTS_FILE" ]]; then
        REL_PATH="${AGENTS_FILE#"$CEILING"/}"
        COLLECTED="${COLLECTED}
---
## Instructions from ${REL_PATH}

$(cat "$AGENTS_FILE")
"
      fi
    fi
  fi

  # Stop after processing the ceiling directory.
  [[ "$CURRENT" == "$CEILING" ]] && break

  # Move to parent.
  CURRENT=$(dirname "$CURRENT")
  [[ "$CURRENT" == "/" ]] && break
done

# --- Output collected content as additionalContext ---
if [[ -n "$COLLECTED" ]]; then
  jq -n --arg ctx "$COLLECTED" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: $ctx
    }
  }'
fi

exit 0
