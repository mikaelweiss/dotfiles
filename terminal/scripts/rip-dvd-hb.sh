#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: rip-dvd-hb \"Movie Name\" \"Year\""
  echo "Example: rip-dvd-hb \"The Prince of Egypt\" \"1998\""
  exit 1
fi

DVDNAV=""
for arg in "$@"; do
  [[ "$arg" == "--no-dvdnav" ]] && DVDNAV="--no-dvdnav"
done

NAME="$1"
YEAR="$2"
DEVICE="${3:-/dev/sr0}"
trap 'eject "$DEVICE" 2>/dev/null || true' EXIT
TITLE="${4:-}"
MOVIES_DIR="/mnt/raid/videos/movies"
OUTPUT_DIR="$MOVIES_DIR/$NAME ($YEAR)"
OUTPUT_FILE="$OUTPUT_DIR/$NAME ($YEAR).mkv"

if [ -f "$OUTPUT_FILE" ]; then
  echo "Error: $OUTPUT_FILE already exists"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo ""
echo "  $NAME ($YEAR)"
echo ""

exec 3< <(HandBrakeCLI \
  -i "$DEVICE" \
  -o "$OUTPUT_FILE" \
  ${TITLE:+--title "$TITLE"} ${TITLE:---main-feature} $DVDNAV \
  --preset="Super HQ 480p30 Surround" \
  -f av_mkv \
  2>&1)
HB_PID=$!

error_count=0
while IFS= read -r -t 1800 line <&3; do
  if [[ "$line" =~ Encoding:.*,\ ([0-9]+\.[0-9]+)\ %.*ETA\ ([0-9h]+[0-9m]+[0-9s]+) ]]; then
    error_count=0
    pct="${BASH_REMATCH[1]%.*}"
    eta="${BASH_REMATCH[2]}"
    width=40
    filled=$((pct * width / 100))
    empty=$((width - filled))
    bar_fill="" bar_empty=""
    [ "$filled" -gt 0 ] && bar_fill=$(printf '%0.s#' $(seq 1 "$filled"))
    [ "$empty" -gt 0 ] && bar_empty=$(printf '%0.s-' $(seq 1 "$empty"))
    printf "\r  Encoding  [%s%s] %3d%%  ETA: %s  " "$bar_fill" "$bar_empty" "$pct" "$eta"
  elif [[ "$line" =~ "error" || "$line" =~ "Error" ]]; then
    echo "$line" >&2
    ((error_count++)) || true
    if [ "$error_count" -ge 10 ]; then
      echo "" >&2
      echo "  Too many consecutive read errors, stopping" >&2
      break
    fi
  fi
done

exec 3<&-
kill "$HB_PID" 2>/dev/null || true
wait "$HB_PID" 2>/dev/null || true

echo ""

if [ ! -f "$OUTPUT_FILE" ]; then
  rmdir "$OUTPUT_DIR" 2>/dev/null || true
  echo "  Error: encoding failed"
  exit 1
fi

echo ""
echo "  Done! $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""

echo "  Disc ejected — ready for the next one!"
echo ""
