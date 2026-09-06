# Art

## wizard.png

The fighters. One strip of 46 frames, 79×65 each — 3634×65 in total — read by
`client/fighter_sprite.gd`. It draws **four headings**: a six-frame walk and a four-frame
cast for each of down, up, right and left, plus a six-frame channel set the game does not
use.

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
`client/fighter_sprite.gd` was read off the sheet rather than derived — walk and cast
alternate by heading instead of sitting in blocks, so it is a table and not a stride.

### Two things measured rather than assumed

- **The left-facing walk sits about 3.6 px left in its cells.** Everything else registers
  within a pixel. Drawn from one anchor a fighter would hop sideways every time it turned,
  so `FighterSprite.ANCHORS` is per heading, and
  `test_every_heading_stands_where_its_anchor_says` re-measures the committed PNG rather
  than trusting the constants.
- **Frames 40–45 are a staff-raised channel** with its own yellow-and-blue sparkle burst,
  and are deliberately unused. The game already announces a cast with the mantra overhead
  and an aura in the colour of the spell being cast; this would say the same thing again,
  in the wrong colour. `test_the_channel_frames_are_left_alone` pins that as a decision.

Replacing the pack means re-measuring both. The tests read the atlas, so a swap that gets
the layout wrong fails rather than shipping a fighter who hops, or vanishes mid-spell.
