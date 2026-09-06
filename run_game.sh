#!/usr/bin/env sh
# Launches UO Arena.
#
#   ./run_game.sh                      # join screen
#   ./run_game.sh --editor             # open the Godot editor instead
#   ./run_game.sh --server             # run headless as a dedicated server
#   ./run_game.sh --connect 10.0.0.4   # join a server directly
#   ./run_game.sh --server --port 24568   # either of the last two, on another port
#
# The Windows equivalent is run_game.ps1, which takes the same forms.

set -eu

cd "$(dirname "$0")"
. ./tools/godot.sh

editor=0
server=0
connect=""
port=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --editor)  editor=1 ;;
        --server)  server=1 ;;
        --connect)
            [ "$#" -ge 2 ] || { echo "--connect needs an address." >&2; exit 2; }
            connect=$2
            shift
            ;;
        --port)
            [ "$#" -ge 2 ] || { echo "--port needs a number." >&2; exit 2; }
            port=$2
            shift
            ;;
        *)
            echo "Unknown option '$1'. Use --editor, --server, --connect or --port." >&2
            exit 2
            ;;
    esac
    shift
done

godot=$(find_godot)
require_godot_4 "$godot"

# Everything after `--` is passed through to the game rather than the engine.
set --
[ -n "$port" ] && set -- "$@" --port "$port"

if [ "$editor" -eq 1 ]; then
    exec "$godot" --editor
elif [ "$server" -eq 1 ]; then
    exec "$godot" --headless -- --server "$@"
elif [ -n "$connect" ]; then
    exec "$godot" -- --connect "$connect" "$@"
else
    exec "$godot" -- "$@"
fi
