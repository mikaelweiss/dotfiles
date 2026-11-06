#!/bin/bash
# Counts daily YouTube and social media time across browsers. Runs every 15s via launchd.
# Enforcement lives in enforce.sh, which launchd runs as root.

TICK=15
STATE_DIR="$HOME/Library/Application Support/YouTubeBlocker"
USAGE="$STATE_DIR/usage"

mkdir -p "$STATE_DIR"
TODAY=$(date +%F)
NOW=$(date +%s)

ROOT_DIR="${YOUTUBE_BLOCKER_ROOT_DIR:-/Library/Application Support/YouTubeBlocker}"
STUDIO_URL="https://studio.youtube.com/"

# youtube-unblock adds 900s grants to the root-owned bonus file.
BONUS_DATE=""
BONUS_SECONDS=0
[ -f "$ROOT_DIR/bonus" ] && . "$ROOT_DIR/bonus"
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

ST_DATE=""
ST_SECONDS=0
[ -f "$ROOT_DIR/state" ] && . "$ROOT_DIR/state"
[ "$ST_DATE" != "$TODAY" ] && ST_SECONDS=0

url_host() {
  printf '%s' "$1" | sed -E 's#^[A-Za-z]+://([^/:]+).*#\1#' | tr '[:upper:]' '[:lower:]'
}

# Studio signs in through www.youtube.com, so the hosts file cannot block
# watching without breaking uploads and streams. The agent redirects each
# viewing tab instead.
is_youtube_viewing_url() {
  local path
  case "$(url_host "$1")" in
    youtube.com|www.youtube.com|m.youtube.com) ;;
    *) return 1 ;;
  esac
  path=$(printf '%s' "$1" | sed -E 's#^[A-Za-z]+://[^/]+##')
  case "$path" in
    /signin*|/logout*|/upload*|/live_dashboard*|/account*) return 1 ;;
  esac
  return 0
}

list_tabs() {
  osascript <<APPLESCRIPT
tell application "$1"
  set tabList to ""
  repeat with w in windows
    set windowId to id of w
    set tabIndex to 0
    repeat with t in tabs of w
      set tabIndex to tabIndex + 1
      try
        set tabList to tabList & windowId & (character id 9) & tabIndex & (character id 9) & (URL of t) & linefeed
      end try
    end repeat
  end repeat
  return tabList
end tell
APPLESCRIPT
}

redirect_tab() {
  local app="$1" window_id="$2" tab_index="$3" window_ref
  case "$app" in
    Dia) window_ref="window id \"$window_id\"" ;;
    Safari) window_ref="window id $window_id" ;;
  esac
  osascript -e "tell application \"$app\" to set URL of tab $tab_index of $window_ref to \"$STUDIO_URL\""
}

redirect_youtube_tabs() {
  local app window_id tab_index url
  for app in Dia Safari; do
    pgrep -xq "$app" || continue
    list_tabs "$app" | while IFS=$'\t' read -r window_id tab_index url; do
      is_youtube_viewing_url "$url" && redirect_tab "$app" "$window_id" "$tab_index"
    done
  done
}

[ $((ST_SECONDS > YT_SECONDS ? ST_SECONDS : YT_SECONDS)) -ge "$LIMIT" ] && redirect_youtube_tabs 2>/dev/null

# YouTube counts while a video plays. Social sites count whenever the tab is in front.
TRACKED_JS="(() => { const host = location.hostname.toLowerCase(); const on = domain => host === domain || host.endsWith('.' + domain); const onYouTube = (on('youtube.com') && host !== 'studio.youtube.com') || on('youtube-nocookie.com') || host === 'youtu.be'; const onSocial = ['facebook.com', 'instagram.com', 'twitter.com', 'x.com'].some(on); return onSocial || (onYouTube && Array.from(document.querySelectorAll('video')).some(video => !video.paused && !video.ended && video.readyState >= 2)); })()"

# Dia runs JavaScript from AppleScript only when launched with
# --enable-applescript-javascript, so it reads the tab URL and Chromium's
# video wake lock instead.
dia_url_is_watching() {
  case "$(url_host "$1")" in
    studio.youtube.com)
      return 1 ;;
    facebook.com|*.facebook.com|instagram.com|*.instagram.com|twitter.com|*.twitter.com|x.com|*.x.com)
      return 0 ;;
    youtube.com|*.youtube.com|youtube-nocookie.com|*.youtube-nocookie.com|youtu.be)
      pmset -g assertions | grep -q '(Dia):.*"Video Wake Lock"' ;;
    *)
      return 1 ;;
  esac
}

browser_is_watching() {
  local app="$1" result
  pgrep -xq "$app" || return 1

  case "$app" in
    Dia)
      result=$(osascript <<APPLESCRIPT
tell application "Dia"
  if not frontmost or (count of windows) = 0 then return ""
  return URL of active tab of front window
end tell
APPLESCRIPT
      ) || return 2
      dia_url_is_watching "$result"
      return
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
for browser in Dia Safari; do
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
  osascript -e 'display notification "Time is up. YouTube and social media are blocked, Studio still works. sudo youtube-unblock buys 15 more minutes." with title "YouTube Blocker" sound name "Sosumi"' 2>/dev/null
fi
