#!/usr/bin/env bash
# Run a headless game server from source. Ctrl-C to stop.
# Usage: tools/run_server.sh [space|2d|3d] [port]   (default space)
source "$(dirname "$0")/_godot.sh"
cd "$ROOT"
GAME="${1:-space}"
ARGS=(--server --game="$GAME")
[[ -n "${2:-}" ]] && ARGS+=(--port="$2")
exec "$GODOT" --headless --path . -- "${ARGS[@]}"
