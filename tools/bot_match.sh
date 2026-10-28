#!/usr/bin/env bash
# Test lobby readiness, host start, loadouts and gameplay with two bots.
set -euo pipefail
cd "$(dirname "$0")/.."
DUR="${1:-20}"
MAP="${2:-dining_hall}"
if [[ "$DUR" == --help || "$DUR" == -h ]]; then
  echo "Usage: tools/bot_match.sh [seconds>=12] [dining_hall|hg_e]"
  exit 0
fi
[[ "$DUR" =~ ^[0-9]+$ ]] && (( DUR >= 12 )) || { echo "Use at least 12 seconds so deployment can finish." >&2; exit 2; }
source tools/test_helpers.sh
test_map "$MAP"
PORT="$(test_port 0 9191)"
test_server "$PORT" "$MAP"
URL="ws://127.0.0.1:$PORT"
test_spawn bot_a.log "$G" --headless --path . --script res://tests/bot_client.gd -- \
  "--url=$URL" --name=BotA "--duration=$DUR" "--map=$MAP"
A="$TEST_LAST_PID"
test_wait_log "$A" bot_a.log 'welcomed as slot 0'
test_spawn bot_b.log "$G" --headless --path . --script res://tests/bot_client.gd -- \
  "--url=$URL" --name=BotB "--duration=$DUR" "--map=$MAP"
B="$TEST_LAST_PID"
test_wait_log "$B" bot_b.log 'welcomed as slot 1'
# A third connection must be rejected even while players are still in the lobby.
test_spawn bot_c.log "$G" --headless --path . --script res://tests/bot_client.gd -- \
  "--url=$URL" --name=BotC --duration=2 "--map=$MAP"
C="$TEST_LAST_PID"
wait "$A" || test_fail "BotA failed."
wait "$B" || test_fail "BotB failed."
wait "$C" || test_fail "Third-player rejection check failed."
for log in bot_a.log bot_b.log; do
  grep -q 'state -> 4' "$TEST_LOG_DIR/$log" || test_fail "A player never reached combat."
  grep -q "map -> $MAP," "$TEST_LOG_DIR/$log" || test_fail "A player loaded the wrong map."
done
grep -q 'rejected: Server is full' "$TEST_LOG_DIR/bot_c.log" || test_fail "The third player was not rejected."
test_no_errors
echo "PASS: both players reached combat on $MAP; third player rejected."
echo "Logs: $TEST_LOG_DIR"
