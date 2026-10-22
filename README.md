# Kenney Multiplayer Starter (Godot 4.7)

A working starting point for **multiplayer browser game prototypes** in Godot 4.7, built to use [Kenney](https://kenney.nl) assets and to be developed with Claude Code. It contains two playable skeletons — a 2D arena and a 3D arena — that share one server-authoritative networking layer.

- **Browser-first:** single-threaded web export on the Compatibility (WebGL 2) renderer. Works on any static host, Safari included.
- **Server-authoritative:** clients send input; a headless dedicated server simulates and replicates state; clients interpolate.
- **Verified by script:** one command compiles every script, runs unit tests, and runs a real server with bot clients over WebSockets.

`CLAUDE.md` is the development guide (Claude Code reads it automatically). `docs/SESSION_NOTES.md` records how the starter was built: research sources, design reasoning, what was tried and dropped, and how it was verified.

## Quick start

```bash
tools/install_godot.sh --templates   # pinned Godot + export templates into .tools/
tools/verify.sh                      # compile + unit tests + multiplayer smoke test
```

Play locally with native windows (fastest loop):

```bash
tools/run_server.sh 2d               # terminal 1  (or 3d)
tools/run_client.sh 2d               # terminal 2
tools/run_client.sh 2d               # terminal 3 — a second player
tools/run_client.sh 2d "" --bot      # or a bot player
```

Play in the browser:

```bash
tools/export.sh web
tools/run_server.sh 2d               # terminal 1
tools/serve_web.sh                   # terminal 2 → open http://localhost:8000/?game=2d
```

Open the page in two tabs to see two players. Controls: WASD / arrows, Space to jump (3D). On a touch screen (iPad, phone): drag on the left half to move (floating stick), tap **Jump** bottom-right (3D).

Use the editor normally too: `.tools/godot -e --path .` (or your own Godot 4.7.1). To run server + clients from the editor, set *Debug → Customize Run Instances* with `-- --server` for one instance and `-- --client` for the others.

## Adding Kenney art

```bash
tools/add_kenney_pack.sh ~/Downloads/kenney_mini-characters.zip    # → assets/kenney/mini-characters/
tools/kenney_atlas.sh assets/kenney/<2d-pack>                     # 2D only: spritesheet XML → .tres
```

Then set `MODEL_PATH` in `games/box_arena_3d/player_3d.gd` or `SPRITE_PATH` in `games/box_arena_2d/player_2d.gd`. The installer keeps the pack's folder structure and License, removes the duplicate FBX/OBJ folders, imports, and records the pack in `CREDITS.md`.

## Layout

```
main.gd / main.tscn      entry point: reads launch config, loads game, hosts or joins
common/net/              transport (Net autoload), protocol constants, launch config,
                         input relay, replication helper
common/sim/              pure movement rules (ArenaSim) — server-run, unit-tested
common/game/             GameBase: spawning, despawning, smoke-test reporting
client/                  interpolation buffer, input actions, HUD
games/box_arena_2d|3d/   the two prototypes
tests/                   tiny test runner + unit tests
tools/                   every command (install, check, test, smoke, export, serve, Kenney)
deploy/                  Caddy (HTTPS + wss) and systemd for a single VPS
docs/                    SESSION_NOTES.md (build history) + browser test screenshots
```

## What was verified

On Godot 4.7.1 (Linux): all scripts compile with untyped declarations treated as errors; 22 unit tests pass; server + 2–3 bot clients pass the smoke test in 2D and 3D, both from source and as the exported dedicated-server binary. The web export ran in headless Chromium (WebGL 2 via SwiftShader) against the exported server: the join gate, keyboard input, server movement and the other player all worked, including over HTTPS → `wss://` through the shipped Caddy config. A Kenney-format test pack (GLB + spritesheet XML) went through the installer, atlas converter and the `MODEL_PATH`/`SPRITE_PATH` swap. Not tested: a real macOS machine, Safari, and real Kenney downloads (kenney.nl wasn't reachable from the build environment).

## Deploying

See `deploy/README.md`: one VPS, Caddy for automatic HTTPS and WebSocket TLS, one systemd service per game. CI (`.github/workflows/ci.yml`) runs the full verification and exports on every push.
