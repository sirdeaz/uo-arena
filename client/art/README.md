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
- **Licence:** ⚠️ **not settled**, same precedent as `client/fonts/OFL.txt`. Whatever
  this tileset ships under belongs written down next to it before the browser build
  goes anywhere a player downloads it.
- **Weight:** 21 KB on disk, ~10 KB imported, lossless (`vram_texture_compression` still
  off — #20 still wants a real budget now that arena art exists).
- **Not autotiled yet.** The `Cover`/`Walls` blocks are a hand-picked nine-slice, not a
  terrain set, so edges seam rather than blend. Painting terrain sets onto the tileset in
  the editor is the intended next pass — the whole point of it being a `.tres` and a
  `.tscn` rather than built in code.

## mage_idle.png / mage_walk_down.png / mage_walk_right.png / mage_walk_up.png

The fighters. Four separate 560×70 strips, eight 70×70 frames each — one per animation,
not one shared atlas. `mage_frames.tres` (a `SpriteFrames` resource) names them `idle`,
`walk_down`, `walk_right` and `walk_up`, and `client/scenes/fighter.tscn` assigns it to
the `Character` `AnimatedSprite2D` on every fighter. Nothing in code sets a frame up:
`Fighter` names an animation (`Fighter.animation_name`) and calls `play()` on it as the
fighter moves. Swapping the pack is editing that `.tres` in the SpriteFrames editor.

It carries **posture and heading, and nothing else** — which way you are pointing, whether
you are walking. Health, status, whose body this is and which spell it is stay `_draw()`
calls in palette colours, because every fighter in the arena wears this same robe and one
robe cannot be told from another at a glance. `docs/art-direction.md` states that rule;
`tests/test_fighter_sprite.gd` checks the heading/posture decision and
`tests/test_fighter_frames.gd` re-measures the pack.

- **Source:** self-authored, drawn in Aseprite for this project. Not sourced from an
  asset pack or extracted game files, despite the `uo_`-prefixed working names it
  arrived under — confirmed and renamed before landing here.
- **Licence:** settled. Original art, owned the same way the rest of this repository's
  code is — no `client/fonts/OFL.txt`-style third-party note needed, unlike the tileset
  above.
- **Weight:** four textures rather than one, so compare against the pack they replaced
  by total: was 18 KB / 9 KB imported for one 3634×65 strip; is a few separate small
  strips instead. `vram_texture_compression` stays off, so these are lossless PNGs.

### Two headings this pack does not draw

- **No dedicated left-facing walk.** `Fighter.animation_name` hands back `walk_right`'s
  own name for `LEFT`, and `Fighter.should_flip_h` mirrors it via
  `AnimatedSprite2D.flip_h`. This is safe *because* `Character.centered = true` in
  `fighter.tscn` with no asymmetric offset — a centred sprite mirrors around its own
  local origin, so flipping it can't make a fighter hop sideways the way the old pack's
  uncorrected left set once did. `tests/test_fighter_sprite.gd` checks the mirroring
  decision; `tests/test_fighter_frames.gd`'s registration check compares the three real
  walk headings against each other with a wider tolerance than the old pack needed —
  this is three independently drawn poses, not one strip sliced four ways, so some
  natural stance variance between headings is the art, not a slicing bug.
- **No cast set.** `Fighter.Anim.CAST` and the scrub-to-cast-progress logic in
  `_update_character_animation` are still there, unremoved — they were kept dormant on
  purpose rather than deleted, gated on `SpriteFrames.has_animation`, so a future pack
  that adds `cast_down`/`cast_up`/`cast_right`/`cast_left` back reactivates them with no
  further code change. Until then, casting causes no visible change to the body
  animation — the mantra overhead and the cast aura are what say a spell is coming.

Replacing the pack means rebuilding `mage_frames.tres` against the new sheets and
re-measuring `Character.offset` and `FighterChrome.head_top`/`chest` against the new
art's own proportions. `tests/test_fighter_frames.gd` reads whatever the resource points
at, so a swap that gets the layout wrong fails rather than shipping a fighter who hops or
vanishes mid-walk.

## shadow.png

The ground shadow every fighter stands in — a small decal, `Sprite2D`-authored as the
first child of `Fighter` in `client/scenes/fighter.tscn`, `z_index = -1` so it still
paints under the identity rim `Fighter._draw_footing()` draws in code (see
`docs/art-direction.md` for why that rim has to stay procedural while the shadow
underneath it didn't).

- **Source / Licence:** self-authored alongside the mage pack above — same settled
  status.
- Replaced a `draw_circle` fill that carried no meaning of its own
  (`client/palette.gd`'s `BODY_RING_ALPHA` doc comment called it "the weaker of the two
  on purpose") — the one part of `Fighter`'s look that wasn't yet an authored asset like
  everything else on the node.
