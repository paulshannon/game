#!/usr/bin/env bash
# Serve the web export locally. The build is single-threaded, so no
# COOP/COEP headers are needed and plain http.server is enough.
#
# Then open:  http://localhost:8000/?game=2d   (or ?game=3d)
# with a server running:  tools/run_server.sh 2d
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-8000}"
[[ -f "$ROOT/build/web/index.html" ]] || { echo "No web build. Run tools/export.sh web"; exit 1; }
echo "Serving build/web on http://localhost:$PORT/?game=2d"
exec python3 -m http.server "$PORT" -d "$ROOT/build/web"
