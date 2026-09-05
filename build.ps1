# Builds shareable copies of UO Arena.
#
#   .\build.ps1              # this machine's native build, plus the browser build
#   .\build.ps1 -Windows     # standalone .exe, zipped, ready to send
#   .\build.ps1 -Web         # browser build in build\web, ready to upload
#   .\build.ps1 -Server      # headless dedicated server binary
#
# The Linux and macOS equivalent is ./build.sh, which builds the Linux binary instead of
# the .exe and otherwise takes the same options.
#
# Needs Godot's export templates for the matching engine version. If they are missing
# the export fails loudly; install them from the editor (Editor > Manage Export
# Templates), or unpack
#
#   https://github.com/godotengine/godot/releases/download/<ver>-stable/Godot_v<ver>-stable_export_templates.tpz
#
# into %APPDATA%\Godot\export_templates\<ver>.stable\

param(
    [switch]$Windows,
    [switch]$Web,
    [switch]$Server
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "tools\Godot.ps1")

if (-not $Windows -and -not $Web -and -not $Server) { $Windows = $true; $Web = $true }

$godot = Find-Godot -Console
Assert-Godot4 $godot
Import-Project $godot

$root = $PSScriptRoot

# Godot refuses to export into a directory that does not exist yet.
function Export-Preset {
    param([string]$Preset, [string]$Destination)

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $output = & $godot --headless --export-release $Preset 2>&1
    $output | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "$Preset export failed." }
    return $output
}

if ($Windows) {
    $out = Join-Path $root "build\windows"
    $output = Export-Preset "Windows Desktop" $out

    # Godot needs rcedit to stamp the icon onto the .exe, and it is configured in
    # Editor Settings rather than anywhere this repo controls. Without it the export
    # succeeds and quietly ships an executable wearing the default Godot logo — on an
    # unsigned build that already has to argue its way past SmartScreen, which is the
    # worst possible first impression. Refuse to ship that silently.
    if ($output -match "rcedit") {
        throw @"
The export could not apply icon.ico to the executable, so it would ship with the
default Godot icon.

Godot needs the rcedit tool for this. Download rcedit-x64.exe from
https://github.com/electron/rcedit/releases and point Godot at it in
Editor Settings > Export > Windows > Rcedit, then run this script again.
"@
    }

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

if ($Server) {
    Export-Preset "Linux Dedicated Server" (Join-Path $root "build\server") | Out-Null
    "Server: build\server\UOArenaServer.x86_64"
}

if ($Web) {
    $out = Join-Path $root "build\web"
    Export-Preset "Web" $out | Out-Null

    # The link preview image has to sit next to index.html, because that whole directory
    # is what gets uploaded. It is a real captured frame, so unlike everything else here
    # it needs a window rather than a headless run.
    & $godot --resolution 1280x720 res://tools/capture_promo_shot.tscn `
        -- --out build/web/og-image.png 2>&1 | Out-Null
    if (-not (Test-Path (Join-Path $out "og-image.png"))) {
        Write-Warning "No og-image.png — the page will unfurl without a preview image."
    }

    "Web: $out (upload the whole folder; index.html is the entry point)"
}
