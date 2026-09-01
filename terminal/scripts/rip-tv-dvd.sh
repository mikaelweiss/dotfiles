#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 4 ]; then
  echo "Usage: rip-tv-dvd \"Show Name\" season start_ep end_ep [/dev/srX]"
  echo "Example: rip-tv-dvd \"The Chosen\" 1 1 4"
  echo ""
  echo "Assumes DVD title N = episode N (title 1 = start_ep, title 2 = start_ep+1, etc.)"
  exit 1
fi

SHOW="$1"
SEASON="$2"
START_EP="$3"
END_EP="$4"
DEVICE="${5:-/dev/sr0}"
TV_DIR="/mnt/raid/videos/TV Shows"
SEASON_DIR="$TV_DIR/$SHOW/Season $(printf '%02d' "$SEASON")"

mkdir -p "$SEASON_DIR"

echo ""
echo "  $SHOW — Season $SEASON, Episodes $START_EP–$END_EP"
echo ""

TITLE=1
for EP in $(seq "$START_EP" "$END_EP"); do
  EP_TAG=$(printf 'S%02dE%02d' "$SEASON" "$EP")
  OUTPUT_FILE="$SEASON_DIR/$SHOW - $EP_TAG.mkv"

  if [ -f "$OUTPUT_FILE" ]; then
    echo "  Skipping $EP_TAG — already exists"
    TITLE=$((TITLE + 1))
    continue
  fi

  echo "  [$EP_TAG] Encoding title $TITLE..."

  while IFS= read -r line; do
    if [[ "$line" =~ Encoding:.*,\ ([0-9]+\.[0-9]+)\ %.*ETA\ ([0-9h]+[0-9m]+[0-9s]+) ]]; then
      pct="${BASH_REMATCH[1]%.*}"
      eta="${BASH_REMATCH[2]}"
      width=40
      filled=$((pct * width / 100))
      empty=$((width - filled))
      bar_fill="" bar_empty=""
      [ "$filled" -gt 0 ] && bar_fill=$(printf '%0.s#' $(seq 1 "$filled"))
      [ "$empty" -gt 0 ] && bar_empty=$(printf '%0.s-' $(seq 1 "$empty"))
      printf "\r  [$EP_TAG]  [%s%s] %3d%%  ETA: %s  " "$bar_fill" "$bar_empty" "$pct" "$eta"
    fi
  done < <(HandBrakeCLI \
    -i "$DEVICE" \
    -o "$OUTPUT_FILE" \
    --title "$TITLE" \
    --preset="Super HQ 480p30 Surround" \
    -f av_mkv \
    2>&1) || true

  echo ""

  if [ -f "$OUTPUT_FILE" ]; then
    echo "  [$EP_TAG] Done — $(du -h "$OUTPUT_FILE" | cut -f1)"
  else
    echo "  [$EP_TAG] Error: encoding failed"
  fi

  echo ""
  TITLE=$((TITLE + 1))
done

echo "  All episodes complete!"
echo ""
