#!/usr/bin/env bash
# Install a Kenney asset pack zip into assets/kenney/<name>/ the way CLAUDE.md
# asks: whole pack, original folder structure, License kept, unused duplicate
# model formats removed, then imported and listed in CREDITS.md.
#
# Usage: tools/add_kenney_pack.sh ~/Downloads/kenney_platformer-kit.zip [name]
#   name defaults to the zip name minus "kenney_" (e.g. platformer-kit)
#
# Get packs from https://kenney.nl/assets (CC0). Download in a browser;
# this script works on the zip you already have.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="${1:?usage: $0 <pack.zip> [name]}"
NAME="${2:-$(basename "$ZIP" .zip)}"
NAME="${NAME#kenney_}"; NAME="${NAME#kenney-}"
NAME="$(echo "$NAME" | tr '[:upper:] _' '[:lower:]--')"
DEST="$ROOT/assets/kenney/$NAME"

[[ -f "$ZIP" ]] || { echo "No such file: $ZIP"; exit 1; }
[[ -e "$DEST" ]] && { echo "$DEST already exists — remove it first to reinstall"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unzip -q "$ZIP" -d "$TMP"
# Some zips wrap everything in one top-level folder; unwrap it.
SRC="$TMP"
entries=("$TMP"/*)
if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then SRC="${entries[0]}"; fi

mkdir -p "$DEST"
cp -R "$SRC"/. "$DEST"/

# GLB is the format we use for 3D (same content as FBX, smaller, best importer).
# Drop the duplicate formats so Godot doesn't import every model three times.
removed=()
while IFS= read -r d; do rm -rf "$d"; removed+=("${d#$DEST/}"); done < <(
  find "$DEST" -type d \( -iname 'FBX format' -o -iname 'OBJ format' -o -iname 'DAE format' \) 2>/dev/null)
# Vector sources (.svg/.swf/.ai) and preview images aren't game assets.
find "$DEST" -type f \( -iname '*.swf' -o -iname '*.ai' -o -iname '*.eps' -o -iname '*.url' \) -delete 2>/dev/null || true

license="$(find "$DEST" -maxdepth 2 -iname 'license*' | head -n1)"
[[ -n "$license" ]] || echo "WARNING: no License file found in pack — check the download"

grep -q "^- $NAME " "$ROOT/CREDITS.md" 2>/dev/null || \
  echo "- $NAME — Kenney (kenney.nl), CC0. Added $(date +%Y-%m-%d) from $(basename "$ZIP")" >> "$ROOT/CREDITS.md"

echo "Installed → assets/kenney/$NAME"
[[ ${#removed[@]} -gt 0 ]] && printf '  removed duplicate format: %s\n' "${removed[@]}"
echo "  GLB models:   $(find "$DEST" -iname '*.glb' | wc -l | tr -d ' ')"
echo "  spritesheets: $(find "$DEST" -iname '*.xml' | wc -l | tr -d ' ') (convert with tools/kenney_atlas.sh assets/kenney/$NAME)"
echo "→ importing"
"$ROOT/tools/check.sh" > /dev/null && echo "  import + compile OK"
