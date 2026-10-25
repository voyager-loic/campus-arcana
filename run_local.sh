#!/usr/bin/env bash
# One-command local test: exports the web client, starts the game server and a
# static web server, and opens two browser tabs (one per player).
#   ./run_local.sh                 (re-export + local run)
#   ./run_local.sh --no-export
#   ./run_local.sh --lan           (allow another PC over plain LAN HTTP)
set -euo pipefail
cd "$(dirname "$0")"
source tools/godot_path.sh
G="$(find_godot)"

NO_EXPORT=false
LAN_MODE=false
for arg in "$@"; do
  case "$arg" in
    --no-export) NO_EXPORT=true ;;
    --lan) LAN_MODE=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

port_in_use() {
  python3 - "$1" <<'PY'
import socket, sys
s = socket.socket()
try:
    s.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(0)
finally:
    s.close()
raise SystemExit(1)
PY
}

for port in 9080 8080; do
  if port_in_use "$port"; then
    echo "Port $port is already in use. Stop the existing service and try again." >&2
    exit 1
  fi
done

if [[ "$NO_EXPORT" != true || ! -f build/web/index.html ]]; then
  ./export_web.sh
fi

if [[ "$LAN_MODE" == true ]]; then
  # Remote HTTP origins cannot use Godot's AudioWorklet driver. LAN mode uses
  # the Dummy driver so keyboard/mouse clients can still play without HTTPS.
  python3 tools/patch_web_lan.py build/web/index.js
fi

cleanup() { kill "${SERVER_PID:-}" "${WEB_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

"$G" --headless --path . -- --server --port=9080 &
SERVER_PID=$!
python3 tools/serve_web.py 8080 build/web &
WEB_PID=$!

wait_for_service() {
  local pid="$1" port="$2" label="$3"
  for _attempt in {1..80}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$label stopped before it was ready." >&2
      return 1
    fi
    if port_in_use "$port"; then
      return 0
    fi
    sleep 0.1
  done
  echo "$label did not become ready on port $port." >&2
  return 1
}

wait_for_service "$SERVER_PID" 9080 "Game server"
wait_for_service "$WEB_PID" 8080 "Web server"

URL="http://localhost:8080/"
echo ""
echo "  Game server : ws://localhost:9080"
echo "  Web client  : $URL"
if [[ "$LAN_MODE" == true ]]; then
  echo "  Other PCs   : http://<THIS-PC-IP>:8080/"
  echo "  LAN mode has keyboard/mouse controls but no browser audio or voice input."
fi
echo "  Open the URL in TWO browser tabs/windows (one per player). Ctrl+C to stop."
echo ""
if command -v open >/dev/null 2>&1; then
  open "${URL}?name=Blue"; sleep 1; open "${URL}?name=Red"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${URL}?name=Blue"; sleep 1; xdg-open "${URL}?name=Red"
fi

# Keep the launcher alive and report if either service unexpectedly exits.
while kill -0 "$SERVER_PID" 2>/dev/null && kill -0 "$WEB_PID" 2>/dev/null; do
  sleep 1
done
echo "A local service stopped unexpectedly; shutting down the other service." >&2
exit 1
