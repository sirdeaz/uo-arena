# Launches UO Arena. Boots straight into the local test scene.
#
#   .\run_game.ps1
#   .\run_game.ps1 -Editor    # open the Godot editor instead
#   .\run_game.ps1 -Server    # run headless as a dedicated server

param(
    [switch]$Editor,
    [switch]$Server
)

$ErrorActionPreference = "Stop"

$godot = $env:GODOT_BIN
if (-not $godot) {
    $candidates = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
        -Filter "Godot_v*_win64.exe" -Recurse -ErrorAction SilentlyContinue
    if ($candidates) { $godot = $candidates[0].FullName }
}

if (-not $godot -or -not (Test-Path $godot)) {
    Write-Error "Godot not found. Set GODOT_BIN to the Godot executable path."
    exit 1
}

if ($Editor) {
    & $godot --editor
} elseif ($Server) {
    & $godot --headless -- --server
} else {
    & $godot
}
