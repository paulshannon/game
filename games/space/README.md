# Space

![Three ships shooting asteroids](../../docs/screenshots/space-asteroids-native.png)

**Core loop:** co-op asteroid shooting. Fly a ship with momentum, shoot asteroids, and pick up power-ups. Large rocks split into two medium rocks, and medium rocks into two small ones; smaller rocks are worth more (20 / 50 / 100). Hitting a rock with your ship destroys it, unless your shield takes the hit. You respawn at your start point after 2 s, blinking and invulnerable for 2 s. The server keeps at least 6 rocks in play, bringing new ones in from the edge away from ships. Shots don't hurt other players. Score is per player and shown top-right.

**Pickups** (15% chance per destroyed rock, gone after 12 s): **bolt** = rapid fire for 8 s, **shield** = absorbs one hit, **star** = +250 points.

**Thrusters:** the main engine flames while thrusting. Braking fires two RCS puffs forward from the nose. Turning fires a pair on opposite sides (one at the nose, one at a wingtip) that push the nose round. They're cosmetic: the server sends which ones are firing in the ship's `flags`.

![RCS thrusters braking and turning](../../docs/screenshots/space-rcs-thrusters.png)

**Controls:** Left/Right (A/D) turn, Up (W) thrust, Down (S) brake, Space fire. On touch, the stick's left/right turns and pushing it up thrusts; Fire is bottom-right. Controls are the same `move` vector as the box games plus a `fire` action, so the protocol and `InputRelay` stay generic. The relay sends only the game's own button (`GameBase.action_button()`), and ignores a key still held from pressing Play until it's released.

**Players:** 1–8 (`Protocol.MAX_PLAYERS`). **Dimension:** 2D. **Port:** 9082. **URL:** `?game=space`.

**Kenney packs:**
- `space-shooter-remastered` (Space Shooter Redux): ships, meteors, lasers, power-ups, engine flame, shield.
- `space-shooter-extension`: smoke puffs for explosions.
- `sci-fi-sounds` + `digital-audio`: shot, explosion, shield and pickup sounds.
- `ui-pack-sci-fi`: the menu.

All are CC0; see `CREDITS.md`.

**Menu:** Play joins the match (Enter / Space / gamepad work too: Play has focus). Quit only appears outside the browser. After a lost connection the menu comes back with the reason and **Rejoin** / **Try again**. Bots (smoke tests) skip it.

## How it's networked

- **Rules** are in `space_sim.gd`: pure functions, unit-tested in `tests/unit/test_space_sim.gd`. The server runs them; clients never decide a hit, a pickup or a score.
- **Ships** (`SpaceShip`) use `PlayerNet` like every player. Position, rotation, `flags` (alive, thrust, brake, turn left/right, shield, rapid, invulnerable) and the `pickups` count are sent every snapshot, so each change is stamped with the server time it happened at. A `StateTimeline` plays the change when render time reaches it: a ship explodes where it's drawn touching the rock, and a pickup sounds when it's drawn being collected. A late joiner gets no effects for what happened before it arrived. A destroyed ship stays parked, hidden, where it was hit until it respawns, so it never slides across the field before exploding. `score` is sent only when it changes.
- **Asteroids, shots and pickups** (`SpaceEntity`) are spawned by the server through a second `MultiplayerSpawner` (`Game/EntitySpawner`). Their paths are fixed by the spawn data (origin, velocity, server time; asteroids bounce in closed form), so nothing is replicated after the spawn: each peer computes the position for any server time. Removing the node on the server despawns it everywhere.
- **One clock**: ships and entities on a client are drawn at the same server time (`SpaceArena.clock`, shared through `PlayerNet.use_clock`), so a shot leaves the nose of the ship as drawn.
- **Swept hits**: each tick tests a shot's whole path since the last tick, so a fast shot can't step over a small rock.
- **Ghosts**: a despawn arrives while the client is still drawing 100 ms in the past. The client keeps drawing a copy (in `Game/Fx`, outside the replicated tree) until its render time reaches the removal, then explodes the rock. Shots and rocks vanish where they visibly meet.

## Smoke test

Bots use `SpaceBot`, which turns toward the nearest asteroid it can see, thrusts and fires. On top of the usual "everyone moved":
- the **server** checks that every player fired and that rocks were destroyed;
- **each client** checks that it drew its own shots, drew a rock explode, drew its own ship's RCS thrusters, and received a non-zero score from the server (any ship's: whether one particular bot lands a hit in a short run is chance).

| File | Runs on | Does |
|---|---|---|
| `space_sim.gd` | server (+ tests) | rules: ship flight, shots, asteroid paths and splits, hits, pickups, points |
| `space_ship.gd` | both | the player: sim step (server); Kenney ship, flame, RCS puffs, shield, explosion timing (client) |
| `space_entity.gd` | both | asteroid / shot / pickup: position from spawn data; sprite; ghost after despawn |
| `space_director.gd` | server | rock spawning, shots, all collisions, scoring, pickups |
| `space_arena.gd` | both | world, spawners, shared clock, camera, `smoke_report()` |
| `space_fx.gd` | client | ghosts, explosion puffs, sounds (silent when headless) |
| `space_scoreboard.gd` | client | scores, top-right |
| `space_bot.gd` | client (bots) | aiming smoke-test pilot |
| `space_menu.gd` | client | the main menu (`GameMenu` subclass) |
| `space_ui.gd` | client | menu theme built in code from the Kenney UI pack: 9-slice panel and buttons, Kenney Future font |
| `starfield.gd` | client | procedural twinkling star field (menu background and arena backdrop) |

**Tuning:** feel constants (thrust, drag, cooldowns, points, pickup times) are at the top of `space_sim.gd`; field density and the pickup drop rate are at the top of `space_director.gd`. To restyle the menu, change the sprite paths and 9-slice margins in `space_ui.gd`.
