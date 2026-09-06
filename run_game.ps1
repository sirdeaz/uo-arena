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

# Keeps global class names (ArenaServer, NetProtocol, ...) registered after new scripts
# land, the way run_tests.ps1 and build.ps1 already do. Without it, launching straight
# after a pull that added a class_name dies on parse errors in the autoloads. The editor
# rescans the filesystem when it opens, so it is the one path that does not need this.
if (-not $Editor) { Import-Project $godot }

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
