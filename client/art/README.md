# Art

## Grass-01.png

The arena. A 512×256 tileset on a 32px grid — grass for the floor, and dirt-bordered
pieces for the boundary walls and the cover (tents and rocks) sitting on top of it.
`arena/arena_tileset.tres` slices it and carries a collision polygon on every tile that
should block; nothing else says a tile is solid — there is no separate "solid" flag and
no tent/rock enum anywhere in the game.

One authored scene owns the whole arena: `arena/arena_map.tscn`'s `Floor`, `Walls` and
`Cover` `TileMapLayer`s are painted for looks and collided for physics from that same
tileset, and `arena/arena_map.gd` only reads it back — `bounds()` is the `Floor` layer's
extent, and `obstacle_polygons()` lifts the routing shapes straight off `Walls`/`Cover`'s
own tile data, unioned and split for the pathfinder. `client/scenes/arena_client.tscn`,
`client/scenes/local_test.tscn` and `server/arena_server.tscn` all instance that one
scene — there is no separate collision scene kept in step by hand.

To reshape the arena: repaint `arena/arena_map.tscn` in the editor.
`tests/test_arena_tiles.gd` fails if a painted obstacle carries no collision polygon —
cover that blocks nothing while still reading as floor — or a solid tile drifts into open
play.

- **Source:** supplied as `Grass-01.png`; provenance not recorded.
- **Licence:** ⚠️ **not settled**, same gap as the wizard pack below and the same
  precedent (`client/fonts/OFL.txt`). Whatever this tileset ships under belongs written
  down next to it before the browser build goes anywhere a player downloads it.
- **Weight:** 21 KB on disk, ~10 KB imported, lossless (`vram_texture_compression` still
  off — #20 still wants a real budget now that arena art exists).
- **Not autotiled yet.** The `Cover`/`Walls` blocks are a hand-picked nine-slice, not a
  terrain set, so edges seam rather than blend. Painting terrain sets onto the tileset in
  the editor is the intended next pass — the whole point of it being a `.tres` and a
  `.tscn` rather than built in code.

## wizard.png

The fighters. One strip of 46 frames, 79×65 each — 3634×65 in total. `wizard_frames.tres`
(a `SpriteFrames` resource) slices it into twelve animations — a six-frame walk and a
four-frame cast for each of down, up, right and left, plus four idle sets that replay the
walk frames slowly — and `client/scenes/fighter.tscn` assigns it to the `Character`
`AnimatedSprite2D` on every fighter. Nothing in code sets a frame up: `Fighter` names an
animation (`Fighter.animation_name`) and calls `play()` on it as the fighter moves
or casts. The six-frame channel set (frames 40–45) is left out of the resource entirely.
Swapping the pack is editing that `.tres` in the SpriteFrames editor.

It carries **posture and heading, and nothing else** — which way you are pointing, whether
you are walking, whether a spell is coming. Health, status, whose body this is and which
spell it is stay `_draw()` calls in palette colours, because every fighter in the arena
wears this same robe and one robe cannot be told from another at a glance.
`docs/art-direction.md` states that rule; `tests/test_fighter_sprite.gd` checks the
heading/posture decision and `tests/test_fighter_frames.gd` re-measures the pack.

- **Source:** a wizard character pack supplied for #26, as a single pre-packed strip.
- **Licence:** ⚠️ **not yet settled.** The repository is MIT and `client/fonts/OFL.txt` is
  the precedent: whatever this pack ships under belongs next to it, named, before this
  goes anywhere a player can download it. Nothing here is UO-derived, so it is a
  paperwork gap rather than a rights problem — but it is still a gap.
- **Weight:** 18 KB on disk, 9 KB imported, which is what actually ships — lighter than
  the single-heading atlas it replaced, which cost 33 KB for a quarter of the animation.
  For scale, the subset display font is 15 KB. `vram_texture_compression` stays off, so
  this is a lossless PNG rather than a compressed texture.

### Shipped exactly as supplied

There is **no packing step**. The pack arrives as a registered atlas on a uniform 79×65
grid, so what ships is the artwork that was handed over, byte for byte. Each frame in
`wizard_frames.tres` is an `AtlasTexture` over a single cell — walk and cast alternate by
heading on the sheet rather than sitting in blocks, so the twelve animations pick out
non-contiguous runs.

### Two things measured rather than assumed

- **The left-facing walk sits about 3.6 px left in its cells.** Everything else registers
  within a pixel. Drawn from one `AnimatedSprite2D.offset` a fighter would hop sideways
  every time it turned left, so the left frames' `AtlasTexture`s carry a `margin` that
  pulls them back into registration. `test_every_heading_stands_in_the_same_place`
  re-measures the committed PNG rather than trusting it.
- **Frames 40–45 are a staff-raised channel** with its own yellow-and-blue sparkle burst,
  and are deliberately unused. The game already announces a cast with the mantra overhead
  and an aura in the colour of the spell being cast; this would say the same thing again,
  in the wrong colour. No animation in `wizard_frames.tres` references them, and
  `test_the_channel_frames_are_left_alone` pins that as a decision.

A cast set is not played on its own clock: `Fighter._update_character_animation` scrubs it
to real cast progress, so a one-second spell and a four-second one show a different pose at
the same moment — the read on how close the spell is to landing.

Replacing the pack means rebuilding `wizard_frames.tres` against the new sheet and
re-measuring. `tests/test_fighter_frames.gd` reads whatever the resource points at, so a
swap that gets the layout wrong fails rather than shipping a fighter who hops, or vanishes
mid-spell.
