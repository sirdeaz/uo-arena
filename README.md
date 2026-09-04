# UO Arena

Classic Ultima Online magery PvP as a small arena game: cast-while-moving, fixed cast
times, fizzle on recast-too-soon, interrupt-on-hit, and line-of-sight dodging behind
cover. Godot 4, GDScript. 1v1 first, team modes later.

## Requirements

- Godot 4.x (installed here via `winget install GodotEngine.GodotEngine`)
- Git

Godot is not on `PATH` after a winget install. Either add its folder to `PATH` or call it
by full path:

```bash
"$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe" --version
```

## Layout

```
common/      shared rules — spell data, cast state machine, constants
server/      authoritative logic only, no rendering (exports as Dedicated Server)
client/      input, rendering, prediction/interpolation, UI
autoload/    network_manager.gd picks client vs server role at boot
```

`autoload/network_manager.gd` routes to `server/server_main.tscn` when the build has the
`dedicated_server` feature or is launched with `--server`, and to `client/client_main.tscn`
otherwise.

Run as server locally:

```bash
godot --headless -- --server
```

## Spells

| Spell | Cast time | Effect | Duration |
| --- | --- | --- | --- |
| Magic Arrow | 1.0s | damage | — |
| Poison | 1.5s | poison | 8s |
| Lightning | 1.75s | damage | — |
| Flamestrike | 2.5s | damage | — |
| Paralyze | 2.5s | paralyze | 4s |

Cast times and durations come from the design doc. Damage values in the `.tres` files are
placeholders and still need balancing.

## Build order

1. `server/combat_resolver.gd` — line-of-sight raycast + hit resolution
2. `server/arena_map.tscn` — Minoc tents map with real cover (can overlap with 1)
3. `autoload/network_manager.gd` — ENet multiplayer wiring, 2 players
4. `client/cast_bar_ui.gd` — casting feedback driven purely by `EntityState` signals
5. `server/match_manager.gd` — round start/win/reset

Rule of thumb: get hit resolution and cover-dodging feeling right in local single-player
before any networking goes in. Keep `server/` free of `Node2D` rendering code so the
Dedicated Server export stays clean.
