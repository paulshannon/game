# Session notes — how this starter was built

History and reasoning behind the code, for a future Claude Code session (or a human) picking this up. `CLAUDE.md` holds the **rules**. This file holds **why they exist and what was tried**. If the two disagree, `CLAUDE.md` wins, and this file should be corrected.

Built 2026-10-20 in a single conversation between Paul and Claude (Opus 5.5) in the Claude app, with a Linux cloud workspace.

---

## 1. What was asked, in order

1. *"I'm going to want to use kenney.nl assets with the Godot game engine to prototype some multiplayer browser games in both 2D and 3D. Put together best practices in a development guide to use with Claude Code."* → Researched the current state of Godot and Kenney, then wrote a first `CLAUDE.md` as a pure guide, with no code.
2. *"I need this into code."* → Read as: turn the guide into a working starter repo that follows it. That reading was stated up front, and the result is this repo. The guide was then rewritten to describe the real code.
3. Asked whether the deliverable included a session summary. It didn't, so this file was added.

---

## 2. Research behind the version and platform choices

Checked by web search on 2026-10-20. Re-check before relying on any of it after that date.

| Finding | Consequence in the repo | Source |
|---|---|---|
| Godot **4.7** went stable in June 2026; **4.7.1** was the latest stable patch (July 2026). **4.8 Beta 1** shipped 2026-10-15, stable expected Q4 2026. | Pinned `4.7.1-stable` in `.godot-version`. Don't jump to 4.8 mid-prototype; upgrade deliberately (see `CLAUDE.md` §9). | Godot release blog; Godot 4.8 beta coverage (warp2search / linuxcompatible) |
| Godot 4 web export targets **WebGL 2 only**, via the Compatibility renderer. WebGPU (needed for Forward+/Mobile on web) isn't in official Godot. 4.7's web addition was **wasm64** exports, which lift the 4 GB memory ceiling. A third-party WebGPU template fork exists but is beta. | Compatibility renderer from day one. No WebGPU fork. | docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html; Cinevva 4.7 coverage; lxsolutions/studio-foundation releases |
| **Single-threaded web export** has existed since 4.3. Threaded builds need cross-origin isolation (COOP/COEP) headers. | Thread Support off; the build runs on any static host. Confirmed in the export (`GODOT_THREADS_ENABLED = false`). | Same Godot web export doc |
| **Godot 4 C# can't export to web.** | GDScript only. | Same doc |
| **WebSocket** works in native and web exports and plugs into the high-level multiplayer API. It's TCP, so it's reliable but has head-of-line blocking. WebRTC is the documented path for unreliable transport and needs a signaling server. | `WebSocketMultiplayerPeer` now; WebRTC described as a later step. | docs.godotengine.org (4.5) WebSocket and WebRTC pages |
| Kenney: FBX and GLB have **equal features, GLB is smaller**, and GLB is recommended for Godot. 2D packs ship **spritesheet PNG + XML `<TextureAtlas>`**. An AssetLib plugin, *Kenney Spritesheet Importer*, reads that XML. | `add_kenney_pack.sh` keeps GLB and drops FBX/OBJ. `kenney_atlas.gd` converts the XML itself, so there's no plugin dependency. | kenney.nl knowledge base ("importing 3D models into game engines"); Godot AssetLib; Godot forum thread on Kenney spritesheets |
| Several Godot MCP servers exist (Coding-Solo/godot-mcp and others). | Mentioned as optional; the `tools/` scripts are the primary interface. | dev.co listing, PyPI godot-mcp-server, summerengine comparison |

---

## 3. Design decisions and the reasoning

- **Server-authoritative from the first commit.** Retrofitting authority later means rewriting every gameplay script, so even the box demos send only input.
- **Dedicated headless server, never a browser host.** A browser can't listen for connections, so WebSocket topology forces this.
- **Players and arenas built in code, not `.tscn`.** Hand-edited scenes carry `uid://` and `ExtResource` IDs that agents break easily. Code-built nodes keep the synced-property list next to the code that owns it (`Replication.make_synchronizer`).
- **`MultiplayerSpawner` with a custom `spawn_function`.** It lets players be code-built while Godot still handles spawn and despawn replication. The same small `data` dictionary builds the node on every peer.
- **Pure `ArenaSim` with plain state objects.** The server runs it, unit tests call it directly, and future client-side prediction can reuse it unchanged.
- **20 Hz snapshots, 30 Hz input, 100 ms interpolation delay.** 100 ms is two snapshot intervals, so there are almost always two snapshots to blend even with TCP jitter. The constants live in `Protocol`.
- **Interpolation buffer holds the end value instead of extrapolating.** Extrapolation overshoots badly when a player stops.
- **Input actions defined in code (`InputSetup`).** The `[input]` section of `project.godot` is serialized objects and fragile to hand-edit.
- **Own tiny test runner (`TestCase`) instead of GUT/gdUnit4.** It means no third-party dependency to download or version-match. Swap it if the tests outgrow it.
- **One port per game (9080/9081) and a `/ws/<game>` path behind Caddy.** One VPS runs both prototypes. On HTTPS the page's default server URL needs no configuration.
- **`--bind=127.0.0.1` in production.** Only Caddy, on the same host, should reach the plain `ws://` port.
- **Join indices for labels ("P1", "You (P1)").** Peer IDs are large random integers and made the first screenshots unreadable.

---

## 4. Problems found while building, and what was tried

In discovery order. The final fixes are documented as rules in `CLAUDE.md` §7 ("Godot gotchas").

1. **`--check-only` reported "Identifier not found: Net"** for any script using the autoload. Cause: `--check-only` and `-s` don't register autoloads. Fix: the checker (`tools/check_scripts.tscn`) and test runner (`tests/run_tests.tscn`) run as scenes, which do load autoloads. Proved by planting a broken script: the checker caught both the bad call and an untyped `var`.
2. **One smoke client reported `remote_moved:false`.** Cause: a bug in the report, not the netcode. The other client had already left and its player had been despawned by the time the report ran. Fix: latch "own moved" / "remote moved" every frame.
3. **`Net.close()` broke the WebSocket close handshake.** Swapping in the offline peer immediately stops polling the socket. Fix: added `close_gracefully()`, which closes but keeps polling briefly.
4. **Exported server logged `Attempt to disconnect a nonexistent connection ... PlayerSpawner ... tree_exited`.**
   - First guess: setting `spawn_path` after `add_child`. Moving the configuration before `add_child` is still in the code because it's the right order, but it **didn't fix this**.
   - Isolation: the error never appeared with no clients and only after a player had been despawned. stderr markers then placed it **inside `Net.close()`**, and only with the release template.
   - Fix: on quit, free the game first, then `Net.shutdown()`, which closes the socket **without** swapping the peer.
5. **Server logged `Condition "ready_state != STATE_OPEN"` intermittently.** The server sends a snapshot into a socket the client has started closing.
   - **Tried:** a "leave" RPC so the server disconnects the client first. It didn't eliminate the error. It also gave `Net` an RPC, which made problem 4 reappear on `Net`. **Removed.**
   - **Kept:** `tools/smoke_allowlist.txt` with this one line and a written reason. Every closed browser tab causes it in production, and it's an engine log line, not a fault. The rule: any other error in a smoke log is a real failure, and allowlist entries need a reason.
6. **Export output got imported as project assets.** `build/` lives inside the project, so Godot generated `.import` files for the exported icons. Fix: `.gdignore` in `build/` and `.smoke/`. `docs/` has one too, so these screenshots aren't imported.
7. **A probe script hung forever.** A `-s` script that fails to compile never reaches `quit()`, and headless Godot waits indefinitely. Fix: every Godot call in `tools/` goes through a timeout (`GODOT_TIMEOUT`, default 300 s; uses `gtimeout` on macOS if available).
8. **macOS bash 3.2:** an empty array under `set -u` errors. The timeout fallback now uses `${arr[@]+"${arr[@]}"}`.
9. **Visual fixes after the first browser screenshots:**
   - The join button was off-centre, because anchoring centred its top-left corner. It now sits in a `CenterContainer`.
   - 3D labels were tiny; they now use a larger `pixel_size` and an outline.
   - 2D had grey margins; the clear colour is now set.
   - Huge peer IDs in labels were replaced with join indices.
10. **`install_godot.sh` lacked the exec bit** in the first commit. Caught by `git ls-files -s` and amended.
11. **Space gameplay (#16): shots vanished before they were drawn.** Shots and asteroids are drawn from their spawn data at the shared clock's render time. In smoke runs a client's clock was ~2.2 s behind, so the server despawned a shot (0.9 s life) before the client's render time reached its birth.
    - Cause: the client stalls loading art when the first players spawn. The stalled snapshots seed `SnapshotClock`'s offset 2 s too large, and slewing back at 0.1 s/s takes ~20 s. The box games hid this because everything they draw lags together.
    - Fix: `SnapshotClock` jumps when it is more than `SNAP_BEHIND` (0.5 s) behind the best latency seen (a stall only adds larger offsets, so it can't trigger the jump), and the space art is preloaded when the world is built.
12. **Smoke clients leaked `AudioStreamPlaybackOggVorbis` at exit** ("ObjectDB instances leaked", "resources still in use"), so the smoke test failed. `--verbose` showed only the explosion sound leaking: its playbacks were cut off by `max_polyphony`, and short sounds that finish on their own were fine. Calling `stop()` on exit didn't help, because the dummy audio driver never releases a stopped playback. Fix: no sounds when headless.

Also checked: untyped **loop variables** are *not* rejected by the compiler, so `CLAUDE.md` says to type them for checking, not that the build enforces it.

---

## 5. How it was verified (and how to repeat it)

Environment: Linux x86_64, official Godot 4.7.1 binary and export templates from GitHub releases.

| Check | How | Result |
|---|---|---|
| Compile all scripts | `tools/check.sh` | 23/23 |
| Unit tests | `tools/test.sh` | 22 pass |
| Multiplayer, source | `tools/smoke.sh all 8 2`, plus a 3-client run | 2D + 3D pass |
| Multiplayer, exported server | `SERVER_BIN=build/server/server.x86_64 tools/smoke.sh`, repeated 4× | pass, only the allowlisted line |
| Web build in a browser | Playwright + headless Chromium, `--use-angle=swiftshader` (WebGL 2), against the exported server plus a native bot client | joined, moved, saw the other player |
| Production path | Caddy 2.10.2 with the shipped `deploy/Caddyfile` (`caddy validate` passed), adapted to `localhost:8443` + `tls internal`; servers on `--bind=127.0.0.1`; page on HTTPS with no `server=` param | both games connected over `wss://.../ws/<game>` |
| Kenney flow | Synthetic Kenney-format zip: GLB made with Godot's `GLTFDocument`, spritesheet PNG + XML, FBX duplicate, License → `add_kenney_pack.sh` → `kenney_atlas.sh` → `MODEL_PATH`/`SPRITE_PATH` set → probe + smoke | model and sprite loaded; smoke passed |
| Installer | `tools/install_godot.sh` on a clean copy | downloaded, version-checked |
| Fresh unzip of the deliverable | full verify + export + exported smoke; `git status` clean afterwards | pass |

Screenshots from the browser runs are in `docs/screenshots/`. `web-3d-two-players-before-fixes.png` is from before the label fixes in §4.9.

**Not tested:** a real macOS machine, Safari or iOS, real Kenney downloads (kenney.nl wasn't reachable from the build environment), the CI workflow on GitHub itself, and `install_godot.sh --templates` doing a real extraction (its `unzip` command matches the one run manually, but the script found templates already installed and skipped it).

---

## 6. Open threads / sensible next steps

**Future work lives in the GitHub issue tracker, not in this file:** https://github.com/paulshannon/game/issues. This file keeps the history and reasoning; it isn't a to-do list.

What this section used to list was assessed on 2026-10-23 and moved into issues:

| Was here | Now |
|---|---|
| Run `tools/verify.sh` on Paul's machine (macOS) | #13, together with real Safari / iPad testing |
| Push to GitHub to exercise CI | Done: CI has run on every push since the import, PRs included |
| Try a real Kenney pack | Partly done (UI Pack: Sci-fi in #6, no GLBs or XML spritesheets); real 3D/2D packs in #15 |
| First real mechanic | #16 (space) |
| Client-side prediction | #17, deferred until movement feels laggy |

Threads that came up later: first release through `release.yml` (#11), a public `wss://` server and `GAME_SERVER_URL` (#12), checking release builds for the disconnect error on Rejoin (#14), Docker arm64 / `:develop` image (#18).

