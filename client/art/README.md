# Art

## dark_mage.png

The fighters. One 256×192 atlas: four idle frames, four walk frames, three cast frames,
64×64 each, read by `client/fighter_sprite.gd`.

It carries **posture and nothing else** — standing, walking, winding up a spell. Health,
status, whose body this is and which spell is coming stay `_draw()` calls in palette
colours, because every fighter in the arena wears this same hooded robe and a robe cannot
be told from another robe at a glance. `docs/art-direction.md` states that rule and
`tests/test_fighter_sprite.gd` is where it is checked.

- **Source:** a `Dark_Mage_64x64_Pack` supplied for this change — 16 loose PNGs under
  `Idle/`, `Walk/` and `Attack/`.
- **Licence:** ⚠️ **not yet settled.** The repository is MIT and `client/fonts/OFL.txt` is
  the precedent: whatever this pack ships under belongs next to it, named, before this
  goes anywhere a player can download it. Nothing here is UO-derived, so it is a
  paperwork gap rather than a rights problem — but it is still a gap.
- **Weight:** 33 KB on disk, 26 KB imported, which is what actually ships. For scale, the
  subset display font is 15 KB. `vram_texture_compression` stays off, so this is a
  lossless PNG rather than a compressed texture — right for a 256×192 atlas of pixel art,
  and worth revisiting when the arena itself gets textures.

One frame of the pack is deliberately not in the atlas:

- **`Attack/attack_04.png`** — a right-facing burst of purple energy. The game already
  draws a release, in the colour of the spell that was actually cast, and this would put a
  second one on top of it that always fires to the right and always means nothing.

Rebuild the atlas from a pack laid out the same way:

```sh
pip install pillow
python3 tools/pack_character_sprites.py path/to/Dark_Mage_64x64_Pack client/art/dark_mage.png
```

The script registers the frames — the raw pack's animations each stand somewhere
different on canvases of different widths, and drawn straight from it a fighter jumps
sideways the moment it stops walking. Do not hand-place frames into the atlas; the test
that measures registration is there to catch exactly that.
