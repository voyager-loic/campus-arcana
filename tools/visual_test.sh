#!/usr/bin/env bash
# Capture both players after automatic lobby readiness and spell confirmation.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/campus-arcana-shots}"
DELAY="${2:-12}"
MAP="${3:-dining_hall}"
if [[ "$OUT" == --help || "$OUT" == -h ]]; then
  echo "Usage: tools/visual_test.sh [output_directory] [delay>=10] [dining_hall|hg_e]"
  exit 0
fi
[[ "$DELAY" =~ ^[0-9]+$ ]] && (( DELAY >= 10 )) || { echo "Use at least 10 seconds to capture after deployment." >&2; exit 2; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
source tools/test_helpers.sh
test_map "$MAP"
PORT="$(test_port 0 9291)"
test_server "$PORT" "$MAP"
CODE="$(python3 tools/lobby_code.py 127.0.0.1 "$PORT")"
LIMIT=$((DELAY + 8))
test_spawn blue.log "$G" --path . -- --auto_loadout --demo --keep_after_shot --name=Blue \
  "--join_code=$CODE" "--screenshot=$OUT/shot_blue.png" "--shot_delay=$DELAY" "--quit_after=$LIMIT"
A="$TEST_LAST_PID"
test_wait_log "$TEST_SERVER_PID" server.log 'joined as slot 0'
test_spawn red.log "$G" --path . -- --auto_loadout --demo --keep_after_shot --name=Red \
  "--join_code=$CODE" "--screenshot=$OUT/shot_red.png" "--shot_delay=$DELAY" "--quit_after=$LIMIT"
B="$TEST_LAST_PID"
wait "$A" || test_fail "Blue screenshot client failed."
wait "$B" || test_fail "Red screenshot client failed."
# Check this run's log, so stale screenshots cannot produce a false success.
grep -q 'screenshot saved:' "$TEST_LOG_DIR/blue.log" || test_fail "Blue screenshot was not captured."
grep -q 'screenshot saved:' "$TEST_LOG_DIR/red.log" || test_fail "Red screenshot was not captured."
for log in blue.log red.log; do
  grep -q "screenshot saved:.*state=4 map=$MAP" "$TEST_LOG_DIR/$log" || test_fail "A screenshot was not taken during combat on $MAP."
done
test_no_errors
echo "Screenshots: $OUT/shot_blue.png and $OUT/shot_red.png"
echo "Map: $MAP. Logs: $TEST_LOG_DIR"
