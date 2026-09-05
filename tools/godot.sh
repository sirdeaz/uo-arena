# Locates a Godot 4 binary. Sourced by run_game.sh, run_tests.sh and build.sh so the
# three of them cannot drift apart the way the PowerShell copies did.
#
# Order: $GODOT_BIN, then godot4/godot on PATH. That covers a distro package
# (`pacman -S godot` puts `godot` straight on PATH) without any environment set up by
# hand, and lets anyone override it for a self-built or downloaded engine.
#
# Flatpak is deliberately not searched. `org.godotengine.Godot` is sandboxed: it needs
# `flatpak run` rather than a binary path, and without explicit --filesystem grants it
# cannot see the project directory or write build/. Set GODOT_BIN to a wrapper script if
# you want to use it anyway.

find_godot() {
    if [ -n "${GODOT_BIN:-}" ]; then
        if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
            echo "GODOT_BIN is set to '$GODOT_BIN', which is not executable." >&2
            return 1
        fi
        printf '%s\n' "$GODOT_BIN"
        return 0
    fi

    # godot4 first: on distros that ship both, `godot` may still be Godot 3.
    for candidate in godot4 godot; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done

    cat >&2 <<'MESSAGE'
Godot 4 not found.

Install it so that `godot` or `godot4` is on your PATH:

  Arch / Omarchy   sudo pacman -S godot
  Debian / Ubuntu  sudo apt install godot4     (or download from godotengine.org)
  macOS            brew install --cask godot

Or point GODOT_BIN at the executable:

  GODOT_BIN=/path/to/godot ./run_tests.sh
MESSAGE
    return 1
}

# Fails with a readable message rather than letting a Godot 3 binary produce a cascade
# of parse errors in files it cannot understand.
require_godot_4() {
    version=$("$1" --version 2>/dev/null | head -n 1)
    case "$version" in
        4.*) return 0 ;;
        *)
            echo "'$1' reports version '${version:-unknown}', but this project needs Godot 4." >&2
            return 1
            ;;
    esac
}

# CI does this and the old scripts did not: the first import always reports errors for
# classes that are not registered yet, and the second pass is the one that has to be
# clean. On a fresh clone a single import fails on unregistered global classes.
import_project() {
    "$1" --headless --import >/dev/null 2>&1 || true
    "$1" --headless --import >/dev/null
}
