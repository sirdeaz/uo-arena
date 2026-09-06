# Launches UO Arena.
#
#   .\run_game.ps1                      # join screen
#   .\run_game.ps1 -Editor              # open the Godot editor instead
#   .\run_game.ps1 -Server              # run headless as a dedicated server
#   .\run_game.ps1 -Connect 10.0.0.4    # join a server directly
#   .\run_game.ps1 -Server -Port 24568  # either of the last two, on another port
#
# The Linux and macOS equivalent is ./run_game.sh, which takes the same forms.

param(
    [switch]$Editor,
    [switch]$Server,
    [string]$Connect,
    [int]$Port
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "tools\Godot.ps1")

$godot = Find-Godot
Assert-Godot4 $godot

$extra = @()
if ($Port) { $extra += @("--port", "$Port") }

if ($Editor) {
    & $godot --editor
} elseif ($Server) {
    & $godot --headless -- --server @extra
} elseif ($Connect) {
    & $godot -- --connect $Connect @extra
} else {
    & $godot -- @extra
}
