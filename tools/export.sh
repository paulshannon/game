#!/usr/bin/env bash
# Export builds using the presets in export_presets.cfg.
# Usage: tools/export.sh [web|server|all] [release|debug]
# Needs export templates for the pinned version (tools/install_godot.sh --templates).
source "$(dirname "$0")/_godot.sh"
cd "$ROOT"
WHAT="${1:-all}"
MODE="${2:-release}"

# build/ sits inside the project folder; .gdignore stops Godot from importing
# the exported icons/pck as if they were project assets.
mkdir -p build && touch build/.gdignore

godot_run --headless --path . --import > /dev/null 2>&1 || true

export_preset() {
  local preset="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  echo "→ $preset → $out"
  local log; log="$(godot_run --headless --path . --export-"$MODE" "$preset" "$out" 2>&1)" || true
  if [[ ! -s "$out" ]] || echo "$log" | grep -qE '^ERROR'; then
    echo "$log" | grep -E 'ERROR|error' | head -20
    echo "EXPORT FAILED: $preset"; return 1
  fi
}

case "$WHAT" in
  web)    export_preset "Web" build/web/index.html ;;
  server) export_preset "Linux Server" build/server/server.x86_64 ;;
  all)    export_preset "Web" build/web/index.html && export_preset "Linux Server" build/server/server.x86_64 ;;
  *) echo "usage: $0 [web|server|all] [release|debug]"; exit 2 ;;
esac
echo "EXPORT OK"
