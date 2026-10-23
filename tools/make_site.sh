#!/usr/bin/env bash
# Build the static site that GitHub Pages serves: a landing page linking to
# every game, plus the web export under play/.
#
# Usage: tools/make_site.sh <web build dir> <out dir> [version]
#   GAME_SERVER_URL=wss://game.example.com  → links carry &server=<url>/ws/<game>
#   (the deploy/ Caddy layout). Unset → plain links, and the page says a
#   server is required: Pages is HTTPS, so the game needs a wss:// server,
#   and Pages itself can't host one.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="${1:?usage: $0 <web build dir> <out dir> [version]}"
OUT="${2:?usage: $0 <web build dir> <out dir> [version]}"
VERSION="${3:-$("$ROOT/tools/version.sh")}"
SERVER="${GAME_SERVER_URL:-}"
SERVER="${SERVER%/}"

[[ -f "$WEB/index.html" ]] || { echo "No web build at $WEB (run tools/export.sh web)" >&2; exit 1; }
if [[ -n "$SERVER" && ! "$SERVER" =~ ^wss:// ]]; then
  echo "GAME_SERVER_URL must start with wss:// (Pages is HTTPS), got: $SERVER" >&2; exit 1
fi
mkdir -p "$OUT/play"
cp -R "$WEB"/. "$OUT/play/"
touch "$OUT/.nojekyll"

# Games come from Protocol.PORTS so the list can't drift from the code.
mapfile -t GAMES < <(sed -n '/^const PORTS/,/^}/s/^[[:space:]]*"\([a-z0-9_]*\)":.*/\1/p' "$ROOT/common/net/protocol.gd")
[[ ${#GAMES[@]} -gt 0 ]] || { echo "No games found in Protocol.PORTS" >&2; exit 1; }

links=""
for g in "${GAMES[@]}"; do
  href="play/?game=$g"
  [[ -n "$SERVER" ]] && href="$href&amp;server=$SERVER/ws/$g"
  links+="      <li><a href=\"$href\">$g</a></li>"$'\n'
done
if [[ -n "$SERVER" ]]; then
  note="Games connect to <code>$SERVER</code>."
else
  note="No game server is configured for this site, so games will load but can't connect.
      Open a game with <code>&amp;server=wss://your-server/ws/&lt;game&gt;</code> added to its address,
      or set the <code>GAME_SERVER_URL</code> repository variable and re-run the release."
fi

cat > "$OUT/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Kenney Multiplayer Prototypes v$VERSION</title>
  <style>
    :root { color-scheme: dark; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center;
           background: #080b17; color: #e8ecf6; font: 18px/1.5 system-ui, sans-serif; }
    main { max-width: 34rem; padding: 2rem 1rem; }
    h1 { font-size: 1.6rem; margin: 0 0 .25rem; }
    .version { color: #8b93a8; margin: 0 0 1.5rem; }
    ul { list-style: none; padding: 0; display: grid; gap: .75rem; }
    a { display: block; padding: .9rem 1.1rem; border-radius: .6rem; background: #1ca1db;
        color: #fff; text-decoration: none; font-weight: 600; text-transform: uppercase; letter-spacing: .05em; }
    a:hover, a:focus-visible { background: #3bb6ea; }
    .note { color: #aab2c5; font-size: .95rem; }
    code { color: #e8ecf6; overflow-wrap: anywhere; }
  </style>
</head>
<body>
  <main>
    <h1>Kenney Multiplayer Prototypes</h1>
    <p class="version">v$VERSION</p>
    <ul>
$links    </ul>
    <p class="note">$note</p>
  </main>
</body>
</html>
HTML
echo "Site → $OUT (v$VERSION, games: ${GAMES[*]}, server: ${SERVER:-none})"
