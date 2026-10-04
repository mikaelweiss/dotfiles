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
  printf '%s\n' '#!/bin/bash' '[ "$2" = "Arc" ]' > "$bin_dir/pgrep"
  chmod +x "$bin_dir/pgrep"
}

test_arc_uses_direct_tab_specifier() {
  local test_home bin_dir status
  test_home=$(make_test_home)
  bin_dir="$test_home/bin"
  install_pgrep_mock "$bin_dir"
  cat > "$bin_dir/osascript" <<'MOCK'
#!/bin/bash
script=$(cat)
case "$script" in
  *'execute active tab of front window javascript'*) echo false; exit 0 ;;
  *) exit 1 ;;
esac
MOCK
  chmod +x "$bin_dir/osascript"

  HOME="$test_home" PATH="$bin_dir:/usr/bin:/bin" "$AGENT_SCRIPT" >/dev/null 2>&1
  status=$?
  assert_eq 0 "$status" "Arc query should use a directly addressable tab specifier"
  rm -rf "$test_home"
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

test_arc_uses_direct_tab_specifier
test_query_failure_keeps_heartbeat_fresh

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: 2 tests"
