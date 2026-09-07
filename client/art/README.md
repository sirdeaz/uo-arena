# Art

## Grass-01.png

The arena. A 512×256 top-down tileset on a 16px grid — grass, a dirt-on-grass autotile,
and a cliff / raised-earth autotile (no buildings or boulders). `grass_tileset.tres`
slices it and marks the cliff tiles `solid`; `client/scenes/arena_ground.tscn` paints
three `TileMapLayer`s from it — `Floor` (grass everywhere), `Walls` (a cliff band on the
four boundary rects, run out past the play edge so no engine-grey shows) and `Cover` (a
raised cliff block on each of the two tents and two rocks). Both client scenes instance
that one ground scene.

**Collision did not move.** `server/arena_map.tscn` still owns every `StaticBody2D`, and
the resolver still raycasts those — a painted cliff blocks nothing on its own. The tiles
are aligned to the colliders by `client/arena_tiles.gd`, rounded **outward** so a shape
is always fully under a solid tile (never invisible cover) at the cost of up to one tile
of overhang, and `tests/test_arena_tiles.gd` fails if a collider is uncovered or a solid
tile drifts into open play. To reshape the arena: move the collider in
`server/arena_map.tscn`, repaint `arena_ground.tscn` to match, and that test keeps the
two honest.

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

The fighters. One strip of 46 frames, 79×65 each — 3634×65 in total. `wizard.tres`
(a `FighterSprite` resource — see `client/fighter_sprite.gd`) points at this PNG and
carries the frame table; `client/scenes/fighter.tscn` assigns that resource to every
fighter, so the sheet is swapped in the inspector, not in code. It draws **four
headings**: a six-frame walk and a four-frame cast for each of down, up, right and left,
plus a six-frame channel set the game does not use.

It carries **posture and heading, and nothing else** — which way you are pointing, whether
you are walking, whether a spell is coming. Health, status, whose body this is and which
spell it is stay `_draw()` calls in palette colours, because every fighter in the arena
wears this same robe and one robe cannot be told from another at a glance.
`docs/art-direction.md` states that rule and `tests/test_fighter_sprite.gd` is where it is
checked.

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
grid, so what ships is the artwork that was handed over, byte for byte, and there is no
script standing between the two that could quietly change it. The frame table in
`wizard.tres` was read off the sheet rather than derived — walk and cast alternate by
heading instead of sitting in blocks, so it is a table and not a stride.

### Two things measured rather than assumed

- **The left-facing walk sits about 3.6 px left in its cells.** Everything else registers
  within a pixel. Drawn from one anchor a fighter would hop sideways every time it turned,
  so the `anchor_*` fields in `wizard.tres` are per heading, and
  `test_every_heading_stands_where_its_anchor_says` re-measures the committed PNG rather
  than trusting them.
- **Frames 40–45 are a staff-raised channel** with its own yellow-and-blue sparkle burst,
  and are deliberately unused. The game already announces a cast with the mantra overhead
  and an aura in the colour of the spell being cast; this would say the same thing again,
  in the wrong colour. `test_the_channel_frames_are_left_alone` pins that as a decision.

Replacing the pack means dropping the new texture into `wizard.tres` and re-measuring
both. The tests read the atlas the resource points at, so a swap that gets the layout
wrong fails rather than shipping a fighter who hops, or vanishes mid-spell.
