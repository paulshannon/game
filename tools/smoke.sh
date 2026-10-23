#!/usr/bin/env bash
# End-to-end multiplayer test: 1 headless server + N headless bot clients over
# real WebSockets on localhost. Passes when:
#   - every process prints SMOKE_RESULT ... "ok":true and exits 0
#   - no ERROR / SCRIPT ERROR lines appear in any log, apart from the
#     documented benign ones in tools/smoke_allowlist.txt
#
# Usage: tools/smoke.sh [2d|3d|space|all] [seconds=8] [clients=2]
#        SERVER_BIN=build/server/server.x86_64 tools/smoke.sh   # test the export
#        SERVER_IMAGE=game-server:ci tools/smoke.sh   # test the Docker image
#            (deploy/docker/Dockerfile; the container's 9080 is published on
#            127.0.0.1:<the game's Protocol port>, so clients are unchanged)
#        SMOKE_RESTART=1 tools/smoke.sh 2d   # kill + restart the server mid-run;
#            bots must reconnect and play on (each reports "reconnects":1)
# Logs:  .smoke/<game>/{server,client1,...}.log  (restart: .smoke/<game>-restart/)
source "$(dirname "$0")/_godot.sh"
cd "$ROOT"

GAME="${1:-all}"
SECS="${2:-8}"
CLIENTS="${3:-2}"

# SERVER_BIN=build/server/server.x86_64 tests the exported dedicated server
# (the production artifact) instead of running the server from source.
server_cmd=("$GODOT" --headless --path .)
[[ -n "${SERVER_BIN:-}" ]] && server_cmd=("$SERVER_BIN" --headless)

# The port a game listens on (Protocol.PORTS), for publishing the container.
game_port() {
  sed -n "/^const PORTS/,/^}/s/^[[:space:]]*\"$1\":[[:space:]]*\([0-9]*\).*/\1/p" "$ROOT/common/net/protocol.gd"
}

start_server() {  # game seconds log
  if [[ -n "${SERVER_IMAGE:-}" ]]; then
    # Attached `docker run` proxies signals to the container, so the restart
    # test's kill reaches the server the same way systemd/docker stop would.
    ${_TO[@]+"${_TO[@]}"} docker run --rm -e GAME="$1" -p "127.0.0.1:$(game_port "$1"):9080" \
        "$SERVER_IMAGE" --run-seconds="$2" --expect-peers="$CLIENTS" > "$3" 2>&1 &
    return
  fi
  ${_TO[@]+"${_TO[@]}"} "${server_cmd[@]}" -- --server --game="$1" \
      --run-seconds="$2" --expect-peers="$CLIENTS" > "$3" 2>&1 &
}

start_clients() {  # game seconds dir → appends to pids
  for i in $(seq 1 "$CLIENTS"); do
    godot_run --headless --path . -- --client --game="$1" --bot \
        --run-seconds="$2" --expect-peers="$CLIENTS" > "$3/client$i.log" 2>&1 &
    pids+=($!)
  done
}

run_one() {
  local game="$1"
  local dir="$ROOT/.smoke/$game"
  rm -rf "$dir"; mkdir -p "$dir"; touch "$ROOT/.smoke/.gdignore"

  start_server "$game" $((SECS + 4)) "$dir/server.log"
  local spid=$!
  sleep 2   # let the server bind its port
  pids=()
  start_clients "$game" "$SECS" "$dir"

  local fail=0
  for p in "${pids[@]}"; do wait "$p" || fail=1; done
  wait "$spid" || fail=1
  check_logs "$dir" "$game" $fail
}

# Server A runs, then is killed (as a crash or a systemd restart would). The
# bots see the disconnect, retry until server B is up, rejoin, and must play
# on: their SMOKE_RESULT comes from the rebuilt game, so "ok" proves the
# rejoined session works. Server A's log is not checked (it was killed).
run_restart() {
  local game="$1"
  local dir="$ROOT/.smoke/$game-restart"
  rm -rf "$dir"; mkdir -p "$dir"; touch "$ROOT/.smoke/.gdignore"
  local client_secs=$((SECS + 8))

  start_server "$game" 60 "$dir/killed-server.txt"
  local apid=$!
  sleep 2
  pids=()
  start_clients "$game" "$client_secs" "$dir"
  sleep $((SECS / 2 + 1))
  kill "$apid" 2>/dev/null; wait "$apid" 2>/dev/null || true
  sleep 2   # bots notice, reset, and start retrying
  start_server "$game" $((client_secs - SECS / 2 + 2)) "$dir/server.log"
  local bpid=$!

  local fail=0
  for p in "${pids[@]}"; do wait "$p" || fail=1; done
  wait "$bpid" || fail=1
  for log in "$dir"/client*.log; do
    grep -q '"reconnects":1' "$log" || { echo "  ✗ $(basename "$log"): did not reconnect exactly once"; fail=1; }
  done
  check_logs "$dir" "$game (server restart)" $fail
}

check_logs() {  # dir label fail
  local dir="$1" label="$2" fail="$3"
  for log in "$dir"/*.log; do
    grep -q '"ok":true' "$log" || { echo "  ✗ $(basename "$log"): no passing SMOKE_RESULT"; fail=1; }
    local errors
    errors="$(grep -E '^(ERROR|SCRIPT ERROR)' "$log" | grep -vEf <(grep -vE '^(#|$)' "$ROOT/tools/smoke_allowlist.txt") || true)"
    if [[ -n "$errors" ]]; then
      echo "  ✗ $(basename "$log") has errors:"; echo "$errors" | head -8 | sed 's/^/      /'
      fail=1
    fi
  done
  grep -h SMOKE_RESULT "$dir"/*.log | sed 's/^/  /'
  if [[ $fail -eq 0 ]]; then echo "SMOKE $label: PASS"; else echo "SMOKE $label: FAIL (logs in ${dir#$ROOT/}/)"; fi
  return $fail
}

run=run_one
[[ -n "${SMOKE_RESTART:-}" ]] && run=run_restart
status=0
if [[ "$GAME" == "all" ]]; then
  $run 2d || status=1
  $run 3d || status=1
  $run space || status=1
else
  $run "$GAME" || status=1
fi
exit $status
