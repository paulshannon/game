#!/usr/bin/env bash
# Import assets, then compile every script with autoloads registered.
# Exit 0 = all scripts compile.
source "$(dirname "$0")/_godot.sh"
cd "$ROOT"

echo "→ import"
godot_run --headless --path . --import > /dev/null 2>&1 || true
echo "→ compile"
out="$(godot_q --headless --path . res://tools/check_scripts.tscn)"
echo "$out" | grep -E 'CHECK_|SCRIPT ERROR|ERROR|res://' || true
echo "$out" | grep -q 'CHECK_RESULT ok=true'
