# Space

![Three ships shooting asteroids](../../docs/screenshots/space-asteroids-native.png)

**Core loop:** co-op asteroid shooting. Fly a ship with momentum, shoot asteroids, and pick up power-ups. Large rocks split into two medium rocks, and medium rocks into two small ones; smaller rocks are worth more (20 / 50 / 100). Hitting a rock with your ship destroys it, unless your shield takes the hit. You respawn where you were destroyed after 2 s, blinking and invulnerable for 2 s. Shots don't hurt other players. Score is per player and shown top-right.

**Ships** (#31): pick one of four ships and its colour on the menu before Play (`SpaceShipPicker`); both are remembered (`user://space.cfg`). Left/Right (keys, D-pad, stick) or the arrows change the ship; Up moves to the colour button, where Left/Right change the colour. Colours are blue, green, orange and red, or **auto** (the default): your seat's colour, so players who don't pick still differ. Anyone may pick a colour someone else has; the labels still tell you apart. Your colour also tints your shots and your score.

**Bots** (server-flown): the menu's **Bots** row (0–7) asks the server to fly that many bot ships. Only the first person into an empty match decides (the pick goes with the join request; later players' picks are ignored), and going back to select while alone lets you change it. Bots are ordinary ships spawned by the server (`ServerBots`, fake negative peer ids, labelled "Bot (P2)" and "bot" on the scoreboard), flown by `SpaceBot` reading the server's own state, with a random ship and colour. They take free seats only, one gives up its seat when someone joins a full match, and they all leave with the last person.

![Three server bots flying with you](../../docs/screenshots/space-server-bots.png)

**Changing ship mid-game:** Esc (Start on a controller, the **Menu** button top-left on touch; remappable as "Ship select") despawns your ship and brings the menu back. Pick again and Play: you rejoin on the same connection, in the same seat, with your score. It's the generic `InputSetup.MENU` action: `main.gd` calls `GameBase.leave_to_select()` (the server checks the sender, removes that player and keeps the seat waiting) and Play sends the join request again. Games without a menu get their join button back instead.

![Picking a green Hornet on the menu](../../docs/screenshots/space-ship-picker.png)

| Ship | Art | Thrust | Top speed | Turn | Fire every |
|---|---|---|---|---|---|
| **Falcon**: all-rounder | `playerShip1` | 560 | 440 | 4.2 rad/s | 0.25 s |
| **Comet**: fastest, slow to fire | `playerShip2` | 700 | 540 | 3.8 rad/s | 0.32 s |
| **Hornet**: turns tightest | `playerShip3` | 520 | 420 | 5.6 rad/s | 0.22 s |
| **Gunship**: fires fastest, heavy | `Enemies/enemy*2` (black for orange players) | 440 | 360 | 3.4 rad/s | 0.15 s |

All hulls are the same size to hit, and rapid fire is 0.1 s for all. The pick travels in the join request (`GameBase.join_choice`, `{"hull", "color"}`): the server claims your seat when you connect, but spawns your ship only when the request arrives. `SpaceArena._sanitize_choice` rebuilds it from those two keys (hull clamped, auto or out-of-range colour → the seat's), so the spawn data carries `"hull"` and `"color"` and every peer builds the right ship from the first frame.

**Infinite map** (#29): space has no edges. The camera follows your ship, and the star field scrolls in three parallax layers so you can see yourself moving. The server keeps at least 6 rocks within 1000 px of every ship (`SpaceField`), bringing new ones in just off screen (800 px out) heading roughly towards that ship, and removes rocks more than 1800 px from every ship, so the field costs the same however far apart players fly. A player who joins late spawns next to a ship already in the match. Effects (explosions, other players' shot sounds) more than 1200 px from your camera are skipped, so a dropped rock never explodes on anyone's screen. Positions are 32-bit floats: precision stays well under a pixel for the first ~10⁶ px, about 40 minutes of flying flat out in one direction.

**Pickups** (15% chance per destroyed rock, gone after 12 s): **bolt** = rapid fire for 8 s, **shield** = absorbs one hit, **star** = +250 points.

**Thrusters:** the main engine flames while thrusting. Braking fires two RCS puffs forward from the nose. Turning fires a pair on opposite sides (one at the nose, one at a wingtip) that push the nose round. They're cosmetic: the server sends which ones are firing in the ship's `flags`.

![RCS thrusters braking and turning](../../docs/screenshots/space-rcs-thrusters.png)

**Controls:** Left/Right (A/D) turn, Up (W) thrust, Down (S) brake, Space fire, Esc ship select; on a controller, left stick or D-pad, A or RT to fire, Start for ship select. All of them can be remapped on the menu's **Controls** page (below). On touch, the stick's left/right turns and pushing it up thrusts; Fire is bottom-right, Menu (ship select) top-left. Controls are the same `move` vector as the box games plus a `fire` action, so the protocol and `InputRelay` stay generic. The relay sends only the game's own button (`GameBase.action_button()`), and ignores a key still held from pressing Play until it's released.

**Players:** 1–8 (`Protocol.MAX_PLAYERS`). **Dimension:** 2D. **Port:** 9082. **URL:** `?game=space`.

**Kenney packs:**
- `space-shooter-remastered` (Space Shooter Redux): ships, meteors, lasers, power-ups, engine flame, shield.
- `space-shooter-extension`: smoke puffs for explosions.
- `sci-fi-sounds` + `digital-audio`: shot, explosion, shield and pickup sounds.
- `ui-pack-sci-fi`: the menu.

All are CC0; see `CREDITS.md`.

**Menu:** Play joins the match (Enter / Space / gamepad work too: Play has focus). **Controls** opens the settings page: two keys and two controller inputs per action (`ControlsEditor`, `InputBindings`). Pick a slot, then press a key, a button, or push a stick or trigger; Esc or a click cancels, an input already used by another action moves to the new one, and Reset restores the defaults. Changes are saved at once to `user://controls.cfg` (in the browser: its IndexedDB) and loaded at startup. On touch screens the page also explains the touch controls, which can't be remapped. The controls aren't described on the play screen any more. Quit only appears outside the browser.

![The Controls page](../../docs/screenshots/space-controls.png)
 After a lost connection the menu comes back with the reason and **Rejoin** / **Try again**. Bots (smoke tests) skip it.

## How it's networked

- **Rules** are in `space_sim.gd`: pure functions, unit-tested in `tests/unit/test_space_sim.gd`. The server runs them; clients never decide a hit, a pickup or a score.
- **Ships** (`SpaceShip`) use `PlayerNet` like every player. Position, rotation, `flags` (alive, thrust, brake, turn left/right, shield, rapid, invulnerable) and the `pickups` count are sent every snapshot, so each change is stamped with the server time it happened at. A `StateTimeline` plays the change when render time reaches it: a ship explodes where it's drawn touching the rock, and a pickup sounds when it's drawn being collected. A late joiner gets no effects for what happened before it arrived. A destroyed ship stays parked, hidden, where it was hit until it respawns, so it never slides across the field before exploding. `score` is sent only when it changes.
- **Asteroids, shots and pickups** (`SpaceEntity`) are spawned by the server through a second `MultiplayerSpawner` (`Game/EntitySpawner`). Their paths are fixed by the spawn data (origin, velocity, server time; straight lines), so nothing is replicated after the spawn: each peer computes the position for any server time. Removing the node on the server despawns it everywhere.
- **One clock**: ships and entities on a client are drawn at the same server time (`SpaceArena.clock`, shared through `PlayerNet.use_clock`), so a shot leaves the nose of the ship as drawn.
- **Swept hits**: each tick tests a shot's whole path since the last tick, so a fast shot can't step over a small rock.
- **Ghosts**: a despawn arrives while the client is still drawing 100 ms in the past. The client keeps drawing a copy (in `Game/Fx`, outside the replicated tree) until its render time reaches the removal, then explodes the rock. Shots and rocks vanish where they visibly meet.

## Smoke test

Bots use `SpaceBot`, which turns toward the nearest asteroid it can see, thrusts and fires. Each smoke client also asks for `SpaceArena.SMOKE_BOTS` (2) server bots. On top of the usual "everyone moved":
- the **server** checks that every person fired, that rocks were destroyed, and that the server bots flew and fired;
- **each client** checks that it got the hull and colour it asked for (bots pick both at random, auto included), drew its own shots, drew a rock explode, drew a server bot move, drew its own ship's RCS thrusters, and received a non-zero score from the server (any ship's: whether one particular bot lands a hit in a short run is chance).

| File | Runs on | Does |
|---|---|---|
| `space_sim.gd` | server (+ tests) | rules: hulls, ship flight, shots, asteroid paths and splits, hits, pickups, points |
| `space_ship.gd` | both | the player: sim step (server); Kenney ship, flame, RCS puffs, shield, explosion timing (client) |
| `space_entity.gd` | both | asteroid / shot / pickup: position from spawn data; sprite; ghost after despawn |
| `space_field.gd` | server (+ tests) | rules for the unbounded field: where new rocks come in, which are left behind |
| `space_director.gd` | server | rock spawning, shots, all collisions, scoring, pickups |
| `space_arena.gd` | both | world, spawners, shared clock, camera that follows your ship, `smoke_report()` |
| `space_fx.gd` | client | ghosts, explosion puffs, sounds (silent when headless) |
| `space_scoreboard.gd` | client | scores, top-right |
| `space_bot.gd` | client (smoke bots), server (server bots) | aiming pilot |
| `space_menu.gd` | client | the main menu (`GameMenu` subclass): Play, and its Controls page |
| `space_ship_picker.gd` | client | the menu's ship, colour and bots picker; remembers the picks |
| `space_ui.gd` | client | menu theme built in code from the Kenney UI pack: 9-slice panel and buttons, Kenney Future font |
| `starfield.gd` | client | procedural twinkling star field (menu background; parallax arena backdrop) |

**Tuning:** feel constants (thrust, drag, cooldowns, points, pickup times) and the hull table (`HULLS`) are at the top of `space_sim.gd`; field density and distances are at the top of `space_field.gd`; rock speed, spawn rate and the pickup drop rate at the top of `space_director.gd`. To restyle the menu, change the sprite paths and 9-slice margins in `space_ui.gd`.
