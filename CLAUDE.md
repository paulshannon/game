# CLAUDE.md — Godot + Kenney Multiplayer Browser Prototypes

How to work in this repo: engine version, networking design, Kenney asset handling, and the commands that prove a change works. Each rule says *why*, so edge cases can be reasoned out rather than guessed.

**Before saying any task is done, run `tools/verify.sh` and see `VERIFY: PASS`.**

For the history behind these rules (research sources, what was tried and dropped, how it was verified) read `docs/SESSION_NOTES.md`.

---

## 1. Stack at a glance

| Area | Choice | Why |
|---|---|---|
| Engine | **Godot 4.7.1 stable**, pinned in `.godot-version` | Don't mix versions; `.tscn`/`.import` formats and APIs shift between minors. `tools/install_godot.sh` installs exactly this version into `.tools/`. |
| Language | **GDScript only, statically typed** | Godot 4 C# can't export to the web. Untyped declarations are compile *errors* here (`project.godot`), so mistakes surface in `tools/check.sh` instead of at runtime. |
| Renderer | **Compatibility** | Web export targets WebGL 2 only; Forward+/Mobile need WebGPU, which official Godot doesn't ship for web. Developing in another renderer means the web build looks different. |
| Web build | **Single-threaded** (Thread Support off) | Threaded builds need COOP/COEP headers that many hosts don't send. Single-threaded runs everywhere, Safari/iOS included. |
| Transport | **`WebSocketMultiplayerPeer`** | ENet (UDP) isn't available in browsers. WebSocket works in native and web builds and plugs into the high-level multiplayer API. |
| Topology | **Headless dedicated server** + clients | A browser can't listen for connections, so a browser can never host. |
| Assets | Kenney.nl (CC0) | Consistent style, no attribution required (credit anyway). |

---

## 2. Repo layout

```
main.gd / main.tscn        entry point for every build: LaunchConfig → game → host or join
project.godot              Compatibility renderer, Net autoload, untyped = error
.godot-version             4.7.1-stable — tools read this
export_presets.cfg         "Web" (single-threaded) + "Linux Server" (dedicated_server)
common/
  net/                     Net autoload, Protocol constants, LaunchConfig, InputRelay,
                           BotInput, Replication (synchronizer builder)
  sim/arena_sim.gd         pure movement rules — no nodes; server-run, unit-tested
  game/game_base.gd        spawner, peer join/leave, smoke reporting — base for every game
  game/player_net.gd       PlayerNet: relay + synchronizer + interpolation every player uses
  game/player_slots.gd     PlayerSlots: reusable seats (match-full check, spawn index)
client/                    SnapshotBuffer (interpolation), InputSetup (actions), Hud
games/<name>/              one folder per prototype + README.md (core loop, players, packs)
assets/kenney/<pack>/      whole packs, original structure, License kept
assets/own/                anything we made or modified
tests/                     run_tests.tscn + TestCase + ErrorCapture + unit/test_*.gd;
                           fixtures/ = runner self-check cases; keep them out of unit/ (they fail on purpose)
tools/                     every command (see §7) — run these, don't improvise
deploy/                    Caddyfile (HTTPS + wss), systemd unit, deploy README
docs/                      SESSION_NOTES.md + screenshots (has .gdignore; not imported or exported)
build/, .smoke/, .tools/   gitignored output; build/ and .smoke/ get a .gdignore
```

**Commit `*.import` files** (they hold import settings); never commit `.godot/`.

The `common/sim` vs node-script split is the most important structural rule. Game rules in `common/sim` take plain state objects, so the server runs them, tests call them directly, and client-side prediction can later reuse the exact same code. Anything visual is built only when `not config.is_server`.

---

## 3. Kenney assets

### Installing a pack
```bash
tools/add_kenney_pack.sh ~/Downloads/kenney_<pack>.zip [name]
```
It copies the **whole pack** into `assets/kenney/<name>/` keeping its structure (Kenney GLBs reference shared textures like `Textures/colormap.png` by relative path, so moving a model away from its folder silently breaks materials), keeps the License, deletes the duplicate `FBX format`/`OBJ format`/`DAE format` folders (GLB is the same content, smaller, and Godot's best importer), imports, and appends to `CREDITS.md`. Kenney downloads happen in a browser; the script works on the zip.

### 2D spritesheets
```bash
tools/kenney_atlas.sh assets/kenney/<pack>        # every *.xml in the pack
```
Turns `<TextureAtlas>`/`<SubTexture>` XML into one `AtlasTexture` `.tres` per sprite under `<sheet>_atlas/`. Those files are derived data; re-running overwrites them, and the Kenney XML stays the source of truth.
- Tilemaps: use `tilemap_packed.png` (no padding) for `TileSet` atlases.
- Pixel-art packs: set Project Settings → Rendering → Textures → Default Texture Filter = **Nearest**.

### Using art
Players are built in code, so swapping art is one constant:
- 3D: `BoxPlayer3D.MODEL_PATH` (+ `MODEL_SCALE`) → a `.glb`
- 2D: `BoxPlayer2D.SPRITE_PATH` → a texture or generated `.tres`

The model/sprite is a child of `Body` and is **purely visual**: collision and movement stay in `ArenaSim`. For props and levels, wrap each model in our own scene (our root + script + collision, Kenney model instanced untouched); never edit imported Kenney files, because reimport regenerates them.

### Collision
Kenney models carry no `-col` hints. In order of preference: primitive shapes in our wrapper (cheapest, most stable for networking) → convex per-mesh physics on import for dynamic props → trimesh only for static level geometry.

### Animation
Kenney character GLBs include animations. Drive them from an `AnimationTree` on the client from replicated velocity/state. Animation is cosmetic and never sent over the network.

---

## 4. Multiplayer architecture

### Core rule: the server is authoritative
Clients send **input**. The server simulates and replicates **state**. Clients render state. Never let a client tell the server its position, score or hit result, even in a prototype — retrofitting authority means rewriting every gameplay script.

### How a frame flows (read these files in order)
1. `client/input/input_setup.gd` — actions defined in code (the `[input]` section of `project.godot` is serialized objects; easy to corrupt by hand).
2. `common/net/input_relay.gd` — on the owning client, sends `submit_input(move, jump, seq)` to the server at `Protocol.INPUT_HZ`. On the server, validates sender == owner, drops stale `seq`, sanitizes. Input older than `Protocol.INPUT_TIMEOUT` (250 ms) counts as released, so a backgrounded tab or stalled network can't hold a key down forever.
3. `games/*/player_*.gd` `_physics_process` (server only) — `ArenaSim.step_*` → writes `net_time` (server clock) + `net_position` / `net_rotation`.
4. `common/net/replication.gd` — a `MultiplayerSynchronizer` sends those at `Protocol.SNAPSHOT_HZ` (20 Hz). Authority stays with the server.
5. Player property setters (client) push each snapshot into a `SnapshotBuffer` **stamped with `net_time`, not arrival time**, and `SnapshotClock` maps server time onto the local clock. `_process` draws at server time `now - latency - Protocol.INTERP_DELAY` (100 ms ≈ 2 snapshots). Stamping by arrival time would squash a burst of snapshots that queued up behind a TCP stall into ~0 s and the player would teleport. `net_time` must stay **first** in the synchronizer's property list: properties are applied in list order, so it's set before the values it stamps. Stalls up to `INTERP_DELAY − snapshot interval − latency` (~20–50 ms) are invisible; longer ones pause, then catch up by the excess.

### Spawning
`GameBase` owns a `MultiplayerSpawner` with a **custom `spawn_function`**: the server calls `spawner.spawn(data)`, and the same function runs on every peer with the same data, building the player in code. Players are named by peer id so node paths — and therefore RPCs — match everywhere. Removing the node on the server is enough to despawn on clients. Spawn data must stay small primitives.

### RPC rules
- Every `any_peer` RPC checks `multiplayer.get_remote_sender_id()` and sanitizes every argument (`ArenaSim.sanitize_move` rejects NaN/∞ and clamps length).
- Annotate every RPC fully: `@rpc("any_peer", "call_remote", "unreliable_ordered", 0)`.
- **WebSocket is TCP**, so `unreliable*` behaves as reliable-ordered and one late packet delays the ones behind it. Keep the annotations correct anyway (they become real on WebRTC) and design for 100–200 ms hitches: interpolate, never snap.

### Player plumbing
`common/game/player_net.gd` (`PlayerNet`) holds what every player shares: spawn data (peer id, slot, colour), the `InputRelay`, the synchronizer, and client-side buffering and sampling on the server timeline. A player script declares the synced properties (the synchronizer reads them off the node), forwards their setters to `PlayerNet`, and keeps only its sim step and visuals. A new game's player should do the same; don't copy the plumbing.

### Adding a synced property
Add it to the property list passed to `Replication.make_synchronizer(...)` (`PlayerNet.SYNCED` for the shared position/rotation ones). Use the second list (`on_change_props`) for values that rarely change (health, score, team).

### 2D vs 3D
Same network layer. Sync `Quaternion` for 3D rotation (slerp takes the short way; Euler angles flip), and angles as `float` with `SnapshotBuffer.new(true)` in 2D.

### Client-side prediction (not implemented yet)
Add only when local movement feels laggy: run `ArenaSim.step_*` locally on input, keep unacknowledged inputs by `seq`, and when a snapshot arrives with the server's last processed `seq`, rewind to it and replay the rest. `InputRelay.last_seq` is already tracked server-side for this.

### When to move to WebRTC
For true unreliable transport (fast shooters) or peer-to-peer. Needs a WebSocket signaling server plus STUN/TURN. Start from Godot's `networking/webrtc_signaling` demo. Not before the WebSocket version is shown to be the bottleneck.

---

## 5. Web export specifics

- Presets live in `export_presets.cfg`: **Web** (thread support off, desktop + mobile VRAM compression) and **Linux Server** (`dedicated_server=true`, strips visuals, embedded pck). Tests, tools and deploy files are excluded from exports.
- Web clients wait for a **click to join**: browsers only allow audio after a user gesture.
- The page picks its server from the URL (`LaunchConfig.from_web_location`): `?game=2d|3d`, optional `&server=wss://...`. On HTTPS the default is `wss://<same host>/ws/<game>` — what `deploy/Caddyfile` serves. On plain HTTP (local dev) it's `ws://<hostname>:<game port>`.
- **HTTPS pages can only open `wss://`**; the Godot server speaks `ws://`, so production terminates TLS in Caddy and runs servers with `--bind=127.0.0.1`.
- Compatibility renderer budget: one directional light, no SDFGI/volumetric fog/SSR, `MultiMeshInstance3D` for repeated props, low-poly Kenney kits.
- Test in Chrome **and** Safari before calling a web change done; Safari usually breaks first.

---

## 6. Coding conventions

- Static types everywhere. `var x = expr`, untyped parameters and missing return types fail the build; `var x := expr` (inferred) is fine. Loop variables aren't enforced by the compiler, but type them anyway (`for p: Node in ...`) so the body is type-checked.
- `class_name` for reusable types. The only autoload is `Net`; add another only for a true singleton.
- Constants that client and server must agree on go in `common/net/protocol.gd`.
- Gameplay in `_physics_process` (fixed 60 Hz tick); visuals in `_process`.
- Signals for "something happened"; direct calls for "do this".
- Keep files under ~300 lines; split by responsibility.

---

## 7. How Claude Code should work in this repo

### Commands — use these, they wrap the Godot quirks below
| Command | Does |
|---|---|
| `tools/install_godot.sh [--templates]` | pinned Godot (+ Web/Linux templates) into `.tools/` |
| `tools/check.sh` | import, then compile **every** `.gd` with autoloads loaded |
| `tools/test.sh` | unit tests in `tests/unit/` |
| `tools/smoke.sh [2d\|3d\|all] [secs] [clients]` | headless server + N bot clients over real WebSockets; logs in `.smoke/` |
| `SMOKE_RESTART=1 tools/smoke.sh 2d` | kills and restarts the server mid-run; bots must rejoin and play on |
| `tools/verify.sh` | check → test → smoke 2D+3D → restart smoke 2D. **Definition of done.** |
| `tools/export.sh [web\|server\|all]` | builds into `build/` |
| `SERVER_BIN=build/server/server.x86_64 tools/smoke.sh` | smoke-test the exported server (what production runs) |
| `tools/run_server.sh 2d` / `tools/run_client.sh 2d [url] [--bot]` | manual play |
| `tools/serve_web.sh` | serve `build/web` on :8000 |
| `tools/add_kenney_pack.sh`, `tools/kenney_atlas.sh` | Kenney import (§3) |

Tools find Godot via `$GODOT`, then `.tools/godot`, then `godot` on PATH, and warn if it doesn't match `.godot-version`. Every Godot call has a timeout (`GODOT_TIMEOUT`, default 300 s).

### Godot gotchas this repo already hit — don't rediscover them
- **`godot --check-only` and `-s script.gd` don't load autoloads.** Any script touching `Net` reports "Identifier not found" there. That's why the checker and test runner are *scenes* (`tools/check_scripts.tscn`, `tests/run_tests.tscn`). New tooling that needs project classes must be a scene too.
- **A `-s` script that fails to compile never calls `quit()`, and headless Godot then hangs forever.** Always run Godot through the `tools/` wrappers (they time out).
- **Clients must add the game scene before connecting.** The server replicates spawns the instant a peer connects; a `MultiplayerSpawner` that isn't in the client's tree yet drops them. `main.gd` does this.
- **Configure `MultiplayerSpawner` (`spawn_path`, `spawn_function`) before `add_child`.**
- **With no peer connected, `multiplayer.is_server()` returns true** (offline peer). Decide roles from `LaunchConfig.is_server` and gate client logic with `Net.is_online()`.
- **Swapping `multiplayer_peer` after nodes have used RPC/replication makes 4.7 release builds log "Attempt to disconnect a nonexistent connection".** On quit, free the game first, then `Net.close_socket()` (closes without swapping). When the connection drops or fails, `Net` only emits the signal and leaves the dead peer in place; `main.gd` frees the game, waits a frame, calls `Net.close()`, adds a fresh game, then offers Rejoin (bots retry every `Protocol.REJOIN_DELAY`). Debug builds don't print this error, so the smoke test can't catch a wrong order — keep the order.
- **Server logs `ready_state != STATE_OPEN` when it sends into a socket a client is closing.** Every closed browser tab does this; it's the one entry in `tools/smoke_allowlist.txt`. Anything else in a smoke log is a real failure. Add allowlist entries only with a written reason.

### Editing scenes and resources
- Prefer building nodes in code (as the players and arenas do). For `.tscn`/`.tres`, make small edits; when adding an `[ext_resource]`, give it a unique `id` and let Godot add the `uid` on the next import rather than inventing one.
- Never edit `.import` files or anything in `.godot/`.
- After adding assets or scenes, run `tools/check.sh` (it imports first).

### Testing
- Unit tests: `tests/unit/test_<thing>.gd`, `extends TestCase`, methods named `test_*`, using `assert_true/false/eq/near`. Test `common/sim`, `client/net` and parsing directly — no scene tree needed.
- A test also fails if any engine or script error is logged while it runs (`push_error`, null deref, bad cast), including after an `await` and in deferred work it queued. Errors logged outside a test (loading a file) fail the run too. A runtime error aborts the method without failing an assert, so the runner captures errors with a `Logger` (`tests/error_capture.gd`).
- Testing a path that *should* log an error: call `expect_error("fragment")` first. Each call consumes one matching error; an unmet expectation fails the test.
- Every run starts with a self-check against `tests/fixtures/` proving each failure mode is still caught; the `SCRIPT ERROR`/`ERROR` lines it prints are expected. A test method that awaits forever hangs until `GODOT_TIMEOUT`.
- Multiplayer: the smoke test is the integration test. Bots (`--bot`) drive real input through the full loop; each process prints `SMOKE_RESULT ... {"ok":true}`. The server checks every player moved; each client checks it saw its own and a remote player move. When you add a mechanic, extend `GameBase.smoke_report()` (or the game's override) so the smoke test proves the mechanic works over the network.
- If the tests outgrow `TestCase`, add GUT or gdUnit4 under `addons/` and port them.

### Workflow for a new prototype
1. Copy a `games/box_arena_*` folder, rename classes, add a branch in `main.gd::_make_game` and a port in `Protocol.PORTS`. Write the game's `README.md` (core loop, players, 2D/3D, Kenney packs).
2. Get the core mechanic working with boxes, server-side, with unit tests for the rules in `common/sim` (or a game-specific sim file).
3. Extend the smoke report for the mechanic; `tools/verify.sh` green.
4. Import Kenney packs and swap the art.
5. `tools/export.sh web`, test in two browser tabs plus one phone. Restart the server once while connected: the page must show Rejoin and work after it.
6. Only then: polish, prediction, lobbies.

### Optional: Godot MCP server
An MCP server (e.g. `Coding-Solo/godot-mcp`) can launch the editor and read debug output. The `tools/` scripts cover what's needed here and are easier to reason about. If you add one, scope it to this project and don't enable arbitrary script execution by default.

---

## 8. Deployment

See `deploy/README.md`. Short version: static web build behind Caddy (automatic HTTPS), one systemd service per game (`kenney-mp@2d`, `kenney-mp@3d`) bound to 127.0.0.1, Caddy proxying `/ws/<game>` as `wss://`. Smoke-test the exported server binary before shipping it. CI (`.github/workflows/ci.yml`) runs verify + export + exported-server smoke on every push.

---

## 9. Things Claude should NOT do

- Switch renderer away from Compatibility, enable web Thread Support, or add C#.
- Trust client-sent positions, damage or scores; add an `any_peer` RPC without sender validation.
- Edit Kenney source files or move them out of their pack folders.
- Hand-generate `uid://` values or edit `.godot/` / `.import` files.
- Run Godot directly in loops or scripts without a timeout — use `tools/`.
- Add entries to `tools/smoke_allowlist.txt` to make a failure go away.
- Upgrade Godot without being asked (if asked: change `.godot-version`, reinstall, re-export templates, run `tools/verify.sh` and the exported-server smoke).
- Add a networking library or backend service before the built-in WebSocket path is shown to be insufficient.
