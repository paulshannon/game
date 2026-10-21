#!/usr/bin/env bash
# Sourced by the other tools/*.sh scripts. Resolves the Godot binary and
# checks it matches .godot-version, so every script runs the pinned engine.
#
# Resolution order:
#   1. $GODOT, if set
#   2. .tools/godot (installed by tools/install_godot.sh)
#   3. `godot` on PATH
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED="$(tr -d '[:space:]' < "$ROOT/.godot-version")"   # e.g. 4.7.1-stable

if [[ -n "${GODOT:-}" ]]; then
  :
elif [[ -x "$ROOT/.tools/godot" ]]; then
  GODOT="$ROOT/.tools/godot"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
else
  echo "Godot not found. Run tools/install_godot.sh or set GODOT=/path/to/godot" >&2
  exit 127
fi

# `--version` prints e.g. "4.7.1.stable.official.a13da4feb"
_actual="$("$GODOT" --headless --version 2>/dev/null | tail -n1)"
_want="${PINNED/-/.}"   # 4.7.1-stable -> 4.7.1.stable
if [[ "$_actual" != "$_want"* ]]; then
  echo "WARNING: Godot is $_actual but .godot-version pins $PINNED" >&2
fi

export GODOT ROOT PINNED

# Every Godot call goes through a timeout. A script that fails to compile
# inside `-s` mode never reaches quit(), and a headless Godot then waits
# forever — an agent running these tools would hang with no output.
GODOT_TIMEOUT="${GODOT_TIMEOUT:-300}"
if command -v timeout >/dev/null 2>&1; then _TO=(timeout "$GODOT_TIMEOUT")
elif command -v gtimeout >/dev/null 2>&1; then _TO=(gtimeout "$GODOT_TIMEOUT")   # macOS + coreutils
else _TO=(); fi

godot_run() { ${_TO[@]+"${_TO[@]}"} "$GODOT" "$@"; }   # bash 3.2-safe empty-array expansion

# Quiet wrapper: drop the banner and blank lines, keep everything else.
godot_q() {
  godot_run "$@" 2>&1 | grep -vE '^(Godot Engine v|$)' || true
}
