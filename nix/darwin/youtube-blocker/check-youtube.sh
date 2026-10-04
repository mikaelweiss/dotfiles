#!/bin/bash
# Counts daily YouTube and social media time across browsers. Runs every 15s via launchd.
# Enforcement lives in enforce.sh, which launchd runs as root.

TICK=15
STATE_DIR="$HOME/Library/Application Support/YouTubeBlocker"
USAGE="$STATE_DIR/usage"

mkdir -p "$STATE_DIR"
TODAY=$(date +%F)
NOW=$(date +%s)

# youtube-unblock adds 900s grants to the root-owned bonus file.
BONUS_DATE=""
BONUS_SECONDS=0
[ -f "/Library/Application Support/YouTubeBlocker/bonus" ] && . "/Library/Application Support/YouTubeBlocker/bonus"
[ "$BONUS_DATE" != "$TODAY" ] && BONUS_SECONDS=0
LIMIT=$((1800 + BONUS_SECONDS))
WARN=$((LIMIT - 300))

YT_DATE=""
YT_SECONDS=0
[ -f "$USAGE" ] && . "$USAGE"
[ "$YT_DATE" != "$TODAY" ] && YT_SECONDS=0

write_usage() {
  local usage_temp="$USAGE.tmp.$$"
  {
    echo "YT_DATE=$TODAY"
    echo "YT_SECONDS=$YT_SECONDS"
    echo "YT_HEARTBEAT=$NOW"
  } > "$usage_temp"
  mv "$usage_temp" "$USAGE"
}

write_usage

# YouTube counts while a video plays. Social sites count whenever the tab is in front.
TRACKED_JS="(() => { const host = location.hostname.toLowerCase(); const on = domain => host === domain || host.endsWith('.' + domain); const onYouTube = on('youtube.com') || on('youtube-nocookie.com') || host === 'youtu.be'; const onSocial = ['facebook.com', 'instagram.com', 'twitter.com', 'x.com'].some(on); return onSocial || (onYouTube && Array.from(document.querySelectorAll('video')).some(video => !video.paused && !video.ended && video.readyState >= 2)); })()"

browser_is_watching() {
  local app="$1" result
  pgrep -xq "$app" || return 1

  case "$app" in
    Arc)
      result=$(osascript <<APPLESCRIPT
tell application "Arc"
  if not frontmost or (count of windows) = 0 then return false
  return execute active tab of front window javascript "$TRACKED_JS"
end tell
APPLESCRIPT
      ) || return 2
      ;;
    Safari)
      result=$(osascript <<APPLESCRIPT
tell application "Safari"
  if not frontmost or (count of windows) = 0 then return false
  set currentTab to current tab of front window
  return do JavaScript "$TRACKED_JS" in currentTab
end tell
APPLESCRIPT
      ) || return 2
      ;;
  esac

  [ "$result" = "true" ]
}

watching=0
for browser in Arc Safari; do
  browser_is_watching "$browser"
  status=$?
  [ "$status" -eq 0 ] && watching=1 && break
  [ "$status" -eq 2 ] && exit 1
done

prev=$YT_SECONDS
[ "$watching" -eq 1 ] && YT_SECONDS=$((YT_SECONDS + TICK < LIMIT ? YT_SECONDS + TICK : LIMIT))

write_usage

if [ "$prev" -lt "$WARN" ] && [ "$YT_SECONDS" -ge "$WARN" ]; then
  osascript -e 'display notification "5 minutes of YouTube and social media left today." with title "YouTube Blocker" sound name "Sosumi"' 2>/dev/null
elif [ "$prev" -lt "$LIMIT" ] && [ "$YT_SECONDS" -ge "$LIMIT" ]; then
  osascript -e 'display notification "Time is up. YouTube and social media are blocked. sudo youtube-unblock buys 15 more minutes." with title "YouTube Blocker" sound name "Sosumi"' 2>/dev/null
fi
