"""Builds `icon.ico` from the PNG that `tools/make_windows_icon.gd` rasterises.

Windows wants a real multi-resolution .ico: a single-resolution source scales badly in
the taskbar and in Explorer's large-icon view, which is where a player meets this build
first — on an unsigned executable that already has to argue its way past SmartScreen.

    godot --headless --script tools/make_windows_icon.gd
    python tools/make_windows_icon.py

Needs Pillow. Build tooling; not shipped in any export.
"""

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / ".godot" / "icon-256.png"
OUTPUT = ROOT / "icon.ico"

# The four sizes Windows actually asks for: list view, taskbar, Explorer medium, and
# the 256px one used for large icons and the file properties dialog.
SIZES = [(16, 16), (32, 32), (48, 48), (256, 256)]


def main() -> int:
    if not SOURCE.exists():
        print(
            f"{SOURCE} is missing — run `godot --headless --script "
            "tools/make_windows_icon.gd` first.",
            file=sys.stderr,
        )
        return 1

    with Image.open(SOURCE) as image:
        image.convert("RGBA").save(OUTPUT, format="ICO", sizes=SIZES)

    print(f"{OUTPUT} ({OUTPUT.stat().st_size} bytes, {len(SIZES)} sizes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
