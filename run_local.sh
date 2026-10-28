#!/usr/bin/env bash
# Start a private test lobby and open two desktop players, already connected.
set -euo pipefail
cd "$(dirname "$0")"

MODE=desktop
MAP=dining_hall
NO_EXPORT=false
NO_OPEN=false
GAME_PORT=0
WEB_PORT=0
DURATION=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --web) MODE=web; shift ;;
    --lan) MODE=lan; shift ;;
    --no-export) NO_EXPORT=true; shift ;;
    --no-open) NO_OPEN=true; shift ;;
    --map|--port|--web-port|--duration)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --map) MAP="$2" ;;
        --port) GAME_PORT="$2" ;;
        --web-port) WEB_PORT="$2" ;;
        --duration) DURATION="$2" ;;
      esac
      shift 2 ;;
    --help|-h)
      echo "Usage: ./run_local.sh [--map dining_hall|hg_e] [--web|--lan]"
      echo "Default: two desktop players connected to one lobby."
      echo "--web: two browser players. --lan: one browser player plus an invite for another PC."
      echo "Optional: --no-export --no-open --port N --web-port N --duration SECONDS"
      exit 0 ;;
    *) echo "Unknown option: $1. Use --help." >&2; exit 2 ;;
  esac
done
for value in "$GAME_PORT" "$WEB_PORT" "$DURATION"; do
  [[ "$value" =~ ^[0-9]+$ ]] || { echo "Ports and duration must be whole numbers." >&2; exit 2; }
done
source tools/test_helpers.sh
test_map "$MAP"
GAME_PORT="$(test_port "$GAME_PORT" 9080)"
if [[ "$MODE" != desktop ]]; then WEB_PORT="$(test_port "$WEB_PORT" 8080)"; fi

if [[ "$MODE" != desktop ]]; then
  if [[ "$NO_EXPORT" != true || ! -f build/web/index.html ]]; then ./export_web.sh; fi
  if [[ "$MODE" == lan ]]; then python3 tools/patch_web_lan.py build/web/index.js; fi
fi
test_server "$GAME_PORT" "$MAP"
SERVER_URL="ws://127.0.0.1:$GAME_PORT"
ADDRESS=127.0.0.1
if [[ "$MODE" == lan ]]; then
  ADDRESS="$(python3 - <<'PY'
import socket
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
    try:
        probe.connect(("192.0.2.1", 9))
        print(probe.getsockname()[0])
    except OSError:
        raise SystemExit("Could not determine the LAN address. Connect to your local network first.")
PY
)"
  SERVER_URL="ws://$ADDRESS:$GAME_PORT"
fi
CODE="$(python3 tools/lobby_code.py "$ADDRESS" "$GAME_PORT")"
echo "Lobby code: $CODE"
echo "Map: $MAP"
echo "Both players: Ready Up. Host: Continue to Spells. Then confirm both squads."
echo "Change maps in the lobby. Ctrl+C stops all test processes."
echo "Logs: $TEST_LOG_DIR"
CLIENT_A=0
CLIENT_B=0
if [[ "$MODE" == desktop ]]; then
  if [[ "$NO_OPEN" != true ]]; then
    CLIENT_ARGS=("--quit_after=$DURATION")
    test_spawn player_one.log "$G" --path . --position 40,60 -- \
      --name=PlayerOne "--server=$SERVER_URL" "--join_code=$CODE" "${CLIENT_ARGS[@]}"
    CLIENT_A="$TEST_LAST_PID"
    test_wait_log "$TEST_SERVER_PID" server.log 'joined as slot 0'
    test_spawn player_two.log "$G" --path . --position 160,100 -- \
      --name=PlayerTwo "--server=$SERVER_URL" "--join_code=$CODE" "${CLIENT_ARGS[@]}"
    CLIENT_B="$TEST_LAST_PID"
  fi
else
  test_spawn web.log python3 tools/serve_web.py "$WEB_PORT" build/web
  WEB_PID="$TEST_LAST_PID"
  # Confirm the HTTP listener rather than opening a browser before it is ready.
  for attempt in {1..80}; do
    if curl --silent --fail "http://127.0.0.1:$WEB_PORT/" -o /dev/null; then break; fi
    kill -0 "$WEB_PID" 2>/dev/null || test_fail "The web server stopped."
    if [[ "$attempt" == 80 ]]; then test_fail "The web server did not become ready."; fi
    sleep 0.1
  done
  URL="http://localhost:$WEB_PORT/?join_code=$CODE"
  echo "Web game: $URL"
  if [[ "$MODE" == lan ]]; then
    echo "Other PC: http://$ADDRESS:$WEB_PORT/?join_code=$CODE"
    echo "LAN browser mode has no audio or microphone; keyboard and mouse work."
  fi
  if [[ "$NO_OPEN" != true ]]; then
    OPENER=()
    if command -v open >/dev/null 2>&1; then OPENER=(open)
    elif command -v xdg-open >/dev/null 2>&1; then OPENER=(xdg-open); fi
    if [[ ${#OPENER[@]} -gt 0 ]]; then
      "${OPENER[@]}" "${URL}&name=PlayerOne"
      if [[ "$MODE" == web ]]; then
        test_wait_log "$TEST_SERVER_PID" server.log 'joined as slot 0'
        "${OPENER[@]}" "${URL}&name=PlayerTwo"
      fi
    fi
  fi
  echo "Keep both browser players in visible windows during local testing."
fi

START_TIME=$SECONDS
while kill -0 "$TEST_SERVER_PID" 2>/dev/null; do
  if (( DURATION > 0 && SECONDS - START_TIME >= DURATION )); then exit 0; fi
  if [[ "$MODE" == desktop && "$NO_OPEN" != true ]]; then
    if ! kill -0 "$CLIENT_A" 2>/dev/null || ! kill -0 "$CLIENT_B" 2>/dev/null; then exit 0; fi
  elif [[ "$MODE" != desktop ]]; then
    kill -0 "$WEB_PID" 2>/dev/null || test_fail "The web server stopped."
  fi
  sleep 0.25
done
test_fail "The game server stopped."
