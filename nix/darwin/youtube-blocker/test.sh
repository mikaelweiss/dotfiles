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

run_agent() {
  local test_home="$1"
  mkdir -p "$test_home/root"
  HOME="$test_home" PATH="$test_home/bin:/usr/bin:/bin" YOUTUBE_BLOCKER_ROOT_DIR="$test_home/root" \
    "$AGENT_SCRIPT" >/dev/null 2>&1
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
  run_agent "$test_home"
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

test_dia_skips_studio() {
  assert_eq 0 "$(counted_seconds 'https://studio.youtube.com/channel/x/livestreaming' yes)" "Dia YouTube Studio should not count"
}

redirected_tabs() {
  local blocked="$1" test_home bin_dir
  test_home=$(make_test_home)
  bin_dir="$test_home/bin"
  install_pgrep_mock "$bin_dir"
  cat > "$bin_dir/osascript" <<'MOCK'
#!/bin/bash
if [ "$1" = "-e" ]; then
  echo "$2" >> "$HOME/redirects"
  exit 0
fi
case "$(cat)" in
  *'tabs of w'*)
    printf 'W1\t1\thttps://www.youtube.com/watch?v=x\n'
    printf 'W1\t2\thttps://www.youtube.com/shorts/y\n'
    printf 'W1\t3\thttps://studio.youtube.com/channel/z\n'
    printf 'W1\t4\thttps://www.youtube.com/signin?next=studio\n'
    printf 'W1\t5\thttps://example.com/\n'
    ;;
  *) echo '' ;;
esac
MOCK
  printf '%s\n' '#!/bin/bash' 'true' > "$bin_dir/pmset"
  chmod +x "$bin_dir/osascript" "$bin_dir/pmset"
  mkdir -p "$test_home/root"
  [ "$blocked" = "yes" ] && printf 'ST_DATE=%s\nST_SECONDS=1800\n' "$(date +%F)" > "$test_home/root/state"
  run_agent "$test_home"
  [ -f "$test_home/redirects" ] && sed -E 's/.*set URL of tab ([0-9]+) .*/\1/' "$test_home/redirects" | tr '\n' ' '
  rm -rf "$test_home"
}

test_blocked_redirects_youtube_viewing_tabs() {
  assert_eq "1 2 " "$(redirected_tabs yes)" "blocked agent should redirect watch and shorts tabs only"
}

test_unblocked_leaves_tabs_alone() {
  assert_eq "" "$(redirected_tabs no)" "agent under the limit should not redirect tabs"
}

test_query_failure_keeps_heartbeat_fresh() {
  local test_home bin_dir status usage heartbeat now age
  test_home=$(make_test_home)
  bin_dir="$test_home/bin"
  install_pgrep_mock "$bin_dir"
  printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'exit 1' > "$bin_dir/osascript"
  chmod +x "$bin_dir/osascript"

  run_agent "$test_home"
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
test_dia_skips_studio
test_blocked_redirects_youtube_viewing_tabs
test_unblocked_leaves_tabs_alone
test_query_failure_keeps_heartbeat_fresh

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: 8 tests"
