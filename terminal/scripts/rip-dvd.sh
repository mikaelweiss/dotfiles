#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: rip-dvd \"Movie Name\" \"Year\""
  echo "Example: rip-dvd \"The Prince of Egypt\" \"1998\""
  exit 1
fi

NAME="$1"
YEAR="$2"
DEVICE="${3:-/dev/sr0}"
MOVIES_DIR="/mnt/raid/videos/movies"
OUTPUT_DIR="$MOVIES_DIR/$NAME ($YEAR)"
OUTPUT_FILE="$OUTPUT_DIR/$NAME ($YEAR).mkv"
TEMP_DIR=$(mktemp -d)

cleanup() {
  kill "$MONITOR_PID" 2>/dev/null || true
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [ -f "$OUTPUT_FILE" ]; then
  echo "Error: $OUTPUT_FILE already exists"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

bar_str() {
  local pct=$1 width=40
  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  local bar_fill="" bar_empty=""
  [ "$filled" -gt 0 ] && bar_fill=$(printf '%0.s#' $(seq 1 "$filled"))
  [ "$empty" -gt 0 ] && bar_empty=$(printf '%0.s-' $(seq 1 "$empty"))
  printf "[%s%s] %3d%%" "$bar_fill" "$bar_empty" "$pct"
}

waiting_str() {
  local width=40
  printf "[%s] %s" "$(printf '%0.s.' $(seq 1 "$width"))" "    "
}

draw_both() {
  local ext_pct=$1 enc_str=$2
  printf "\033[2A"
  printf "\r  Extracting  %s\n" "$(bar_str "$ext_pct")"
  printf "\r  Encoding    %s\n" "$enc_str"
}

draw_enc() {
  local enc_pct=$1
  printf "\033[1A"
  printf "\r  Encoding    %s\n" "$(bar_str "$enc_pct")"
}

echo ""
echo "  $NAME ($YEAR)"
echo ""

# Get total DVD size for progress tracking
TOTAL_BYTES=$(dvdbackup -I -i "$DEVICE" 2>&1 | grep -oP 'Total size: \K[0-9]+' || echo "0")
if [ "$TOTAL_BYTES" = "0" ]; then
  TOTAL_BYTES=$(blockdev --getsize64 "$DEVICE" 2>/dev/null || echo "4700000000")
fi

# Print both bars initially
printf "  Extracting  %s\n" "$(bar_str 0)"
printf "  Encoding    %s\n" "$(waiting_str)"

# Step 1: Extract DVD (feature mode auto-selects the main movie)
MONITOR_PID=""
(
  while true; do
    CURRENT=$(du -sb "$TEMP_DIR" 2>/dev/null | cut -f1 || echo "0")
    if [ "$TOTAL_BYTES" -gt 0 ] 2>/dev/null; then
      PCT=$((CURRENT * 100 / TOTAL_BYTES))
      [ "$PCT" -gt 100 ] && PCT=100
      draw_both "$PCT" "$(waiting_str)"
    fi
    sleep 2
  done
) &
MONITOR_PID=$!

dvdbackup -F -i "$DEVICE" -o "$TEMP_DIR" >/dev/null 2>&1

kill "$MONITOR_PID" 2>/dev/null || true
draw_both 100 "$(bar_str 0)"

# Find the extracted VOB files (feature mode picks the right title set)
DVD_DIR=("$TEMP_DIR"/*)
VOB_DIR="${DVD_DIR[0]}/VIDEO_TS"
VOB_FILES=("$VOB_DIR"/VTS_*_[1-9]*.VOB)

if [ ${#VOB_FILES[@]} -eq 0 ]; then
  echo "Error: No VOB files found"
  exit 1
fi

# Build concat demuxer file list
CONCAT_LIST="$TEMP_DIR/concat.txt"
for f in "${VOB_FILES[@]}"; do
  echo "file '$f'" >> "$CONCAT_LIST"
done

# Get duration for encoding progress (try concat list first, then first VOB directly)
DURATION=$(ffprobe -v quiet -show_entries format=duration \
  -f concat -safe 0 -i "$CONCAT_LIST" 2>/dev/null | grep -oP 'duration=\K[0-9.]+' || echo "0")
if [ "$DURATION" = "0" ] || [ -z "$DURATION" ]; then
  DURATION=$(ffprobe -v quiet -probesize 50M -analyzeduration 100M \
    -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \
    -i "concat:$(printf '%s|' "${VOB_FILES[@]}" | sed 's/|$//')" 2>/dev/null || echo "0")
fi
if [ "$DURATION" = "0" ] || [ -z "$DURATION" ]; then
  DURATION=$(ffprobe -v quiet -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "${VOB_FILES[0]}" 2>/dev/null || echo "0")
  if [ "$DURATION" != "0" ] && [ -n "$DURATION" ]; then
    DURATION=$(awk "BEGIN {printf \"%.0f\", $DURATION * ${#VOB_FILES[@]}}")
  fi
fi

# Step 2: Encode
PROGRESS_FILE="$TEMP_DIR/ffmpeg_progress"
ffmpeg -nostdin -y -loglevel quiet \
  -probesize 50M -analyzeduration 100M \
  -fflags +genpts \
  -f concat -safe 0 -i "$CONCAT_LIST" \
  -map 0:v:0 -map 0:a \
  -vf bwdif -c:v libx264 -crf 18 -c:a aac \
  -progress "$PROGRESS_FILE" \
  "$OUTPUT_FILE" &
FFMPEG_PID=$!

DURATION_US=0
if [ "$DURATION" != "0" ] && [ -n "$DURATION" ]; then
  DURATION_US=$(awk "BEGIN {printf \"%.0f\", $DURATION * 1000000}")
fi

while kill -0 "$FFMPEG_PID" 2>/dev/null; do
  if [ -f "$PROGRESS_FILE" ]; then
    CURRENT_US=$(grep -oP 'out_time_us=\K[0-9]+' "$PROGRESS_FILE" 2>/dev/null | tail -1 || echo "0")
    if [ "$DURATION_US" -gt 0 ] && [ "$CURRENT_US" -gt 0 ] 2>/dev/null; then
      PCT=$((CURRENT_US * 100 / DURATION_US))
      [ "$PCT" -gt 100 ] && PCT=100
      draw_enc "$PCT"
    elif [ "$CURRENT_US" -gt 0 ] 2>/dev/null; then
      ELAPSED_MIN=$((CURRENT_US / 60000000))
      printf "\033[1A"
      printf "\r  Encoding    %d min encoded...\033[K\n" "$ELAPSED_MIN"
    fi
  fi
  sleep 2
done

wait "$FFMPEG_PID"
draw_enc 100

SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
echo ""
echo "  Done! $SIZE"
echo ""

eject "$DEVICE"
echo "  Disc ejected — ready for the next one!"
echo ""
