# Box Arena 3D

**Core loop:** up to 8 players run and jump on a flat floor with a follow camera. Like the 2D arena, it's a working multiplayer skeleton to build a real prototype on.

**Players:** 1–8. **Dimension:** 3D. **Port:** 9081.

**Kenney packs:** none yet. To add art, install a 3D pack (`tools/add_kenney_pack.sh`), then set `BoxPlayer3D.MODEL_PATH` to one of its GLBs (adjust `MODEL_SCALE` if needed). Good starting packs: *Mini Characters*, *Platformer Kit*, *Blocky Characters*. The model is purely visual; collision and movement stay in `ArenaSim.step_3d`.

| File | Runs on | Does |
|---|---|---|
| `arena_3d.gd` | both | floor, light, environment, follow camera (client only) |
| `player_3d.gd` | both | server: sim from input; client: interpolated position + slerped facing |

Rendering stays inside the Compatibility renderer's budget (one directional light, colour background, no SDFGI/SSR/volumetrics), so the web build looks like the editor.
