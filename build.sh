#!/usr/bin/env sh
# Builds shareable copies of UO Arena.
#
#   ./build.sh              # this machine's native build, plus the browser build
#   ./build.sh --linux      # standalone Linux binary, tarred, ready to send
#   ./build.sh --web        # browser build in build/web, ready to upload
#   ./build.sh --server     # headless dedicated server binary
#
# The Windows equivalent is build.ps1, which builds the .exe instead of the Linux
# binary and otherwise takes the same options.
#
# Needs Godot's export templates for the matching engine version. If they are missing
# the export fails loudly; install them from the editor (Editor > Manage Export
# Templates), or unpack
#
#   https://github.com/godotengine/godot/releases/download/<ver>-stable/Godot_v<ver>-stable_export_templates.tpz
#
# into ~/.local/share/godot/export_templates/<ver>.stable/ on Linux, or
# ~/Library/Application Support/Godot/export_templates/<ver>.stable/ on macOS.

set -eu

cd "$(dirname "$0")"
. ./tools/godot.sh

want_linux=0
want_web=0
want_server=0

if [ "$#" -eq 0 ]; then
    want_linux=1
    want_web=1
fi
for argument in "$@"; do
    case "$argument" in
        --linux)  want_linux=1 ;;
        --web)    want_web=1 ;;
        --server) want_server=1 ;;
        *)
            echo "Unknown option '$argument'. Use --linux, --web or --server." >&2
            exit 2
            ;;
    esac
done

godot=$(find_godot)
require_godot_4 "$godot"
import_project "$godot"

# Godot refuses to export into a directory that does not exist yet.
export_preset() {
    preset=$1
    destination=$2
    mkdir -p "$destination"
    "$godot" --headless --export-release "$preset"
}

# The preview image is a rendered frame, not a drawing, so it cannot be produced by a
# headless run. Returns non-zero if there is no way to get a display.
capture_preview() {
    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a "$godot" --audio-driver Dummy --resolution 1280x720 \
            res://tools/capture_promo_shot.tscn -- --out build/web/og-image.png
    elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        "$godot" --audio-driver Dummy --resolution 1280x720 \
            res://tools/capture_promo_shot.tscn -- --out build/web/og-image.png
    else
        return 1
    fi
}


human_size() {
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --suffix=B "$(wc -c < "$1")"
    else
        wc -c < "$1"
    fi
}

if [ "$want_linux" -eq 1 ]; then
    export_preset "Linux" build/linux

    # Stage with the player-facing readme, then tar. A tarball keeps the executable bit,
    # which a zip would drop and which is the difference between double-clicking and a
    # confused message about permissions.
    rm -rf build/UOArena-linux-x86_64
    mkdir -p build/UOArena-linux-x86_64
    cp build/linux/* build/UOArena-linux-x86_64/
    cp "dist/READ ME FIRST.txt" build/UOArena-linux-x86_64/
    chmod +x build/UOArena-linux-x86_64/UOArena.x86_64

    rm -f build/UOArena-linux-x86_64.tar.gz
    tar -czf build/UOArena-linux-x86_64.tar.gz -C build UOArena-linux-x86_64
    echo "Linux: build/UOArena-linux-x86_64.tar.gz ($(human_size build/UOArena-linux-x86_64.tar.gz))"
fi

# The dedicated-server build is meant to carry collision, not art. Preset 3 excludes the
# whole `client/*` tree, so nothing client-side should reach the PCK. Two project-level
# dependencies ride along and `exclude_filter` cannot drop one: `client/art/Grass-01.png`
# (~21 KB, the shared arena tileset image) and `client/ui/ui_theme.tres` (<1 KB, a
# SystemFont name list named by project.godot's gui/theme/custom). Both are rounding
# errors; anything else under `res://client/`, or a ballooning PCK, is a real leak.
assert_server_pck_stays_lean() {
    pck=$(ls build/server/*.pck 2>/dev/null | head -n1)
    if [ -z "$pck" ]; then
        echo "  error: no server PCK to check" >&2
        exit 1
    fi
    hits=$(strings "$pck" | grep -oP 'res://client/[\w./-]+' \
        | grep -vP '^res://client/(art/Grass-01\.|ui/ui_theme\.tres)' | sort -u || true)
    if [ -n "$hits" ]; then
        echo "  error: the dedicated-server PCK references client/ resources it should not:" >&2
        echo "$hits" >&2
        exit 1
    fi
    bytes=$(wc -c < "$pck")
    if [ "$bytes" -gt 2097152 ]; then
        echo "  error: the dedicated-server PCK is ${bytes} bytes (> 2 MiB)" >&2
        exit 1
    fi
    echo "Server PCK: $(human_size "$pck"), no client resources beyond the arena tileset image"
}

if [ "$want_server" -eq 1 ]; then
    export_preset "Linux Dedicated Server" build/server
    assert_server_pck_stays_lean
    echo "Server: build/server/UOArenaServer.x86_64"
fi

if [ "$want_web" -eq 1 ]; then
    export_preset "Web" build/web

    # The link preview image has to sit next to index.html, because that whole directory
    # is what gets uploaded. It is a real captured frame, so it needs a display — under
    # xvfb where there is one available, and skipped with a warning where there is not.
    capture_preview || echo \
        "  warning: no og-image.png — the page will unfurl without a preview image." >&2

    echo "Web: build/web (upload the whole folder; index.html is the entry point)"
fi
