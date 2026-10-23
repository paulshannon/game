#!/usr/bin/env bash
# Print the CHANGELOG.md section for one version (without its heading).
# Fails if the section is missing or empty, so a release can't go out
# without notes.
# Usage: tools/release_notes.sh 0.1.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="${1:?usage: $0 <X.Y.Z>}"
notes="$(awk -v v="$V" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^## \[/      { exit }
  found                  { print }
' "$ROOT/CHANGELOG.md" | sed -e '/./,$!d')"
[[ -n "${notes//[[:space:]]/}" ]] || { echo "CHANGELOG.md has no notes for [$V]" >&2; exit 1; }
echo "$notes"
