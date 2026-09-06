#!/usr/bin/env python3
"""Packs a loose character animation pack into the atlas `Fighter` draws from.

    python3 tools/pack_character_sprites.py <pack directory> client/art/dark_mage.png

The pack this was written for ships one PNG per frame in `Idle/`, `Walk/` and
`Attack/` folders, and those frames are *not* registered against each other: the
attack frames sit on a 74 px canvas rather than 64, and each set puts the character
at a different place on it. Drawn straight, a fighter would jump sideways the moment
it stopped walking.

So registration happens here, once, rather than as a table of per-animation fudge
offsets in the client:

  * The anchor of a frame is where the character *stands* — the horizontal centroid
    of the bottom 16 rows of opaque pixels (the robe hem, which is stable while the
    staff and sleeves swing around), and the row below the lowest opaque pixel.
  * That anchor is averaged **per animation, not per frame**, so the bob of a walk
    cycle and the lean of a cast survive intact and only the drift between sets is
    corrected. Rounding each frame to its own anchor would flatten the animation.
  * Every frame is then blitted into a fixed cell with the animation's anchor at
    `ANCHOR`, so the client can draw any frame of any row at the same offset.

`Attack/attack_04.png` is deliberately left out; `docs/art-direction.md` says why.

Requires Pillow. It is not a dependency of the game — the atlas is committed, and
this script exists so the next pack can be registered the same way rather than by
eye.
"""

import statistics
import sys
from pathlib import Path

from PIL import Image

# One cell per frame, in the order the client's `FighterSprite.Anim` enum expects.
ROWS = [
    ("idle", ["Idle/idle_01.png", "Idle/idle_02.png", "Idle/idle_03.png", "Idle/idle_04.png"]),
    ("walk", ["Walk/walk_01.png", "Walk/walk_02.png", "Walk/walk_03.png", "Walk/walk_04.png"]),
    ("cast", ["Attack/attack_01.png", "Attack/attack_02.png", "Attack/attack_03.png"]),
]

CELL = (64, 64)

# Where the character's standing point lands inside a cell. Left of centre because the
# staff reaches further right than the robe reaches left; high enough that the raised
# staff of the last cast frame still fits above the head.
ANCHOR = (26, 61)

# Alpha at or below this is treated as nothing. The pack's edges are hard, so this only
# guards against stray near-transparent pixels dragging an anchor sideways.
ALPHA_FLOOR = 16

# Rows of the hem used to find where the character stands.
HEM_ROWS = 16


def opaque_pixels(image):
    pixels = image.load()
    width, height = image.size
    return [
        (x, y)
        for y in range(height)
        for x in range(width)
        if pixels[x, y][3] > ALPHA_FLOOR
    ]


def frame_anchor(image):
    """Where this one frame's character stands, as (x, y)."""
    opaque = opaque_pixels(image)
    if not opaque:
        raise SystemExit("a frame is entirely transparent")
    bottom = max(y for _, y in opaque)
    hem = [x for x, y in opaque if y > bottom - HEM_ROWS]
    return statistics.fmean(hem), bottom + 1


def pack(pack_dir, out_path):
    columns = max(len(files) for _, files in ROWS)
    atlas = Image.new("RGBA", (CELL[0] * columns, CELL[1] * len(ROWS)), (0, 0, 0, 0))

    for row, (name, files) in enumerate(ROWS):
        frames = [Image.open(pack_dir / f).convert("RGBA") for f in files]
        anchors = [frame_anchor(frame) for frame in frames]
        # One anchor for the whole animation: see the module docstring.
        anchor_x = round(statistics.fmean(x for x, _ in anchors))
        anchor_y = round(statistics.median(y for _, y in anchors))
        print("%-5s anchor (%d, %d) from %d frames" % (name, anchor_x, anchor_y, len(frames)))

        for column, frame in enumerate(frames):
            left = column * CELL[0] + ANCHOR[0] - anchor_x
            top = row * CELL[1] + ANCHOR[1] - anchor_y
            box = frame.getbbox()
            if (
                left + box[0] < column * CELL[0]
                or left + box[2] > (column + 1) * CELL[0]
                or top + box[1] < row * CELL[1]
                or top + box[3] > (row + 1) * CELL[1]
            ):
                raise SystemExit(
                    "%s does not fit a %dx%d cell at anchor %s — widen CELL"
                    % (files[column], CELL[0], CELL[1], ANCHOR)
                )
            atlas.alpha_composite(frame, (left, top))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(out_path, optimize=True)
    print("wrote %s (%d bytes, %dx%d)" % (out_path, out_path.stat().st_size, *atlas.size))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    pack(Path(sys.argv[1]), Path(sys.argv[2]))
