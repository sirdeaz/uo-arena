# UO Arena

Classic Ultima Online magery PvP as a small arena game: cast-while-moving, fixed cast
times, fizzle on recast-too-soon, interrupt-on-hit, and line-of-sight dodging behind
cover. Godot 4, GDScript. 1v1 first, team modes later.

## Requirements

- Godot 4.x (installed here via `winget install GodotEngine.GodotEngine`)
- Git

Godot is **not** on `PATH` after a winget install, so `godot` alone won't work. The
`run_game.ps1` and `run_tests.ps1` scripts locate it for you; set `GODOT_BIN` to override
which executable they use.

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

## Cast model

`EntityState` is `IDLE → CASTING → RECOVERING`, with `INTERRUPTED` as a momentary
signal state that clears the next frame.

- **Recast inside the fizzle window** (first 0.25s of a cast): the *in-progress* spell
  fizzles, you pay `GLOBAL_CAST_RECOVERY_SECONDS` of recovery, and then the spell you
  chained into starts. Nothing is castable during recovery.
- **Recast after the window:** denied outright. There is no cast queueing.
- **Any damage interrupts**, including poison ticks. Paralyze interrupts too despite
  dealing no damage, because it connects.

The chain is a feint tool, not just a punishment — a stream of cast-starts that never
resolve baits an opponent into breaking line of sight or committing early. It also
means spam-casting lands nothing at all.

## Playing it

```bash
powershell -File run_game.ps1
```

(`-Editor` opens the Godot editor instead, `-Server` runs headless as a dedicated
server.) The client boots straight into `client/scenes/local_test.tscn` — a local,
network-free harness against a dummy that casts magic arrow at you on a loop.

| Key | |
| --- | --- |
| `WASD` | move (you can move freely while casting) |
| `1`–`5` | magic arrow, poison, lightning, flamestrike, paralyze |
| `R` | reset the round |

The line between you and the dummy is the actual raycast the resolver uses — green when
it has a shot, red when cover is breaking it. Stand in the open and the dummy will
interrupt whatever you're casting; step behind a tent and its casts fail silently.

## Arena

`server/arena_map.tscn` is 1200×800 with spawns at `(±500, 0)` — about 5.5s apart at
`PLAYER_MOVE_SPEED`. Four cover pieces, placed with 180° rotational symmetry so neither
spawn is favoured: two tents flanking a clear centre lane, two rocks in opposite
corners. The duel opens with a shot available straight down the lane; stepping off it
puts a tent in the way immediately.

The scene holds collision bodies only — no sprites — so the client can draw its own view
and `server/` stays exportable as a Dedicated Server build. Open it in the editor to drag
cover around; `tests/test_arena_map.gd` will tell you if a change breaks the layout, since
it asserts cover is reachable within two seconds of movement and that both spawns get an
equal amount of it.

## Tests

```bash
powershell -File run_tests.ps1
```

Headless, no external test framework — `tests/test_main.gd` discovers every
`tests/test_*.gd`, runs each `test_*` method, and exits non-zero on failure. Tests run
against real physics bodies and real `Combatant`/`EntityState` instances rather than
mocks, since the behaviour under test is how those pieces interact.

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

1. ~~`server/combat_resolver.gd` — line-of-sight raycast + hit resolution~~ ✅
2. ~~`server/arena_map.tscn` — Minoc tents map with real cover~~ ✅
3. `autoload/network_manager.gd` — ENet multiplayer wiring, 2 players
4. `client/cast_bar_ui.gd` — casting feedback driven purely by `EntityState` signals
5. `server/match_manager.gd` — round start/win/reset

Rule of thumb: get hit resolution and cover-dodging feeling right in local single-player
before any networking goes in. Keep `server/` free of `Node2D` rendering code so the
Dedicated Server export stays clean.
