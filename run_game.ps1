# Launches UO Arena. Boots straight into the local test scene.
#
#   .\run_game.ps1
#   .\run_game.ps1 -Editor    # open the Godot editor instead
#   .\run_game.ps1 -Server    # run headless as a dedicated server
#
# The Linux and macOS equivalent is ./run_game.sh, which takes the same three forms.

param(
    [switch]$Editor,
    [switch]$Server
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "tools\Godot.ps1")

$godot = Find-Godot
Assert-Godot4 $godot

if ($Editor) {
    & $godot --editor
} elseif ($Server) {
    & $godot --headless -- --server
} else {
    & $godot
}
