#!/bin/bash

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
AGENT_SCRIPT="$SCRIPT_DIR/check-youtube.sh"
failures=0

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $message (expected '$expected', got '$actual')"
    failures=$((failures + 1))
  fi
}

make_test_home() {
  mktemp -d /tmp/youtube-blocker-test.XXXXXX
}

install_pgrep_mock() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  printf '%s\n' '#!/bin/bash' '[ "$2" = "Dia" ]' > "$bin_dir/pgrep"
  chmod +x "$bin_dir/pgrep"
}

install_dia_mocks() {
  local bin_dir="$1" url="$2" wake_lock="$3"
  install_pgrep_mock "$bin_dir"
  cat > "$bin_dir/osascript" <<MOCK
#!/bin/bash
case "\$(cat)" in
  *'URL of active tab of front window'*) echo '$url' ;;
  *) exit 1 ;;
esac
MOCK
  if [ "$wake_lock" = "yes" ]; then
    printf '%s\n' '#!/bin/bash' "echo '   pid 1515(Dia): [0x1] 00:00:17 NoDisplaySleepAssertion named: \"Video Wake Lock\"'" > "$bin_dir/pmset"
  else
    printf '%s\n' '#!/bin/bash' 'true' > "$bin_dir/pmset"
  fi
  chmod +x "$bin_dir/osascript" "$bin_dir/pmset"
}

counted_seconds() {
  local url="$1" wake_lock="$2" test_home bin_dir
  test_home=$(make_test_home)
  bin_dir="$test_home/bin"
  install_dia_mocks "$bin_dir" "$url" "$wake_lock"
  HOME="$test_home" PATH="$bin_dir:/usr/bin:/bin" "$AGENT_SCRIPT" >/dev/null 2>&1
  YT_SECONDS=0
  . "$test_home/Library/Application Support/YouTubeBlocker/usage"
  echo "$YT_SECONDS"
  rm -rf "$test_home"
}

test_dia_counts_playing_youtube() {
  assert_eq 15 "$(counted_seconds 'https://www.youtube.com/watch?v=x' yes)" "Dia YouTube with a video wake lock should count"
}

test_dia_skips_paused_youtube() {
  assert_eq 0 "$(counted_seconds 'https://www.youtube.com/watch?v=x' no)" "Dia YouTube without a video wake lock should not count"
}

test_dia_counts_social_in_front() {
  assert_eq 15 "$(counted_seconds 'https://x.com/home' no)" "Dia social tab in front should count"
}

test_dia_skips_other_sites() {
  assert_eq 0 "$(counted_seconds 'https://example.com/youtube.com' yes)" "Dia non-tracked site should not count"
}

test_query_failure_keeps_heartbeat_fresh() {
  local test_home bin_dir status usage heartbeat now age
  test_home=$(make_test_home)
  bin_dir="$test_home/bin"
  install_pgrep_mock "$bin_dir"
  printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'exit 1' > "$bin_dir/osascript"
  chmod +x "$bin_dir/osascript"

  HOME="$test_home" PATH="$bin_dir:/usr/bin:/bin" "$AGENT_SCRIPT" >/dev/null 2>&1
  status=$?
  assert_eq 1 "$status" "browser query errors should remain visible"

  usage="$test_home/Library/Application Support/YouTubeBlocker/usage"
  if [ ! -f "$usage" ]; then
    echo "FAIL: a failed browser query should still write a heartbeat"
    failures=$((failures + 1))
  else
    YT_HEARTBEAT=0
    . "$usage"
    heartbeat=$YT_HEARTBEAT
    now=$(date +%s)
    age=$((now - heartbeat))
    if [ "$age" -lt 0 ] || [ "$age" -gt 5 ]; then
      echo "FAIL: heartbeat should be current after a browser query error (age ${age}s)"
      failures=$((failures + 1))
    fi
  fi
  rm -rf "$test_home"
}

test_dia_counts_playing_youtube
test_dia_skips_paused_youtube
test_dia_counts_social_in_front
test_dia_skips_other_sites
test_query_failure_keeps_heartbeat_fresh

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: 5 tests"
