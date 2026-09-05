#!/usr/bin/env sh
# Launches UO Arena. Boots straight into the local test scene.
#
#   ./run_game.sh
#   ./run_game.sh --editor    # open the Godot editor instead
#   ./run_game.sh --server    # run headless as a dedicated server
#
# The Windows equivalent is run_game.ps1, which takes the same three forms.

set -eu

cd "$(dirname "$0")"
. ./tools/godot.sh

godot=$(find_godot)
require_godot_4 "$godot"

case "${1:-}" in
    --editor) exec "$godot" --editor ;;
    --server) exec "$godot" --headless -- --server ;;
    "")       exec "$godot" ;;
    *)
        echo "Unknown option '$1'. Use --editor or --server." >&2
        exit 2
        ;;
esac
