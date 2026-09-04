# Builds shareable copies of UO Arena.
#
#   .\build.ps1              # both targets
#   .\build.ps1 -Windows     # standalone .exe, zipped, ready to send
#   .\build.ps1 -Web         # browser build in build/web, ready to upload
#
# Needs Godot's export templates installed for the matching engine version. If they
# are missing the export fails loudly; install them from the editor
# (Editor > Manage Export Templates) or with:
#
#   https://github.com/godotengine/godot/releases/download/<ver>-stable/Godot_v<ver>-stable_export_templates.tpz
#
# unzipped into %APPDATA%\Godot\export_templates\<ver>.stable\

param(
    [switch]$Windows,
    [switch]$Web
)

$ErrorActionPreference = "Stop"

if (-not $Windows -and -not $Web) { $Windows = $true; $Web = $true }

$godot = $env:GODOT_BIN
if (-not $godot) {
    $found = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
        -Filter "Godot_v*_win64_console.exe" -Recurse -ErrorAction SilentlyContinue
    if ($found) { $godot = $found[0].FullName }
}
if (-not $godot -or -not (Test-Path $godot)) {
    Write-Error "Godot not found. Set GODOT_BIN to the console executable path."
    exit 1
}

$root = $PSScriptRoot
& $godot --headless --import | Out-Null

if ($Windows) {
    $out = Join-Path $root "build\windows"
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    & $godot --headless --export-release "Windows Desktop"
    if ($LASTEXITCODE -ne 0) { Write-Error "Windows export failed."; exit 1 }

    # Stage with the player-facing readme, then zip.
    $stage = Join-Path $root "build\UOArena-win64"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Get-ChildItem $out -File | ForEach-Object {
        Copy-Item $_.FullName -Destination (Join-Path $stage $_.Name)
    }
    Copy-Item (Join-Path $root "dist\READ ME FIRST.txt") -Destination $stage

    $zip = Join-Path $root "build\UOArena-win64.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
    "Windows: {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB)
}

if ($Web) {
    $out = Join-Path $root "build\web"
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    & $godot --headless --export-release "Web"
    if ($LASTEXITCODE -ne 0) { Write-Error "Web export failed."; exit 1 }
    "Web: $out (upload the whole folder; index.html is the entry point)"
}
