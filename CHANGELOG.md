# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

Each release's section becomes the notes of its GitHub Release (`tools/release_notes.sh`). On a `release/vX.Y.Z` branch, rename **Unreleased** to `[X.Y.Z] - YYYY-MM-DD` and set the same version in `project.godot` (`application/config/version`).

## [Unreleased]

### Added
- **Space: each hull has its own jets**: flames and RCS nozzles placed on each ship's art (twin wing engines on the Falcon, outboard on the Comet, a big central flame plus two small on the Hornet, twin rear jets and prong-tip nozzles on the Gunship).
- **Space: strafe**: Q / E (LB / RB or the right stick) slide your ship sideways without turning, at 60% of its thrust, with side thrusters drawn. Bots weave in dogfights. The input protocol gains a `strafe` axis (`submit_input(move, jump, fire, strafe, seq)`).
- **Space: teams, PvP and radar** (#35): colours are teams (auto joins the smallest); shots hit ships of other teams (200 points a kill, shields and spawn protection still count, no friendly fire); bots attack enemy ships near them; the scoreboard groups players by team with totals; a radar top-centre shows ships around you (and the way to far ones) and nearby rocks.
- **Server-flown bots**: the first person into an empty match picks how many bots (0–7) on the space menu's **Bots** row. The server flies them itself (`ServerBots`: no client, no socket), with a random ship and colour; they give up seats to people and leave with the last one. Works for any game (`GameBase._make_server_bot`); only space has the menu row.
- **Back to select with Esc**: Esc (Start on a controller, a **Menu** button top-left on touch; remappable) despawns your player and shows the menu again without leaving the match. In space, pick another ship or colour and Play: same seat, same score. Games without a menu show their join button. Bots do it once per smoke run, and each client checks it spawned again.
- **Space: pick your ship and colour** (#31): Falcon (all-rounder), Comet (fastest), Hornet (tightest turns) or Gunship (fastest guns), in blue, green, orange, red or auto (your seat's colour), chosen on the menu before Play and remembered. Generic piece for other games: a client sends `GameBase.join_choice` (a small Dictionary) when it connects, and the server spawns its player once that arrives, with the game's sanitized version in the spawn data.
- **Space: first real gameplay** (#16): co-op asteroid shooting with momentum ships, asteroids that split, pickups (rapid fire, shield, star) and per-player score, all server-authoritative. Uses Kenney's Space Shooter Redux + Extension art and Sci-fi Sounds + Digital Audio. The smoke test proves that shots, hits and scores work over the network.
- `fire` input action (Space) and a touch **Fire** button. Games choose their action with `GameBase.action_button()` (which replaces `uses_jump()`); only that button is sent, and a key still held from the menu's Play button is ignored until released.
- **Space: RCS thrusters** (#24): braking fires puffs forward from the nose, and turning fires a nose and a wingtip thruster on opposite sides, drawn in step with the ship like the main flame.
- **Space: Controls settings page** (#26): remap every action to two keys and two controller inputs from the main menu, saved in the browser (or `user://`) and restored at startup. The controls hint is no longer shown on the play screen. Generic pieces for other games' menus: `ControlsEditor`, `InputBindings`, `GameBase.control_names()`.
- Controller support: left stick and D-pad move, A (and RT for fire) presses the game's action button, on any connected controller.
- `StateTimeline`: discrete replicated state (flags, counters) played back on the server timeline, in step with interpolated positions.

### Changed
- **Space: infinite map** (#29): no more edges. The camera follows your ship over a parallax star field; the server keeps rocks coming around every ship and drops the ones left far behind. Ships respawn where they were destroyed, and late joiners spawn next to a ship already playing.
- **Space is the default game**: a page with no `?game=`, a client or server with no `--game`, `tools/run_server.sh` / `run_client.sh` without an argument, and the Docker image without `GAME` all start space (`Protocol.DEFAULT_GAME`). The box arenas stay at `?game=2d` / `?game=3d`.

### Fixed
- The exported (release) space server no longer logs "Attempt to disconnect a nonexistent connection" for each asteroid, shot and pickup still alive when it quits, which failed CI's exported-server smoke test. Spawned nodes are now freed before their spawner.
- `SnapshotClock`'s latency window is 2 s of server time instead of 40 packets, so several players can share one clock.
- A client that stalls while the first snapshots arrive (loading art on the first spawn) no longer draws everything seconds late for a long time: `SnapshotClock` jumps when it is far behind instead of slewing.
- `release.yml` adopts a GitHub Release that already exists for the tag (e.g. one created on GitHub's "Draft a new release" page): it attaches the verified files and replaces the notes instead of failing, so re-running the job is safe. The v0.1.1 run failed this way (#11).

## [0.1.1] - 2026-10-23

**The first published release.** It contains everything listed under 0.1.0 in [CHANGELOG.md](https://github.com/paulshannon/game/blob/main/CHANGELOG.md) (the space game and its menu, touch controls, smoother networking, rejoin after disconnects, the Docker image, git-flow releases), plus the fix below. The `v0.1.0` tag points at a pre-release `develop` commit and was never published: its release run stopped at the first check.

### Fixed
- `release.yml` accepts only tags on `main`'s own merge commits; a tag on a commit merely reachable from `main` (like the stray `v0.1.0`) is rejected with instructions (#11).

## [0.1.0] - 2026-10-23

### Added
- **Space** game (`?game=space`, port 9082) with a main menu built from Kenney's UI Pack: Sci-fi; games can now provide a start menu (`GameMenu`) (#6).
- Touch controls for iPad and phones: floating stick and Jump button (#5).
- Server-restart smoke test (`SMOKE_RESTART=1 tools/smoke.sh`), run by `tools/verify.sh` (#2).
- `TestCase.expect_error()`; the test runner fails tests that log any error and self-checks on every run (#1).
- Git-flow branching, tagged GitHub Releases with the web build, server binary and checksums, and the latest release published to GitHub Pages (#7).
- Docker image for the game server, pushed to `ghcr.io/<owner>/game-server` on each release, smoke-tested in CI on every push; `deploy/docker-compose.yml` runs the games behind Caddy (#8).

### Changed
- Remote players are interpolated on server time, so a burst of snapshots after a network stall no longer makes them teleport (#2).
- Shared player networking lives in `PlayerNet`; `Net.close_gracefully()`/`Net.shutdown()` are now `Net.close_socket()` (#4).

### Fixed
- A test that crashed with a script error was reported as passing (#1).
- Held input stayed applied forever when a client stopped sending (#2).
- After a disconnect, stale players stayed on screen and there was no way to rejoin (#2).
- A player joining as another left could be told the match was full; newcomers could spawn on top of others (#3).
- The systemd unit gave Godot no writable home, which crashes the server at startup (#3).
- Release-build server logs could be lost when the process was killed or its output piped (stdout is now flushed on every print) (#8).

## [0.0.0] - 2026-10-21

Kenney multiplayer browser starter (2D and 3D) imported.
