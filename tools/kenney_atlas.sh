#!/usr/bin/env bash
# Turn Kenney spritesheet XML into AtlasTexture .tres files (see kenney_atlas.gd).
# Usage: tools/kenney_atlas.sh res://assets/kenney/<pack>/Spritesheet/<sheet>.xml [...]
#        tools/kenney_atlas.sh assets/kenney/<pack>     # every *.xml in the pack
source "$(dirname "$0")/_godot.sh"
cd "$ROOT"

paths=()
for a in "$@"; do
  if [[ -d "$a" ]]; then
    while IFS= read -r f; do paths+=("res://${f#./}"); done < <(find "$a" -name '*.xml' -not -path '*/_atlas/*')
  else
    paths+=("$([[ "$a" == res://* ]] && echo "$a" || echo "res://${a#./}")")
  fi
done
[[ ${#paths[@]} -gt 0 ]] || { echo "usage: $0 <sheet.xml | pack dir> ..."; exit 2; }

godot_run --headless --path . --import > /dev/null 2>&1 || true   # make sure sheet PNGs are imported
godot_q --headless --path . -s res://tools/kenney_atlas.gd -- "${paths[@]}"
godot_run --headless --path . --import > /dev/null 2>&1 || true   # register the new .tres files
