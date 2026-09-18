#!/bin/sh
# Claude Code's Bash tool sources a shell snapshot ending in a hard `export PATH`,
# so a profile-level direnv hook is always overwritten. Only a prefix inside the
# command itself runs late enough to survive.
set -eu

project="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$project/.envrc" ] || exit 0
command -v direnv >/dev/null 2>&1 || exit 0

jq --arg prefix 'eval "$(direnv export bash 2>/dev/null)"' '
  if (.tool_input.command // "") == "" or (.tool_input.command | startswith($prefix))
  then empty
  else {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      updatedInput: (.tool_input | .command = $prefix + "\n" + .command)
    }
  }
  end
'
