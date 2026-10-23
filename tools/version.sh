#!/usr/bin/env bash
# Print the project version (application/config/version in project.godot).
# It is the single source of truth: release tags must be "v<this>".
# Usage: tools/version.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
v="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$ROOT/project.godot")"
[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "No X.Y.Z config/version in project.godot (got '$v')" >&2; exit 1; }
echo "$v"
