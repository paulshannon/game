# Box Arena 2D

**Core loop:** up to 8 players move top-down boxes around a walled arena. That's all — it exists to prove the multiplayer loop (input → server sim → snapshot → interpolation) before any game design goes in.

**Players:** 1–8 (`Protocol.MAX_PLAYERS`). **Dimension:** 2D. **Port:** 9080.

**Kenney packs:** none yet. To add art, install a 2D pack (`tools/add_kenney_pack.sh`), convert its spritesheet (`tools/kenney_atlas.sh assets/kenney/<pack>`), then set `BoxPlayer2D.SPRITE_PATH` to one of the generated `.tres` files. Good starting packs: *Toon Characters*, *Tiny Dungeon*, *Pixel Platformer*.

| File | Runs on | Does |
|---|---|---|
| `arena_2d.gd` | both | floor, walls, camera (client only), spawn points |
| `player_2d.gd` | both | server: sim from input; client: interpolated drawing |

Movement rules live in `common/sim/arena_sim.gd` (`step_2d`), not here, so they're testable and reusable for prediction.
