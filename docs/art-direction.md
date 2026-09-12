# Art direction: what may be an asset, and what may not

Written alongside the fighter sprite that landed in #26. It states the line that has in
practice been followed since the game was nothing but `_draw()` calls, because that change
is the first one to put an image on something a player looks at in a fight.

This is a **partial** answer to #20, which asks for the same rule plus a committed byte
budget and a test that enforces both. The budget is not decided here.

## The rule

> Anything a player **reads** to make a decision stays procedural and palette-driven.
> Assets are allowed to carry everything that is not a read.

A read is something you act on under time pressure, mid-fight, at a glance: how much
health that is, whether they are poisoned, which spell is coming, whether you have a shot,
which of those two is you.

| Stays procedural | May be an asset |
| --- | --- |
| health bars, status rings | character posture and heading |
| cast aura, bursts, spell bolts | the display font the mantra is set in |
| the sight line and the steering route | audio cues |
| the identity ring under a fighter | UI chrome and menu art |
| the arena floor, cover silhouettes | window icon, `og:image` |
| anything `Palette` feeds | |

## Why the fighter sprite fits it

Ten fighters share one robe. The art therefore *cannot* say which of them you are looking
at, how hurt they are, or what they are casting — so nothing was taken away from `Palette`
by adding it. What the sprite says is posture and heading, and both are things this game
previously could not say at all: a circle standing still and a circle running looked the
same, and a circle has no front.

The identity read moved rather than vanished. It used to be the fill of the body circle;
it is now the ring around the footprint that circle became — the same colour, at the same
radius, still exactly the shape the raycast hits.

Concretely, what the sprite is **not** allowed to do, and what holds each one:

- **Say who someone is.** `Palette.BODY_RING_ALPHA`, drawn in `body_color`, and
  `tests/test_palette.gd` still pins ten separable opponents. The pack replaced in #93
  swapped its ground shadow for an authored asset too, but stopped there — the rim is
  still a `_draw()` call, in code, because a shared static image cannot carry ten
  colours.
- **Say what spell is coming.** The aura, the bolt and the mantra carry which spell, in
  that spell's own colour — a cast pose on the sprite itself would say the same thing
  again. The current pack (#93) has no cast set at all to make this mistake with; the
  code that would play one if it existed stays dormant rather than deleted, waiting for
  art that does.
- **Drift from the collision shape.** The footprint is drawn at `Constants.PLAYER_RADIUS`,
  which is the circle the server collides and the resolver raycasts.

## Where the line still needs drawing

- **A byte budget.** Still no committed number a future asset has to argue against
  (#20) — #93's pack changed the shape of the weight question (four separate textures
  instead of one shared atlas) without settling it.
- **Provenance.** Anything sourced outside the repo needs its licence recorded next to
  it, the way `client/fonts/OFL.txt` is. The fighter pack itself cleared this in #93 —
  self-authored, recorded as settled in `client/art/README.md` — but `Grass-01.png`
  still carries the *unsettled* note this section originally pointed at, which is the
  honest state, not the finished one.
- **The world.** Floor, walls and cover are authored `TileMapLayer`s in
  `arena/arena_map.tscn` now — `ArenaView` and its "no art assets" invariant were
  retired in the arena merge (#51–#55), which is what #35 asked for.
- **Heading.** Now supplied, and it is the one read the art *does* carry. That is a
  deliberate exception to the rule above rather than a hole in it: which way someone is
  pointing is a spatial fact about a body, and drawing a spatial fact anywhere but on the
  body would be the same mistake `ArenaView` exists to avoid. It stays honest because
  heading is derived from where the fighter actually moved, or from who it is actually
  casting at — never decorated. `docs/sprite-pipeline-readiness.md` recorded facing as the
  blocker for a wider pipeline; #26 removed it.
