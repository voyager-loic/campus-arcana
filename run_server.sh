#!/usr/bin/env bash
# Run one dedicated lobby. Players join it; no desktop client is opened.
set -euo pipefail
cd "$(dirname "$0")"
PORT=9080
MAP=dining_hall
PORT_GIVEN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --map)
      [[ $# -ge 2 ]] || { echo "Missing map name." >&2; exit 2; }
      MAP="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: ./run_server.sh [port] [--map dining_hall|hg_e]"
      echo "Starts one lobby only. For a complete two-player test: ./run_local.sh"
      exit 0 ;;
    [0-9]*)
      [[ "$PORT_GIVEN" == false ]] || { echo "Only one port may be specified." >&2; exit 2; }
      PORT="$1"; PORT_GIVEN=true; shift ;;
    *) echo "Unknown option: $1. Use --help." >&2; exit 2 ;;
  esac
done
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "Invalid port '$PORT'. Use a number from 1 to 65535." >&2
  exit 2
fi
case "$MAP" in
  dining_hall|hg_e) ;;
  *) echo "Unknown map '$MAP'. Choose dining_hall or hg_e." >&2; exit 2 ;;
esac
source tools/godot_path.sh
G="$(find_godot)"
echo "Lobby address: ws://127.0.0.1:$PORT (same computer)"
echo "Map: $MAP. The first player to join controls the lobby."
exec "$G" --headless --path . -- --server "--port=$PORT" "--map=$MAP"
