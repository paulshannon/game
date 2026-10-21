#!/usr/bin/env bash
# End-to-end multiplayer test: 1 headless server + N headless bot clients over
# real WebSockets on localhost. Passes when:
#   - every process prints SMOKE_RESULT ... "ok":true and exits 0
#   - no ERROR / SCRIPT ERROR lines appear in any log, apart from the
#     documented benign ones in tools/smoke_allowlist.txt
#
# Usage: tools/smoke.sh [2d|3d|all] [seconds=8] [clients=2]
#        SERVER_BIN=build/server/server.x86_64 tools/smoke.sh   # test the export
# Logs:  .smoke/<game>/{server,client1,...}.log
source "$(dirname "$0")/_godot.sh"
cd "$ROOT"

GAME="${1:-all}"
SECS="${2:-8}"
CLIENTS="${3:-2}"

run_one() {
  local game="$1"
  local dir="$ROOT/.smoke/$game"
  rm -rf "$dir"; mkdir -p "$dir"; touch "$ROOT/.smoke/.gdignore"
  local server_secs=$((SECS + 4))

  # SERVER_BIN=build/server/server.x86_64 tests the exported dedicated server
  # (the production artifact) instead of running the server from source.
  local server_cmd=("$GODOT" --headless --path .)
  [[ -n "${SERVER_BIN:-}" ]] && server_cmd=("$SERVER_BIN" --headless)
  ${_TO[@]+"${_TO[@]}"} "${server_cmd[@]}" -- --server --game="$game" \
      --run-seconds="$server_secs" --expect-peers="$CLIENTS" > "$dir/server.log" 2>&1 &
  local spid=$!
  sleep 2   # let the server bind its port

  local pids=()
  for i in $(seq 1 "$CLIENTS"); do
    godot_run --headless --path . -- --client --game="$game" --bot \
        --run-seconds="$SECS" --expect-peers="$CLIENTS" > "$dir/client$i.log" 2>&1 &
    pids+=($!)
  done

  local fail=0
  for p in "${pids[@]}"; do wait "$p" || fail=1; done
  wait "$spid" || fail=1

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
  if [[ $fail -eq 0 ]]; then echo "SMOKE $game: PASS"; else echo "SMOKE $game: FAIL (logs in .smoke/$game/)"; fi
  return $fail
}

status=0
if [[ "$GAME" == "all" ]]; then
  run_one 2d || status=1
  run_one 3d || status=1
else
  run_one "$GAME" || status=1
fi
exit $status
