#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-/dev/sr0}"
TV_DIR="/mnt/raid/videos/TV Shows"
SHOW="Tom and Jerry Tales"
SEASON=1
SEASON_DIR="$TV_DIR/$SHOW/Season 01"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$SEASON_DIR"

declare -a EP_NUMS=(8 3 2 1)
declare -a TITLE_A=(2 5 8 11)
declare -a TITLE_B=(3 6 9 12)
declare -a TITLE_C=(4 7 10 13)

for i in "${!EP_NUMS[@]}"; do
  EP="${EP_NUMS[$i]}"
  EP_TAG=$(printf 'S%02dE%02d' "$SEASON" "$EP")
  OUTPUT_FILE="$SEASON_DIR/$SHOW - $EP_TAG.mkv"

  if [ -f "$OUTPUT_FILE" ]; then
    echo "  Skipping $EP_TAG — already exists"
    continue
  fi

  TITLES=("${TITLE_A[$i]}" "${TITLE_B[$i]}" "${TITLE_C[$i]}")
  PARTS=()

  for t in "${TITLES[@]}"; do
    PART_FILE="$TMP_DIR/ep${EP}_title${t}.mkv"
    PARTS+=("$PART_FILE")

    echo "  [$EP_TAG] Encoding title $t of 3..."

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
      -o "$PART_FILE" \
      --title "$t" \
      --preset="Super HQ 480p30 Surround" \
      -f av_mkv \
      2>&1) || true

    echo ""
  done

  echo "  [$EP_TAG] Joining 3 segments..."
  CONCAT_LIST="$TMP_DIR/concat_ep${EP}.txt"
  for p in "${PARTS[@]}"; do
    echo "file '$p'" >> "$CONCAT_LIST"
  done

  ffmpeg -nostdin -y -loglevel quiet \
    -f concat -safe 0 -i "$CONCAT_LIST" \
    -c copy \
    "$OUTPUT_FILE"

  if [ -f "$OUTPUT_FILE" ]; then
    echo "  [$EP_TAG] Done — $(du -h "$OUTPUT_FILE" | cut -f1)"
  else
    echo "  [$EP_TAG] Error: join failed"
  fi

  rm -f "${PARTS[@]}" "$CONCAT_LIST"
  echo ""
done

echo "  All episodes complete!"
echo ""
