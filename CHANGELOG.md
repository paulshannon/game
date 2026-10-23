# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

Each release's section becomes the notes of its GitHub Release (`tools/release_notes.sh`). On a `release/vX.Y.Z` branch, rename **Unreleased** to `[X.Y.Z] - YYYY-MM-DD` and set the same version in `project.godot` (`application/config/version`).

## [Unreleased]

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
