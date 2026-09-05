# Locates a Godot 4 executable. Dot-sourced by run_game.ps1, run_tests.ps1 and
# build.ps1 so the three of them cannot drift apart, which is what happened when each
# carried its own copy of the winget glob.
#
# Order: $env:GODOT_BIN, then godot4/godot on PATH, then the winget install location.
# The PATH step is what makes the same command work on Linux and Windows; the winget
# fallback is here because `winget install GodotEngine.GodotEngine` does not put Godot
# on PATH.

function Find-Godot {
    param([switch]$Console)

    if ($env:GODOT_BIN) {
        if (-not (Test-Path $env:GODOT_BIN)) {
            throw "GODOT_BIN is set to '$env:GODOT_BIN', which does not exist."
        }
        return $env:GODOT_BIN
    }

    foreach ($name in @("godot4", "godot")) {
        $onPath = Get-Command $name -ErrorAction SilentlyContinue
        if ($onPath) { return $onPath.Source }
    }

    # The console build writes to stdout, which the test and build scripts need; the
    # windowed one is nicer to launch the game with.
    $filter = if ($Console) { "Godot_v*_win64_console.exe" } else { "Godot_v*_win64.exe" }
    $found = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
        -Filter $filter -Recurse -ErrorAction SilentlyContinue
    if ($found) { return $found[0].FullName }

    throw @'
Godot 4 not found.

Install it and make sure godot.exe is on your PATH, or install it with

  winget install GodotEngine.GodotEngine

which this script will then find on its own. Or set GODOT_BIN:

  $env:GODOT_BIN = "C:\path\to\Godot.exe"
'@
}

# Fails with a readable message rather than letting a Godot 3 binary produce a cascade
# of parse errors in files it cannot understand.
function Assert-Godot4 {
    param([string]$Godot)

    $version = (& $Godot --version 2>$null | Select-Object -First 1)
    if ($version -notmatch '^4\.') {
        throw "'$Godot' reports version '$version', but this project needs Godot 4."
    }
}

# CI does this and the old scripts did not: the first import always reports errors for
# classes that are not registered yet, and the second pass is the one that has to be
# clean. On a fresh clone a single import fails on unregistered global classes.
function Import-Project {
    param([string]$Godot)

    & $Godot --headless --import 2>&1 | Out-Null
    & $Godot --headless --import 2>&1 | Out-Null
}
