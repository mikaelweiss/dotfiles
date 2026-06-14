#!/bin/bash
# no-chatbait/check: Stop hook that blocks engagement-padding ("chatbait")
# at the end of the assistant's final message.
#
# The user's CLAUDE.md forbids trailing follow-up offers ("want me to…?",
# "I can … for you", "would you like…", "let me know if…", "shall I…").
# A prose instruction is a soft constraint the model drifts past; this hook
# is the deterministic backstop.
#
# Mechanism (per https://code.claude.com/docs/en/hooks): on a Stop hook,
# exit 2 blocks the stop and feeds stderr back to Claude as instructions to
# continue/revise. stop_hook_active is true when Claude is ALREADY continuing
# because a prior Stop block fired — short-circuit then to avoid a loop.
#
# It reads the last assistant message from the transcript, inspects the
# CLOSING window (last two paragraphs, with code fences stripped), and if it
# ends on an unsolicited offer, exits 2 so the message gets rewritten.
#
# Loop guard: if stop_hook_active=true, allow the stop. That gives exactly ONE
# rewrite attempt, so a false positive on a genuinely-required clarifying
# question costs one reconsideration, never a hard lock.
#
# Observability: every invocation appends one line to log.txt next to this
# script (decision + matched phrase + closing snippet). When a miss happens,
# the log shows whether the hook fired, what text it saw, and why it allowed.
#
# Install: hooks.Stop in settings.json
# Exit codes:
#   0 — allow the stop
#   2 — block; stderr is fed back to Claude to continue and revise

set -euo pipefail

LOG="$HOME/.claude/no-chatbait/log.txt"
log() {
  # Never let logging failure affect the hook's decision.
  printf '%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

input=$(cat)

# Already mid-correction from a previous Stop block → don't re-block.
stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
if [ "$stop_active" = "true" ]; then
  log "ALLOW	loop-guard (stop_hook_active=true; one rewrite already given)"
  exit 0
fi

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
# Fail open: no readable transcript → never block a stop on a parse failure.
if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  log "ALLOW	no-transcript"
  exit 0
fi

# Last MAIN-THREAD assistant message that actually contains text. Trailing
# tool_use-only records and subagent sidechains are skipped, so we inspect the
# prose the user just saw rather than an empty final record (a turn that ends
# on a tool call would otherwise read as "no text" and slip through).
last_text=$(jq -rs '
  def textof:
    if type == "string" then .
    else (map(select(.type == "text") | .text) | join("\n"))
    end;
  [ .[]
    | select(.type == "assistant")
    | select((.isSidechain // false) | not)
    | ((.message.content // []) | textof)
    | select(. != null and (gsub("\\s"; "") | length) > 0)
  ] | last // ""
' "$transcript" 2>/dev/null || true)

if [ -z "$last_text" ]; then
  log "ALLOW	no-assistant-text"
  exit 0
fi

# Build the closing window:
#   1. Strip fenced code blocks — code (URLs, "?", "let me know" in a comment)
#      must not trip the check, AND an offer that PRECEDES a trailing code
#      block must still be seen once the block is removed.
#   2. Take the last two non-empty paragraphs — catches an offer followed by a
#      short sign-off line, while ignoring offer-shaped phrases used mid-answer.
stripped=$(printf '%s' "$last_text" \
  | awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; next} f{next} {print}')

closing=$(printf '%s' "$stripped" \
  | awk 'BEGIN{RS=""} {a[NR]=$0} END{if(NR>1)print a[NR-1]"\n"; if(NR>0)print a[NR]}')
[ -n "$closing" ] || closing="$last_text"

# Trailing engagement-padding patterns (case-insensitive).
chatbait='want me to|do you want( me)?|would you like|shall i\b|should i\b[^.?]*\?|let me know|just (say the word|let me know)|say the word|i.?d be happy to|i.?m happy to|more than happy to|happy to (help|dig|walk|set|sketch|expand|explain|go|take|put|add|write|run|wire|hook|pull|draft)|feel free to|if you.?(d| would)? ?(want|like|prefer|need)|i can (also )?[^.?!]* (for you|if you)|i could (also )?[^.?!]* (for you|if you)|your call\b|up to you\b|ready when you are|anything else|sound good\?|sounds good\?|make sense\?|makes sense\?|thoughts\?|wdyt\b|lmk\b'

if printf '%s' "$closing" | grep -qiE "$chatbait"; then
  match=$(printf '%s' "$closing" | grep -oiE "$chatbait" | head -1)
  snippet=$(printf '%s' "$closing" | tr '\n' ' ' | sed -E 's/  +/ /g' | tail -c 180)
  log "BLOCK	matched=[$match]	closing=[$snippet]"
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

log "ALLOW	clean	closing=[$(printf '%s' "$closing" | tr '\n' ' ' | sed -E 's/  +/ /g' | tail -c 120)]"
exit 0
