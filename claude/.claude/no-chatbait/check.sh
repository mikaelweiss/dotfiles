#!/bin/bash
# no-chatbait/check: Stop hook that blocks engagement-padding ("chatbait")
# at the end of the assistant's final message.
#
# The user's CLAUDE.md forbids trailing follow-up offers ("want me to…?",
# "I can … for you", "would you like…", "let me know if…", "shall I…").
# A prose instruction is a soft constraint the model drifts past; this hook
# is the deterministic backstop.
#
# It reads the last assistant message from the transcript, inspects only the
# CLOSING paragraph (where chatbait lives), and if it ends on an unsolicited
# offer, exits 2 so stderr is fed back and the message gets rewritten.
#
# Loop guard: if we're already continuing because of a prior Stop block
# (stop_hook_active=true), allow the stop. That gives exactly ONE rewrite
# attempt, so a false positive on a genuinely-required clarifying question
# costs one reconsideration, never a hard lock.
#
# Install: hooks.Stop in settings.json
# Exit codes:
#   0 — allow the stop
#   2 — block; stderr is fed back to Claude to continue and revise

set -euo pipefail

input=$(cat)

# Already mid-correction from a previous Stop block → don't re-block.
stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
[ "$stop_active" = "true" ] && exit 0

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
# Fail open: no readable transcript → never block a stop on a parse failure.
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# Last assistant message's text. content may be an array of blocks or a
# bare string; join all text blocks. Slurp (-s) to scan every line.
last_text=$(jq -rs '
  def textof:
    if type == "string" then .
    else (map(select(.type == "text") | .text) | join("\n"))
    end;
  map(select(.type == "assistant"))
  | last
  | (.message.content // [])
  | textof
' "$transcript" 2>/dev/null || true)

[ -n "$last_text" ] || exit 0

# Inspect only the closing chunk — the final non-empty paragraph — so an
# offer phrase used legitimately mid-answer doesn't trip the check.
closing=$(printf '%s' "$last_text" \
  | awk 'BEGIN{RS=""} {para=$0} END{print para}')
[ -n "$closing" ] || closing="$last_text"

# Trailing engagement-padding patterns (case-insensitive).
chatbait='want me to|do you want|would you like|shall i\b|should i\b[^.?]*\?|let me know( if)?|just (say the word|let me know)|i.?d be happy to|happy to (help|dig|walk|set|sketch|expand|explain|go)|feel free to|if you.?(d| would)? ?(want|like|prefer|need)|i can [^.?!]* (for you|if you)'

if printf '%s' "$closing" | grep -qiE "$chatbait"; then
  cat >&2 <<'EOF'
BLOCKED (chatbait): your final message ends on an unsolicited follow-up
offer / engagement-padding — the exact pattern CLAUDE.md forbids:

  "Do not append follow-up offers, suggested next steps, or 'want me to…?'
   questions unless the next action is genuinely ambiguous and you need a
   decision from me to proceed. No engagement-padding."

Revise the ending:
  - If the task is complete, just END. Delete the trailing offer entirely.
  - Keep a closing question ONLY if you genuinely cannot proceed without a
    decision from the user (a real fork, not a courtesy "want me to?").

Rewrite without the padding and stop.
EOF
  exit 2
fi

exit 0
