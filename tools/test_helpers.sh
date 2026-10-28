#!/usr/bin/env bash
# Shared lifecycle helpers for local launchers. Source from the repository root.
source tools/godot_path.sh
G="$(find_godot)"
TEST_PIDS=()
TEST_LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/campus-arcana-test.XXXXXX")"

test_cleanup() {
  local pid
  if (( ${#TEST_PIDS[@]} == 0 )); then return; fi
  for pid in "${TEST_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
  done
  for pid in "${TEST_PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
}
trap test_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_spawn() {
  local logfile="$1"
  shift
  "$@" > "$TEST_LOG_DIR/$logfile" 2>&1 &
  TEST_LAST_PID=$!
  TEST_PIDS+=("$TEST_LAST_PID")
}

test_fail() {
  echo "ERROR: $*" >&2
  echo "Logs: $TEST_LOG_DIR" >&2
  local logfile
  for logfile in "$TEST_LOG_DIR"/*.log; do
    [[ -f "$logfile" ]] && tail -n 15 "$logfile" >&2
  done
  exit 1
}

test_wait_log() {
  local pid="$1" logfile="$2" pattern="$3"
  local attempt
  for attempt in {1..450}; do
    if grep -qE -- "$pattern" "$TEST_LOG_DIR/$logfile" 2>/dev/null; then return 0; fi
    kill -0 "$pid" 2>/dev/null || test_fail "A test process stopped during startup."
    sleep 0.1
  done
  test_fail "Timed out waiting for the game to start."
}

test_map() {
  case "$1" in
    dining_hall|hg_e) ;;
    *) echo "Unknown map '$1'. Choose dining_hall or hg_e." >&2; exit 2 ;;
  esac
}

test_port() {
  # Auto-pick an unused port from a small range, or validate an explicit port.
  python3 - "$1" "$2" <<'PY'
import socket, sys
requested, start = int(sys.argv[1]), int(sys.argv[2])
if requested < 0 or requested > 65535:
    sys.exit("Port must be between 1 and 65535.")
for port in ([requested] if requested else range(start, start + 20)):
    with socket.socket() as probe:
        try:
            probe.bind(("0.0.0.0", port))
        except OSError:
            continue
        print(port)
        break
else:
    sys.exit("No free port found. Stop another local test or choose another port.")
PY
}

test_server() {
  local port="$1" map="$2"
  test_spawn server.log "$G" --headless --path . -- --server "--port=$port" "--map=$map"
  TEST_SERVER_PID="$TEST_LAST_PID"
  test_wait_log "$TEST_SERVER_PID" server.log "listening on port $port"
}

test_no_errors() {
  # Godot currently returns success but emits a resource warning after native
  # screenshot clients quit. Keep it in logs; it does not invalidate a capture.
  if grep -nE 'SCRIPT ERROR:|^ERROR:|Compile Error:|Parse Error:' "$TEST_LOG_DIR"/*.log \
      | grep -vE 'ERROR: [0-9]+ resources still in use at exit'; then
    test_fail "Godot reported an error."
  fi
  if grep -q 'resources still in use at exit' "$TEST_LOG_DIR"/*.log; then
    echo "Note: Godot emitted a shutdown resource warning; details are in the logs."
  fi
}
