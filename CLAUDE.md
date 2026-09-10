# Working on UO Arena

## An issue comes first, always

**Open a GitHub issue before writing any code.** The issue is the unit of work here, not
the pull request. It is where the problem gets stated, argued about and agreed on, and it
is what makes the history readable later — a PR that appeared from nowhere leaves no
record of why anyone thought the change was worth making.

This holds however small the change looks, and whoever noticed it.

## Plan mode ends at an issue, not at code

**The deliverable of a planning session is an issue.** When plan mode is used, the plan
gets written up as a GitHub issue and the work stops there, for a separate decision about
whether and when to build it.

Approving a plan is not approval to implement it. `ExitPlanMode` means "the plan is
settled" — the next step is filing it, then stopping and saying so.

Do not go from an approved plan straight into changing files, opening a branch, or raising
a PR. Wait to be asked.

## What an issue should carry

Match the ones already in the repo — #1–#9 set the house style, #72 and #77 are recent
worked examples:

- The problem, in terms of what a player or a maintainer actually experiences.
- Evidence, as `file.gd:line` references — the real code, not a paraphrase of it.
- Why it matters *for this game specifically*, not in the abstract.
- A proposal, held loosely, with the trade-offs named.
- A "done looks like" section that someone else could check against.
- A "watch out for" section when there are traps — a sealed gap, a silent fallback, a test
  that cannot catch the thing.

Prefer several small issues over one that bundles unrelated work, and cross-reference them
when one depends on another.

## Then, and only when asked

Implementation goes on the branch named in the session's instructions, and the PR body
says `Closes #N`. If a PR for that branch has already merged, restart the branch from the
current `main` rather than stacking on merged history.

Work each issue in its own git worktree, so an open editor's re-imports on one branch
cannot dirty `main` or another issue's tree:

```bash
git worktree add ../uo-arena-<n> -b claude/issue-<n>-<slug> origin/main
```

Remove it once the PR merges (`git worktree remove ../uo-arena-<n>`). This is the
recommended default, not a gate — a plain `git checkout -b` still works where worktrees
are not to hand.

## Commands

```bash
./run_tests.sh          # headless suite; expects a clean pass
./run_game.sh           # the offline practice harness
./build.sh              # native + browser builds
```

Built and tested on **Godot 4.7** — `project.godot`'s `config/features` names it and
`config_version=5` is a 4.7 project file. `tools/godot.sh` finds the binary via
`$GODOT_BIN`, then `godot4`/`godot` on `PATH`, and accepts any 4.x — but opening the
project in an older 4.x rewrites every `.tscn`/`.tres` it touches into that version's
format, so check `godot --version` before a first import. The suite needs the project
imported first, and a fresh clone needs **two** import passes — the first reports errors
for class names not yet registered.

## Conventions worth not relearning

- **Tests use real objects, not mocks**, and there is no framework: `tests/test_*.gd`
  subclassing `TestCase`, discovered by `tests/test_main.gd`. Only four assertions exist
  and the message argument is mandatory — write it as why the behaviour matters.
- **Pull the decision into a static function** so it can be tested without a scene tree.
  This is the strongest convention in the codebase; `Fighter.movement_direction_toward`,
  `ArenaServer.pick_spawn` and `FighterSprite.facing_for` all exist in that shape for
  that reason. It survives the editor-first rule below — an authored node may *call* the
  static, but the decision itself keeps no node reference.
- **`server/` holds no rendering code**, so the Dedicated Server export stays lean. The
  one seam is the shared arena scene: it references a `TileSet`, the server runs its
  `TileMapLayer`s headless for collision, and CI builds the dedicated-server export and
  fails if the character art leaks in or the PCK balloons (`.github/workflows/deploy.yml`).
  `server/player_body.gd`'s collision body is physics, not rendering, and stays the
  documented exception.
- **Every colour goes through `client/palette.gd`.** One meaning per colour, and
  `tests/test_palette.gd` fails on a raw hex literal anywhere in `client/`. A variant of an
  existing signal should be a new named *alpha*, not a new hue.

## Editor-first layout

Standard Godot 4.7, assembled in the editor, is the default. Code is the exception, and
an exception states its reason — a carve-out below, or something the editor genuinely
cannot express. Tests and `tools/` are outside this rule; they are fixtures.

- **A code change has to earn its place.** A new `.gd`, a build step in `_ready()`, or a
  `load()` where a scene / `@export` / authored child would do: the issue or PR names the
  carve-out it falls under, or says what the editor cannot express. "It was quicker in
  code" is not that reason.
- **Scenes and resources are `@export` or an authored child, not `load()`.** A scene a
  node needs is instanced in the `.tscn` that owns it, or declared
  `@export var thing: PackedScene` / `Resource` and wired in the Inspector.
  `client/art/fighter_chrome.tres` on `Fighter`, the `SpriteFrames` on its `Character`
  node, and `practice_scene` on `client_main.gd` are the pattern. `load("res://…%s.tres")` string-building is the thing
  `SpellBook.by_name` exists to kill.
- **Layout lives in `.tscn`.** The camera, view layers, HUD, join menu and audio nodes
  are authored (`client/scenes/arena_stage.tscn`, `arena_hud.tscn`, `client_main.tscn`),
  not built in `_ready()` with `.new()` + `add_child()` and pixel constants. Anchors, not
  offsets against an assumed 1280×720.
- **One authored scene, shared by both clients.** The networked client and the practice
  harness instance the same `arena_stage.tscn` — never two parallel `_ready()` trees kept
  identical by memory. They drifted once already (`ArenaGround.position`, #43). A new
  feature reuses the authored entry scenes and their composition — `client_main.tscn`,
  `arena_stage.tscn`, `server_main.tscn`, `arena_server.tscn` — rather than adding a
  second bootstrap path; a parallel setup is that drift waiting to happen, and is a bug
  even while the two copies still match.
- **One arena scene for client and server.** `res://arena/arena_map.tscn` is hand-painted
  and the tiles own the collision — a physics layer on the obstacles bit, and nothing
  else. Nothing describes the layout in code: `arena/arena_map.gd` reads it back —
  `obstacle_polygons()` lifts each painted cell's collision polygon off its `TileData`,
  unions the touching ones with `Geometry2D.merge_polygons()` and splits the result into
  convex pieces for the visibility graph; `bounds()` is the `Floor` layer's used rect.
  Repaint the arena in the editor; the code adapts, and there is no grid size or field
  size left in a `.gd` to keep in step. The server *instances* `arena_map.tscn`
  too — as the `Arena` child of `server/arena_server.tscn`, never `load()`ed in
  `_ready()`. `arena_server.tscn` (root `ArenaServer` + `Arena` + `Resolver`) and
  `server_main.tscn` (composing an authored `ArenaServer`) are the server-side
  counterparts of `arena_stage.tscn` / `client_main.tscn`: a fixed node assembled in
  `_ready()` with `.new()` + `add_child()` is a bug — author it. The bare
  `ArenaServer.new()` is not on the must-stay-constructible list (unlike
  `Combatant` / `CombatResolver` / `PathFinder`); its three tests instance
  `arena_server.tscn` and are the only guard against a silent slide back to `.new()`.
- **A per-instance role, if one is ever needed, goes in a Node Group or TileSet
  custom-data** read by a helper — not a `type` enum on every instance. Nothing in the
  tree needs one today; this is the shape to reach for when something does.

### Carve-outs — these stay code, by name

1. **The decision still goes in a static function** (see above). Authoring the node that
   calls it changes nothing.
2. **`autoload/network_manager.gd` is the only file that knows what an RPC is**, and
   `common/net_protocol.gd` is the wire contract. `MultiplayerSpawner` /
   `MultiplayerSynchronizer` are deliberately **not** adopted — they need a live peer and
   bind replication to the tree, and the suite that gates the deploy runs the whole sim
   with no socket.
3. **`client/palette.gd` stays one flat `.gd` module in `client/`.**
   `tests/test_palette.gd` walks `res://client` non-recursively for `Color("#`; a Theme
   resource cannot carry the "one meaning per colour" checks or the rationale, and a
   subfolder drops the script from the scan.
