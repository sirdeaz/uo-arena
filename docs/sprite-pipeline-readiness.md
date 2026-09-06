# Is the codebase ready for a sprite asset pipeline?

Assessment written 2026-09-06 against `main` at `7b8bf5a`, in response to "moving to 2D
using an asset pipeline seems like the easiest way to get a good enough looking result."

**Nothing here is decided.** The decision itself lives in #22; this is the working behind
it, kept so the reasoning survives whichever way it goes.

**Short version: structurally yes, but the real blocker is not rendering at all — there is
no facing direction anywhere in the game.** And "easiest way to a good-enough result" is
probably right about the world and probably wrong about gameplay state.

Note the game is already 2D. What is being proposed is replacing procedural `_draw()` with
authored sprite assets.

---

## What is ready

**The client/server split is exactly right.** `server/` holds no rendering code, and
`NetProtocol` carries position, health, flags and cast state — nothing visual. Sprites are
a pure client change needing **no protocol change**. This is the same property that made
pathfinding cheap to add.

**Drawing is already concentrated.** 2,831 lines of client in total, with rendering
confined to five files:

| File | Lines |
| --- | --- |
| `client/arena_view.gd` | 325 |
| `client/fighter.gd` | 368 |
| `client/bolt_layer.gd` | 79 |
| `client/spell_fx.gd` | 100 |
| `client/cast_bar_ui.gd` | 104 |

Nothing draws from inside game logic, so there is no scattered rendering to hunt down.

**The import pipeline is already proven.** Uncial Antiqua landed with a `.import` file and
CI builds it on every push, so textures follow a path that is known to work rather than a
new one. Two `.import` files are tracked today (the font and `icon.svg`).

**The palette gives an artist a brief.** `client/palette.gd` already states the art
direction by role, with one meaning per colour.

---

## What fights it

### 1. `ArenaView`'s founding invariant is "no art assets"

Its docstring is explicit:

> Draws the arena straight from its collision shapes, so what you see is exactly what the
> raycast hits. No art assets, no second source of truth to drift out of sync.

Two rules hold that file together: every collision shape gets drawn, and a silhouette
never hides part of its own collision box. **A tent sprite is exactly the second source of
truth that invariant exists to prevent.** `tests/test_arena_view.gd` has 12 tests pinning
it.

This is a design position to revisit deliberately, not an obstacle to route around — it is
the same reasoning that made invisible cover (#4) worth fixing.

*Mitigation:* keep collision authoritative, treat sprites as decoration aligned to it, and
keep a developer overlay that draws the true shapes. Several of those 12 tests get
reframed rather than deleted.

### 2. The actual blocker — there is no facing direction

`facing`, `rotation`, `look_at`: **zero hits** across `client/`, `server/` and `common/`. A
fighter is a circle with no orientation.

UO-style character art needs 8-direction facing plus idle / walk / cast / death states.
That is a **model** change, not an art change, and it is the one place the answer is
genuinely *not ready*.

It is also the only part of this that touches the wire. The client can derive facing from
movement delta for free, but a remote player standing still and casting would face
wherever they last walked rather than their target. Fixing that properly means a 9th slot
in the record (`RECORD_SIZE` is currently 8) and a `PROTOCOL_VERSION` bump.

Worth doing regardless of whether sprites ever happen: "which way is that player facing"
is missing information in a PvP game.

### 3. No y-sorting

`z_index` is hand-assigned as flat layers — sight line 5, bolts 6, fx 0. Flat top-down
circles never needed depth. Tent sprites with height do: a player behind a tent should be
occluded, in front of it should not. This interacts with those fixed z-indices.

### 4. Web build weight

The renderer is `gl_compatibility`, thread support is off, and PR #13 deliberately turned
**off** `vram_texture_compression` — correct when there were no textures, wrong the moment
there are. The browser build is the primary distribution channel and the README leads with
it, so this needs revisiting as a deliberate budget rather than as a surprise.

### 5. The palette test quietly stops covering things

`tests/test_palette.gd` scans `client/*.gd` for `Color("#` and enforces one meaning per
colour. Colour decisions that move into PNGs are invisible to it. Not a blocker, but the
guarantee weakens without anything failing to say so.

---

## The recommendation: hybrid, not replacement

Every gameplay read in this game is colour- and shape-coded, and PR #10 was spent giving
each colour exactly one meaning. Status rings, cast aura, progress ring, mantra, sight
line and the pathfinding route are all reads under time pressure.

A sprite pass that absorbs those will make the game **prettier and harder to read**.

- **Sprites for the world** — floor, tents, rocks, bodies.
- **Procedural for state** — rings, cast progress, sight line, route.

Lower risk, keeps the reads, and it is most of the visual win.

---

## Sequencing, if it goes ahead

Not one job. Each of these is its own issue:

1. **Facing and animation state model** — no art involved. The blocker, and worth doing on
   its own merits.
2. **Y-sorting**, replacing the flat z-index layers.
3. **Floor and cover sprites**, collision still authoritative, with a debug overlay.
4. **Character sprites.**
5. **Web build budget** revisit.

---

## Open questions

- Does facing get derived client-side (free, slightly wrong for stationary remote casters)
  or carried on the wire (correct, costs a protocol bump)?
- Is the `ArenaView` invariant retired, or kept as a debug overlay?
- What is the acceptable browser download size? That number decides the art budget more
  than taste does.
