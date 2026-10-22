# Space

**Core loop:** so far, a main menu and a shared 2D arena in a star field: up to 8 players fly the shared top-down boxes (`BoxPlayer2D`, movement from `ArenaSim.step_2d`). The space game's own mechanics (ships, shooting, pickups…) come next; this folder is where they go.

**Players:** 1–8 (`Protocol.MAX_PLAYERS`). **Dimension:** 2D. **Port:** 9082. **URL:** `?game=space`.

**Kenney packs:** `assets/kenney/ui-pack-sci-fi` (UI Pack: Sci-fi 2.0, CC0) for the menu. No ship art yet.

**Menu:** Play joins the match (Enter / Space / gamepad work too: Play has focus). Quit only appears outside the browser. After a lost connection the menu comes back with the reason and **Rejoin** / **Try again**. Bots (smoke tests) skip it.

| File | Runs on | Does |
|---|---|---|
| `space_arena.gd` | both | star-field backdrop, arena edge, camera (client only), spawn points; `make_menu()` |
| `space_menu.gd` | client | the main menu (`GameMenu` subclass) |
| `space_ui.gd` | client | Theme built in code from the Kenney pack: 9-slice panel/buttons, Kenney Future font |
| `starfield.gd` | client | procedural twinkling star field (menu background and arena backdrop) |

To restyle: change the sprite paths and 9-slice margins in `space_ui.gd`. The pack has Blue/Green/Grey/Red/Yellow variants of every panel and bar, and `Double/` (2x) versions for crisper scaling.
