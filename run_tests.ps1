# Runs the UO Arena test suite headlessly. Exits non-zero if any test fails.
#
#   .\run_tests.ps1

$ErrorActionPreference = "Stop"

$godot = $env:GODOT_BIN
if (-not $godot) {
    $candidates = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
        -Filter "Godot_v*_win64_console.exe" -Recurse -ErrorAction SilentlyContinue
    if ($candidates) { $godot = $candidates[0].FullName }
}

if (-not $godot -or -not (Test-Path $godot)) {
    Write-Error "Godot not found. Set GODOT_BIN to the console executable path."
    exit 1
}

# Keeps global class names (SpellData, Combatant, ...) registered after new scripts land.
& $godot --headless --import | Out-Null
& $godot --headless res://tests/test_main.tscn -- --test
exit $LASTEXITCODE
