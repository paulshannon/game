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

Open the page in two tabs to see two players. Controls: WASD / arrows, Space to jump (3D). On a touch screen (iPad, phone): drag on the left half to move (floating stick), tap **Jump** bottom-right (3D). The space game (`?game=space`) is an asteroid shooter: turn with left/right, thrust with up, fire with Space or the touch **Fire** button (see [games/space/README.md](games/space/README.md)).

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

## Branches and releases

The repo uses **git-flow**:

| Branch | What it holds | Branch from | Merge into |
|---|---|---|---|
| `main` | released code only; every commit is a tagged release | — | — |
| `develop` | the integration branch (default branch; open PRs here) | `main` | — |
| `feature/<issue>-<slug>` | one issue or change, e.g. `feature/5-touch-controls` | `develop` | `develop` (PR) |
| `release/vX.Y.Z` | getting a release ready: version, changelog, fixes only | `develop` | `main` **and** `develop` |
| `hotfix/vX.Y.Z` | an urgent fix to a released version | `main` | `main` **and** `develop` |

`main` and `develop` are protected: changes arrive by pull request with CI green. CI refuses PRs into `main` from anything but `release/*` and `hotfix/*`. Because `develop` is the default branch, `Fixes #N` closes an issue when its feature merges into `develop`, not when it ships.

**Cutting a release** (example `v0.1.0`):
1. `git switch -c release/v0.1.0 develop`
2. Set `config/version="0.1.0"` in `project.godot` (`tools/version.sh` prints it), and in `CHANGELOG.md` rename **Unreleased** to `[0.1.0] - YYYY-MM-DD`. Run `tools/verify.sh`.
3. Open a PR `release/v0.1.0` → `main`. After CI passes, merge it.
4. Tag **the merge commit on `main`** and push the tag: `git fetch origin && git tag -a v0.1.0 origin/main -m v0.1.0 && git push origin v0.1.0`. Use git rather than GitHub's "Draft a new release" page. That page creates the Release itself, with generated notes and no files; the workflow will adopt it, but the git route is the intended one. `release.yml` rejects a tag that isn't on `main`'s own merge line.
5. Merge `main` back into `develop` (PR) so the version and changelog land there too, and add a fresh **Unreleased** section.

Pushing the tag runs `.github/workflows/release.yml`. It checks that the tag matches `project.godot`, is on `main` and has changelog notes; re-runs the full CI on the tagged commit; then creates a **GitHub Release** with `game-web-vX.Y.Z.zip`, `game-server-linux-x86_64-vX.Y.Z` and `SHA256SUMS`; and publishes that release's web build to **GitHub Pages**. Nothing is published if any step fails. A hotfix is the same with `hotfix/vX.Y.Z` branched from `main`.

**The published page:** `https://<owner>.github.io/<repo>/` is a landing page linking to every game in `Protocol.PORTS` (built by `tools/make_site.sh`). Pages is HTTPS, so the games need a `wss://` game server, and Pages can't host one. Set the repository variable **`GAME_SERVER_URL`** (Settings → Secrets and variables → Actions → Variables), e.g. `wss://game.example.com`, and the links carry `&server=<url>/ws/<game>` to match the `deploy/` Caddy setup. Without it the page loads but explains that no server is configured.

## Deploying

See `deploy/README.md`: one VPS, Caddy for automatic HTTPS and WebSocket TLS, one systemd service per game. CI (`.github/workflows/ci.yml`) runs the full verification and exports on every push.
