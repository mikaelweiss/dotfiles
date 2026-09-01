#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-/dev/sr0}"
MOVIES_DIR="/mnt/raid/videos/movies"

declare -a TITLES=(1 2)
declare -a NAMES=("The Land Before Time III - The Time of the Great Giving" "The Land Before Time IV - Journey Through the Mists")
declare -a YEARS=(1995 1996)

for i in "${!TITLES[@]}"; do
  TITLE="${TITLES[$i]}"
  NAME="${NAMES[$i]}"
  YEAR="${YEARS[$i]}"
  OUTPUT_DIR="$MOVIES_DIR/$NAME ($YEAR)"
  OUTPUT_FILE="$OUTPUT_DIR/$NAME ($YEAR).mkv"

  mkdir -p "$OUTPUT_DIR"

  if [ -f "$OUTPUT_FILE" ]; then
    echo "  Skipping $NAME — already exists"
    continue
  fi

  echo "  Encoding: $NAME ($YEAR) [title $TITLE]..."
  echo ""

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
      printf "\r  [%s%s] %3d%%  ETA: %s  " "$bar_fill" "$bar_empty" "$pct" "$eta"
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
    echo "  Done — $(du -h "$OUTPUT_FILE" | cut -f1)"
  else
    echo "  Error: encoding failed"
  fi

  echo ""
done

echo "  Both movies complete!"
echo ""
