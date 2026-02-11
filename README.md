# agents-md hooks

Adds `AGENTS.md` lazy-loading support to Claude Code, mirroring the native `CLAUDE.md` behavior.

## What it does

- **`session-start.sh`** — loads `AGENTS.md` (or `.agents/AGENTS.md`) from the project root at session start
- **`loader.sh`** — lazily loads subdirectory `AGENTS.md` files when Claude first reads files in those directories
- Files are only injected once per session (dedup via `/tmp/claude-agents-md-seen-{session_id}`)
- If a `CLAUDE.md` equivalent exists in the same directory, `AGENTS.md` is skipped (no double-loading)

### Equivalence rules

For any directory, these are treated as conceptual equivalents — only one gets loaded:

| File | Handled by |
|------|-----------|
| `dir/CLAUDE.md` | Claude Code (native) |
| `dir/.claude/CLAUDE.md` | Claude Code (native) |
| `dir/AGENTS.md` | This hook |
| `dir/.agents/AGENTS.md` | This hook |

## Setup

Copy this directory to `~/.claude/hooks/agents-md/` and add these entries to `~/.claude/settings.json`:

```jsonc
{
  "hooks": {
    "SessionStart": [
      // ... your existing SessionStart hooks ...
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/agents-md/session-start.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      // ... your existing PreToolUse hooks ...
      {
        "matcher": "Read|Grep|Glob",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/agents-md/loader.sh"
          }
        ]
      }
    ]
  }
}
```

Restart Claude Code for changes to take effect.

## Testing

```bash
bash ~/.claude/hooks/agents-md/test.sh
```

## Dependencies

`bash`, `jq`, `git` — no other dependencies.
