#!/usr/bin/env bash
# Run the dedicated authoritative game server (headless).
#   ./run_server.sh [port]
set -euo pipefail
cd "$(dirname "$0")"
source tools/godot_path.sh
G="$(find_godot)"
PORT="${1:-9080}"
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "Invalid port '$PORT'. Use a number from 1 to 65535." >&2
  exit 2
fi
exec "$G" --headless --path . -- --server --port="$PORT"
