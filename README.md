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

Prefer a native build? **[Download it](../../releases/latest)** — Windows (unzip,
double-click `UOArena.exe`; it's unsigned, so Windows shows a "more info → run anyway"
prompt) or Linux (untar, `chmod +x UOArena.x86_64`, run it). The browser link avoids all
of that entirely.

## Requirements

- Godot 4.x
- Git

| | Install |
| --- | --- |
| Arch / Omarchy | `sudo pacman -S godot` |
| Debian / Ubuntu | `sudo apt install godot4`, or download from [godotengine.org](https://godotengine.org/download) |
| macOS | `brew install --cask godot` |
| Windows | `winget install GodotEngine.GodotEngine` |

The scripts find Godot themselves: `$GODOT_BIN` if you set it, otherwise `godot4` or
`godot` on `PATH`, otherwise the winget install location on Windows — winget does not put
Godot on `PATH`, which is why that last step exists. Set `GODOT_BIN` to use a specific
build.

Flatpak Godot is deliberately not searched for: it is sandboxed, so it needs `flatpak
run` rather than a path and cannot see the project directory or write `build/` without
explicit filesystem grants. Point `GODOT_BIN` at a wrapper script if you want it anyway.

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

```sh
./build.sh              # Linux, macOS
powershell -File build.ps1   # Windows
```

Both produce this machine's native build plus the browser build, neither of which needs
Godot, a GitHub account, or this repo:

- **A native build** — `build/UOArena-linux-x86_64.tar.gz` (~28 MB) or
  `build/UOArena-win64.zip` (~36 MB). Send it however you like; it ships with a
  plain-English `READ ME FIRST.txt` covering both platforms. The Windows build is
  unsigned, so SmartScreen shows a "more info → run anyway" click-through. The Linux
  build is a tarball rather than a zip so the executable bit survives the trip.
- `build/web/` — a browser build. Upload the folder to any static host and send the
  link; it plays in a tab on any OS with nothing to install. Exported without thread
  support on purpose, so it works on plain static hosting with no special headers.

`--linux` / `-Windows`, `--web` / `-Web` and `--server` / `-Server` build one target on
its own. `--server` produces the headless Dedicated Server binary that
`autoload/network_manager.gd` is written around.

Both are verified working: the exe runs standalone, and in-browser the keyboard
casting, right-click steering, and cast-while-moving all behave (Godot suppresses the
browser context menu, so right-click-to-move is safe).

Building needs Godot's export templates for the matching engine version — see the
header of `build.sh` or `build.ps1` for where they go on each OS.

## Playing it

```sh
./run_game.sh               # Linux, macOS
powershell -File run_game.ps1    # Windows
```

(`--editor` / `-Editor` opens the Godot editor instead, `--server` / `-Server` runs
headless as a dedicated server.) The client boots straight into `client/scenes/local_test.tscn` — a local,
network-free harness against a dummy that casts magic arrow at you on a loop.

| Input | |
| --- | --- |
| hold right mouse | walk toward the cursor, UO-style — works freely while casting |
| `1`–`5` | magic arrow, poison, lightning, flamestrike, paralyze |
| `R` | reset the round |
| `M` | mute |
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

Spells that connect draw a coloured bolt and an impact ring, and make a sound. Spells
stopped by cover do none of those things — in UO a spell with no line simply never goes
off.

**Listen for the fizzle.** Classic UO magery is ear-driven: you learn to hear a cast
start, a spell land and a fizzle without watching the caster. The cues are synthesised
at load rather than shipped as files, and they are told apart by shape — a cast gathers
upward, a fizzle falls away and sputters, an interrupt is a short hit. This matters most
for the fizzle, which happens at the exact moment you are watching the sight line and
your own footing instead of the enemy's feet. `M` mutes.

## Arena

`server/arena_map.tscn` is 1200×800 with spawns at `(±500, 0)` — about 5.5s apart at
`PLAYER_MOVE_SPEED`. Four cover pieces, placed with 180° rotational symmetry so neither
spawn is favoured: two tents flanking a clear centre lane, two rocks in opposite
corners. Tents are drawn as peaked shelters and rocks as irregular lumps, so the
instruction to "get behind a tent" names something you can pick out.

The floor carries a faint grid at one cell per second of movement, which is what turns
"can I reach that tent before the flamestrike lands" into a distance you can count
against a cast time rather than estimate. The duel opens with a shot available straight down the lane; stepping off it
puts a tent in the way immediately.

The scene holds collision bodies only — no sprites — so the client can draw its own view
and `server/` stays exportable as a Dedicated Server build. What kind of thing a cover
piece is travels as a node group (`cover_tent`, `cover_rock`), which is plain scene data
rather than a second copy of the artwork. Open it in the editor to drag cover around, and
add a piece with any collision shape you like — `ArenaView` draws rectangles, circles,
capsules and convex polygons, and anything it cannot draw comes out as a loud magenta box
with a warning rather than as invisible cover; `tests/test_arena_map.gd` will tell you if a change breaks the layout, since
it asserts cover is reachable within two seconds of movement and that both spawns get an
equal amount of it.

## Tests

```sh
./run_tests.sh              # Linux, macOS
powershell -File run_tests.ps1   # Windows
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
