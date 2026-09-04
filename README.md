# UO Arena

Classic Ultima Online magery PvP as a small arena game: cast-while-moving, fixed cast
times, fizzle on recast-too-soon, interrupt-on-hit, and line-of-sight dodging behind
cover. Godot 4, GDScript. 1v1 first, team modes later.

> **Early prototype.** Single-player against a practice dummy — there is no multiplayer
> yet. It exists to prove the feel is achievable, not to be a game.

## ▶ Play it in your browser

### **[sirdeaz.github.io/uo-arena](https://sirdeaz.github.io/uo-arena/)**

Nothing to download or install, works on Windows, macOS and Linux, and it's always the
latest version — every push to `main` republishes it automatically.

Hold **right mouse** to walk toward the cursor, **1**–**5** to cast, **R** to reset.
Watch the words above a caster's head: `Kal Vas Flam` means a flamestrike is 2.5 seconds
away and you should get behind a tent.

Prefer a native build? **[Download the Windows version](../../releases/latest)** — unzip,
double-click `UOArena.exe`. It's unsigned, so Windows shows a "more info → run anyway"
prompt. The browser link avoids that entirely.

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

## Giving it to someone who doesn't code

```bash
powershell -File build.ps1
```

Produces two things, neither of which needs Godot, a GitHub account, or this repo:

- `build/UOArena-win64.zip` (~36 MB) — send it however you like. They unzip and
  double-click `UOArena.exe`. It ships with a plain-English `READ ME FIRST.txt`.
  Windows only, and unsigned, so SmartScreen shows a "more info → run anyway"
  click-through.
- `build/web/` — a browser build. Upload the folder to any static host and send the
  link; it plays in a tab on any OS with nothing to install. Exported without thread
  support on purpose, so it works on plain static hosting with no special headers.

Both are verified working: the exe runs standalone, and in-browser the keyboard
casting, right-click steering, and cast-while-moving all behave (Godot suppresses the
browser context menu, so right-click-to-move is safe).

Building needs Godot's export templates for the matching engine version — see the
header of `build.ps1`.

## Playing it

```bash
powershell -File run_game.ps1
```

(`-Editor` opens the Godot editor instead, `-Server` runs headless as a dedicated
server.) The client boots straight into `client/scenes/local_test.tscn` — a local,
network-free harness against a dummy that casts magic arrow at you on a loop.

| Input | |
| --- | --- |
| hold right mouse | walk toward the cursor, UO-style — works freely while casting |
| `1`–`5` | magic arrow, poison, lightning, flamestrike, paralyze |
| `R` | reset the round |
| `WASD` | keyboard fallback, kept for testing |

The line between you and the dummy is the actual raycast the resolver uses — green when
it has a shot, red when cover is breaking it. Stand in the open and the dummy will
interrupt whatever you're casting; step behind a tent and its casts fail silently.

**Watch the words.** A caster speaks the spell's mantra overhead for the whole cast —
`Kal Vas Flam` means a flamestrike is coming and you have 2.5s to get behind a tent.
That's the read the fizzle chain exists to fake: start a cast, let them see the words,
then fizzle into something else while they're already committed to dodging.

| Spell | Mantra | Cast |
| --- | --- | --- |
| Magic Arrow | `In Por Ylem` | 1.0s |
| Poison | `In Nox` | 1.5s |
| Lightning | `Por Ort Grav` | 1.75s |
| Flamestrike | `Kal Vas Flam` | 2.5s |
| Paralyze | `An Ex Por` | 2.5s |

Spells that connect draw a coloured bolt and an impact ring. Spells stopped by cover
draw nothing at all — in UO a spell with no line simply never goes off.

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

| Spell | Mantra | Cast time | Effect | Duration |
| --- | --- | --- | --- | --- |
| Magic Arrow | `In Por Ylem` | 1.0s | damage | — |
| Poison | `In Nox` | 1.5s | poison | 8s tick |
| Lightning | `Por Ort Grav` | 1.75s | damage | — |
| Flamestrike | `Kal Vas Flam` | 2.5s | damage | — |
| Paralyze | `An Ex Por` | 2.5s | paralyze | 4s |

Cast times and durations come from the design doc; mantras are the real UO words, pinned
by `tests/test_spell_data.gd`. Damage values in the `.tres` files are placeholders and
still need balancing.

## Build order

1. ~~`server/combat_resolver.gd` — line-of-sight raycast + hit resolution~~ ✅
2. ~~`server/arena_map.tscn` — Minoc tents map with real cover~~ ✅
3. `autoload/network_manager.gd` — ENet multiplayer wiring, 2 players
4. `client/cast_bar_ui.gd` — casting feedback driven purely by `EntityState` signals
5. `server/match_manager.gd` — round start/win/reset

Rule of thumb: get hit resolution and cover-dodging feeling right in local single-player
before any networking goes in. Keep `server/` free of `Node2D` rendering code so the
Dedicated Server export stays clean.
