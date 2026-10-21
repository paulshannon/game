#!/usr/bin/env bash
# Download the Godot version pinned in .godot-version into .tools/ (gitignored),
# so every machine and every Claude Code session runs the same engine.
#
# Usage: tools/install_godot.sh              # editor only (~75 MB)
#        tools/install_godot.sh --templates  # + Web/Linux export templates
#
# Templates come in one ~1.2 GB archive; only the four we use are extracted
# (single-threaded web + linux x86_64, debug and release).
# Supports Linux x86_64/arm64 and macOS (universal).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/.godot-version")"   # 4.7.1-stable
TAG_DIR="${VERSION/-/.}"                                  # 4.7.1.stable
BASE="https://github.com/godotengine/godot/releases/download/$VERSION"
TOOLS="$ROOT/.tools"
mkdir -p "$TOOLS"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  ASSET="Godot_v${VERSION}_linux.x86_64";  KIND=linux ;;
  Linux-aarch64|Linux-arm64) ASSET="Godot_v${VERSION}_linux.arm64"; KIND=linux ;;
  Darwin-*)      ASSET="Godot_v${VERSION}_macos.universal"; KIND=mac ;;
  *) echo "Unsupported platform $(uname -s)-$(uname -m); install Godot $VERSION manually and set GODOT"; exit 1 ;;
esac

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

if [[ -x "$TOOLS/godot" ]] && "$TOOLS/godot" --headless --version 2>/dev/null | grep -q "^$TAG_DIR"; then
  echo "Godot $VERSION already installed at .tools/godot"
else
  echo "→ downloading $ASSET.zip"
  curl -fL --progress-bar -o "$TMP/godot.zip" "$BASE/$ASSET.zip"
  unzip -q "$TMP/godot.zip" -d "$TMP/editor"
  if [[ $KIND == mac ]]; then
    rm -rf "$TOOLS/Godot.app"; mv "$TMP/editor/Godot.app" "$TOOLS/Godot.app"
    ln -sf "Godot.app/Contents/MacOS/Godot" "$TOOLS/godot"
  else
    mv "$TMP/editor/$ASSET" "$TOOLS/godot"; chmod +x "$TOOLS/godot"
  fi
  echo "Installed: $("$TOOLS/godot" --headless --version 2>/dev/null | tail -n1) → .tools/godot"
fi

if [[ "${1:-}" == "--templates" ]]; then
  if [[ $KIND == mac ]]; then TPL="$HOME/Library/Application Support/Godot/export_templates/$TAG_DIR"
  else TPL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TAG_DIR"; fi
  NEED=(version.txt web_nothreads_release.zip web_nothreads_debug.zip linux_release.x86_64 linux_debug.x86_64)
  have=1; for f in "${NEED[@]}"; do [[ -f "$TPL/$f" ]] || have=0; done
  if [[ $have == 1 ]]; then
    echo "Export templates already in $TPL"
  else
    echo "→ downloading export templates (~1.2 GB, extracting only what we use)"
    curl -fL --progress-bar -o "$TMP/templates.tpz" "$BASE/Godot_v${VERSION}_export_templates.tpz"
    mkdir -p "$TPL"
    unzip -q -o -j "$TMP/templates.tpz" $(printf 'templates/%s ' "${NEED[@]}") -d "$TPL"
    echo "Templates → $TPL"
  fi
fi
echo "Done. Tools find .tools/godot automatically; or export GODOT=\"$TOOLS/godot\"."
