# Runs the UO Arena test suite headlessly. Exits non-zero if any test fails.
#
#   .\run_tests.ps1
#
# The Linux and macOS equivalent is ./run_tests.sh.

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "tools\Godot.ps1")

$godot = Find-Godot -Console
Assert-Godot4 $godot

# Keeps global class names (SpellData, Combatant, ...) registered after new scripts land.
Import-Project $godot

& $godot --headless res://tests/test_main.tscn -- --test
exit $LASTEXITCODE
