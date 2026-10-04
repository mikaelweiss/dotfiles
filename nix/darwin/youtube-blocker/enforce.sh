#!/bin/bash
# Root enforcer for YouTube Blocker. Runs every 30s via LaunchDaemon.
# Reads the user agent's counter, keeps a monotonic root-owned copy,
# and blocks YouTube and social media in /etc/hosts once the daily limit is reached.

LIMIT=1800
TICK=30
USER_STATE_DIR="/Users/mikaelweiss/Library/Application Support/YouTubeBlocker"
USAGE="$USER_STATE_DIR/usage"
ROOT_DIR="/Library/Application Support/YouTubeBlocker"
STATE="$ROOT_DIR/state"
HOSTS="/etc/hosts"
MARK_BEGIN="# youtube-blocker BEGIN"
MARK_END="# youtube-blocker END"

TODAY=$(date +%F)
NOW=$(date +%s)
mkdir -p "$ROOT_DIR"

ST_DATE=""
ST_SECONDS=0
[ -f "$STATE" ] && . "$STATE"
if [ "$ST_DATE" != "$TODAY" ]; then
  ST_SECONDS=0
  rm -f "$ROOT_DIR/bonus" "$ROOT_DIR"/unlock-* 2>/dev/null
fi

# Each successful youtube-unblock adds 900s of watch time for today.
BONUS_DATE=""
BONUS_SECONDS=0
[ -f "$ROOT_DIR/bonus" ] && . "$ROOT_DIR/bonus"
[ "$BONUS_DATE" != "$TODAY" ] && BONUS_SECONDS=0

YT_DATE=""
YT_SECONDS=0
YT_HEARTBEAT=0
[ -f "$USAGE" ] && . "$USAGE"
if [ "$YT_DATE" = "$TODAY" ] && [ "$YT_SECONDS" -gt "$ST_SECONDS" ]; then
  ST_SECONDS=$YT_SECONDS
fi

# Tamper detection: if the counting agent stops heartbeating while a browser
# is running, ALL browser time counts as YouTube time.
tampered=0
if pgrep -xq Arc || pgrep -xq Safari; then
  [ $((NOW - YT_HEARTBEAT)) -gt 120 ] && tampered=1
fi
[ "$tampered" -eq 1 ] && ST_SECONDS=$((ST_SECONDS + TICK))

{
  echo "ST_DATE=$TODAY"
  echo "ST_SECONDS=$ST_SECONDS"
} > "$STATE"
chmod 644 "$STATE"

block() {
  grep -qF "$MARK_BEGIN" "$HOSTS" && return
  {
    echo "$MARK_BEGIN"
    for d in youtube.com www.youtube.com m.youtube.com music.youtube.com \
             youtu.be www.youtube-nocookie.com \
             youtubei.googleapis.com youtube.googleapis.com \
             facebook.com www.facebook.com m.facebook.com web.facebook.com \
             instagram.com www.instagram.com \
             twitter.com www.twitter.com mobile.twitter.com api.twitter.com \
             x.com www.x.com api.x.com; do
      echo "0.0.0.0 $d"
      echo ":: $d"
    done
    echo "$MARK_END"
  } >> "$HOSTS"
  dscacheutil -flushcache
  killall -HUP mDNSResponder
}

unblock() {
  grep -qF "$MARK_BEGIN" "$HOSTS" || return
  sed -i '' "/^$MARK_BEGIN\$/,/^$MARK_END\$/d" "$HOSTS"
  dscacheutil -flushcache
  killall -HUP mDNSResponder
}

if [ "$ST_SECONDS" -ge $((LIMIT + BONUS_SECONDS)) ]; then
  block
else
  unblock
fi
