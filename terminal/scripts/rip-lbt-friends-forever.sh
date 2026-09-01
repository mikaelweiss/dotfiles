#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-/dev/sr0}"
TV_DIR="/mnt/raid/videos/TV Shows"
SHOW="The Land Before Time"

declare -a TITLES=(1 2 3 4)
declare -a SEASONS=(1 1 2 1)
declare -a EPISODES=(2 14 1 11)

for i in "${!TITLES[@]}"; do
  TITLE="${TITLES[$i]}"
  SEASON="${SEASONS[$i]}"
  EP="${EPISODES[$i]}"
  EP_TAG=$(printf 'S%02dE%02d' "$SEASON" "$EP")
  SEASON_DIR="$TV_DIR/$SHOW/Season $(printf '%02d' "$SEASON")"
  OUTPUT_FILE="$SEASON_DIR/$SHOW - $EP_TAG.mkv"

  mkdir -p "$SEASON_DIR"

  if [ -f "$OUTPUT_FILE" ]; then
    echo "  Skipping $EP_TAG — already exists"
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
done

echo "  All episodes complete!"
echo ""
