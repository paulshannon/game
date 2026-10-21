#!/usr/bin/env bash
# Run a native windowed client (fastest iteration loop — no export needed).
# Usage: tools/run_client.sh [2d|3d] [ws://host:port] [--bot]
source "$(dirname "$0")/_godot.sh"
cd "$ROOT"
GAME="${1:-2d}"
ARGS=(--client --game="$GAME")
[[ -n "${2:-}" ]] && ARGS+=(--url="$2")
[[ "${3:-}" == "--bot" ]] && ARGS+=(--bot)
exec "$GODOT" --path . -- "${ARGS[@]}"
