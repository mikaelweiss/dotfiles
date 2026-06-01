#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: rip-dvd-mkv \"Movie Name\" \"Year\" [/dev/srX]"
  echo "Example: rip-dvd-mkv \"The Prince of Egypt\" \"1998\""
  exit 1
fi

NAME="$1"
YEAR="$2"
DEVICE="${3:-/dev/sr0}"
trap 'eject "$DEVICE" 2>/dev/null || true' EXIT
MOVIES_DIR="/mnt/raid/videos/movies"
OUTPUT_DIR="$MOVIES_DIR/$NAME ($YEAR)"
OUTPUT_FILE="$OUTPUT_DIR/$NAME ($YEAR).mkv"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"; eject "$DEVICE" 2>/dev/null || true' EXIT

if [ -f "$OUTPUT_FILE" ]; then
  echo "Error: $OUTPUT_FILE already exists"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo ""
echo "  $NAME ($YEAR)"
echo ""

# Step 1: Rip with MakeMKV (handles copy protection)
echo "  Ripping disc with MakeMKV..."
while IFS= read -r line; do
  if [[ "$line" =~ ^PRGV:([0-9]+),([0-9]+),([0-9]+) ]]; then
    current="${BASH_REMATCH[1]}"
    total="${BASH_REMATCH[3]}"
    if [ "$total" -gt 0 ]; then
      pct=$((current * 100 / total))
      width=40
      filled=$((pct * width / 100))
      empty=$((width - filled))
      bar_fill="" bar_empty=""
      [ "$filled" -gt 0 ] && bar_fill=$(printf '%0.s#' $(seq 1 "$filled"))
      [ "$empty" -gt 0 ] && bar_empty=$(printf '%0.s-' $(seq 1 "$empty"))
      printf "\r  Ripping    [%s%s] %3d%%  " "$bar_fill" "$bar_empty" "$pct"
    fi
  fi
done < <(makemkvcon mkv --minlength=2400 --robot disc:0 all "$TMP_DIR" 2>&1) || true

echo ""

# Find the largest MKV (the main feature)
RIPPED_FILE=$(ls -S "$TMP_DIR"/*.mkv 2>/dev/null | head -1)
if [ -z "$RIPPED_FILE" ]; then
  echo "  Error: MakeMKV produced no output"
  exit 1
fi

echo "  Ripped $(du -h "$RIPPED_FILE" | cut -f1) — now encoding with HandBrake..."
echo ""

# Step 2: Encode with HandBrake
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
    printf "\r  Encoding   [%s%s] %3d%%  ETA: %s  " "$bar_fill" "$bar_empty" "$pct" "$eta"
  fi
done < <(HandBrakeCLI \
  -i "$RIPPED_FILE" \
  -o "$OUTPUT_FILE" \
  --preset="Super HQ 480p30 Surround" \
  -f av_mkv \
  2>&1) || true

echo ""

if [ ! -f "$OUTPUT_FILE" ]; then
  echo "  Error: encoding failed"
  exit 1
fi

echo ""
echo "  Done! $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""
echo "  Disc ejected — ready for the next one!"
echo ""
