# UO Arena

Classic Ultima Online magery PvP as a small arena game: cast-while-moving, fixed cast
times, fizzle on recast-too-soon, interrupt-on-hit, and line-of-sight dodging behind
cover. Godot 4, GDScript. 1v1 first, team modes later.

> **Early prototype.** Ten-player multiplayer works over a local network; there are no
> rounds, no scoring and no matchmaking yet. It exists to prove the feel is achievable,
> not to be a game.

## ▶ Play it in your browser

### **[sirdeaz.github.io/uo-arena](https://sirdeaz.github.io/uo-arena/)**

Nothing to download or install, works on Windows, macOS and Linux, and it's always the
latest version — every push to `main` republishes it automatically.

Hold **right mouse** to walk toward the cursor, **1**–**5** to cast, **R** to reset.
Watch the words above a caster's head: `Kal Vas Flam` means a flamestrike is 2.5 seconds
away and you should get behind a tent.

The browser version is **offline practice against a dummy**. Godot's HTML5 export has no
ENet, so a page cannot join a server — multiplayer needs a native build. (The transport
is isolated behind two functions in `network_manager.gd`; moving to WebSockets, which
browsers *can* speak, is a change to those two and nothing else.)

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

`client/palette.gd` holds every colour in the game. They are all `_draw()` arguments —
there are no textures, sprites or shaders — so the palette is the art. It is grouped by
role rather than by hue to keep one meaning per colour: green is poison and nothing
else, red means you are nearly dead and nothing else, and whether you have a shot is a
solid line versus a dashed one rather than a third claim on those two.

`autoload/network_manager.gd` routes to `server/server_main.tscn` when the build has the
`dedicated_server` feature or is launched with `--server`, and to `client/client_main.tscn`
otherwise.

## Multiplayer

Up to ten players, one authoritative server, ENet. Start a server and point clients at it:

```bash
powershell -File run_game.ps1 -Server
```

```bash
powershell -File run_game.ps1 -Connect 127.0.0.1
```

Without `-Connect` a client opens a join screen with an address box and an **Offline
practice** button. `-Port` moves all of it off the default 24567.

**The server decides everything.** It owns positions, health, status timers and every
cast state machine, and broadcasts the world 20 times a second. Clients draw what they
are told. The three ways a cast can end — completed, fizzled, interrupted — are announced
as their own events rather than sampled, because a snapshot cannot tell a fizzle from an
interrupt, and `INTERRUPTED` clears itself within a frame.

**Your own movement is predicted.** The client keeps running `move_and_slide` on your
input so steering stays instant, and is pulled back toward the server's version when the
two drift more than 28 px apart. A gap over 120 px is a respawn rather than an error, and
snaps. Waiting a round trip to start walking would be felt on every dodge, which in a
game about stepping behind a tent mid-cast is the whole thing.

**Nothing trusts the client.** No request carries a "who I am" field — the caster is
always the transport's own sender id, so there is no field to forge. Steering is clamped
to unit length (an unclamped direction is a fifty-times-move-speed hack in one line),
cast requests are rate-limited and re-validated against the roster, and line of sight is
checked when a cast starts and again when it lands. Peer relaying is turned off, so
clients cannot talk to each other at all.

**Targeting** is sticky: left-click a player to select them, then `1`–`5` casts at them.
The aim is committed when a cast actually *begins*, not when you press the key — a
recast fizzles what was running and the chained spell starts later, and it flies at
whoever you named with it.

**Dying** costs you four seconds, then you reappear at the spawn furthest from everyone
still standing. There are no rounds yet; `server/match_manager.gd` is the next step.

## Cast model

`EntityState` is `IDLE → CASTING → RECOVERING`, with `INTERRUPTED` as a momentary
signal state that clears the next frame.

- **Recast at any point in a cast:** the *in-progress* spell fizzles, you pay
  `GLOBAL_CAST_RECOVERY_SECONDS` of recovery, and then the spell you chained into
  starts. Nothing is castable during recovery, and there is no queueing.
- **Abandoning late costs the same as abandoning early.** If bailing out at the last
  moment were cheaper, the strongest opening would always be a long cast held purely as
  a threat and dropped for free.
- **Any damage interrupts**, including poison ticks. Paralyze interrupts too despite
  dealing no damage, because it connects.
- **You need line of sight to start a cast.** Casting at someone behind a tent is
  refused outright — nothing is spent, no recovery is paid, and any spell already
  running is untouched. Losing the shot *mid-cast* does not cancel it; that spell still
  fails at resolution, which is what makes dodging behind cover mid-flight worth doing.

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

(`--editor` / `-Editor` opens the Godot editor, `--server` / `-Server` runs headless as a
dedicated server, `--connect <addr>` / `-Connect <addr>` joins one directly, and
`--port` / `-Port` moves either off the default port.) With no flags the client opens a
join screen; **Offline practice** boots `client/scenes/local_test.tscn` — a local,
network-free harness against a dummy that casts magic arrow at you on a loop. It is the
quickest way to feel a change, and it needs no server.

| Input | |
| --- | --- |
| hold right mouse | walk toward the cursor, UO-style — works freely while casting |
| `1`–`5` | magic arrow, poison, lightning, flamestrike, paralyze |
| left click | pick your target (multiplayer only) |
| `R` | reset the round (offline practice only) |
| `M` | mute |
| `P` | route around cover instead of walking into it (offline practice only) |
| `WASD` | keyboard fallback, kept for testing |

**`P` is off by default.** With it off, holding right mouse walks straight at the cursor
and you slide along a tent that gets in the way — which is the game as it has always
played, and getting yourself around cover is most of the skill in it. With it on, a
blocked line is routed around the cover instead, and the detour is drawn so you can see
what it decided. A line that was never blocked steers exactly as it did before, so the
setting only ever changes what happens when something is actually in the way.

The line between you and the dummy is the actual raycast the resolver uses — solid when
it has a shot, dashed when cover is breaking it. Stand in the open and the dummy will
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

`server/arena_map.tscn` is 1200×800 with ten spawns, placed in 180° rotationally
symmetric pairs so no starting position is the good one. The first two are the duel lane
at `(±500, 0)` — about 4.5s apart at `PLAYER_MOVE_SPEED` — and joining players are given
spawns in that order, so the first two into a fresh server get the opening the map was
drawn around. Respawns work the other way, picking the marker furthest from everyone
still standing.

Four cover pieces: two tents flanking the clear centre lane, two rocks in opposite
corners. The duel opens with a shot available straight down the lane; stepping off it
puts a tent in the way immediately. Tents are drawn as peaked shelters and rocks as
irregular lumps, so the instruction to "get behind a tent" names something you can pick
out.

The floor carries a faint grid at one cell per second of movement, which is what turns
"can I reach that tent before the flamestrike lands" into a distance you can count
against a cast time rather than estimate.

The scene holds collision bodies only — no sprites — so the client can draw its own view
and `server/` stays exportable as a Dedicated Server build. What kind of thing a cover
piece is travels as a node group (`cover_tent`, `cover_rock`), which is plain scene data
rather than a second copy of the artwork. Open it in the editor to drag cover around, and
add a piece with any collision shape you like — `ArenaView` draws rectangles, circles,
capsules and convex polygons, and anything it cannot draw comes out as a loud magenta box
with a warning rather than as invisible cover. `tests/test_arena_map.gd` will tell you if
a change breaks the layout, since it asserts cover is reachable within two seconds of
movement from *every* spawn, that each one has a rotational partner, and that none of
them puts you inside a tent.

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
3. ~~`autoload/network_manager.gd` — ENet multiplayer wiring, up to 10 players~~ ✅
4. ~~`client/cast_bar_ui.gd` — casting feedback driven purely by `EntityState` signals~~ ✅
5. `server/match_manager.gd` — round start/win/reset

Rule of thumb: get hit resolution and cover-dodging feeling right in local single-player
before any networking goes in. Keep `server/` free of `Node2D` rendering code so the
Dedicated Server export stays clean — `server/player_body.gd` is the one exception, and
it earns it: the server has to slide along cover with the very same `move_and_slide` the
client predicts with, or hugging a tent would produce a correction on every frame.
