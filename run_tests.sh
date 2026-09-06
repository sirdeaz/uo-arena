#!/usr/bin/env sh
# Runs the UO Arena test suite headlessly. Exits non-zero if any test fails.
#
#   ./run_tests.sh
#
# The Windows equivalent is run_tests.ps1.

set -eu

cd "$(dirname "$0")"
. ./tools/godot.sh

godot=$(find_godot)
require_godot_4 "$godot"

# Keeps global class names (SpellData, Combatant, ...) registered after new scripts land.
import_project "$godot"

exec "$godot" --headless res://tests/test_main.tscn -- --test
