#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-/dev/sr0}"
STAGING="/mnt/raid/videos/TV Shows/_staging-pbs-disc2"

mkdir -p "$STAGING"

for TITLE in 2 3 5 6 7 8 9 10 11; do
  OUT="$STAGING/title-${TITLE}.mkv"
  if [ -f "$OUT" ]; then
    echo "Skipping title $TITLE — already exists"
    continue
  fi
  echo ""
  echo "Encoding title $TITLE..."
  HandBrakeCLI -i "$DEVICE" -o "$OUT" --title "$TITLE" \
    --preset="Super HQ 480p30 Surround" -f av_mkv 2>&1 | \
    grep --line-buffered -oP 'Encoding:.*' | while IFS= read -r line; do
      printf "\r  %s  " "$line"
    done
  echo ""
  echo "Done: $(du -h "$OUT" | cut -f1)"
done

echo ""
echo "All titles ripped to $STAGING"
echo "Watch the first few seconds of each to identify them, then come back."
