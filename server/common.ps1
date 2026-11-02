# Gemeinsame Helfer für alle LMNT-Serverskripte
$ErrorActionPreference = "Stop"

$script:ServerScriptDir = $PSScriptRoot
$script:ProjectRoot = Split-Path -Parent $PSScriptRoot

function Read-LmntSettings {
    $path = Join-Path $script:ServerScriptDir "settings.ini"
    if (-not (Test-Path $path)) {
        $example = Join-Path $script:ServerScriptDir "settings.example.ini"
        if (-not (Test-Path $example)) { throw "settings.ini nicht gefunden: $path" }
        Copy-Item $example $path
        Write-Host "settings.ini aus settings.example.ini angelegt – bitte SERVER_DIR, RCON_PASSWORD und OWNERS anpassen." -ForegroundColor Yellow
    }

    $settings = @{}
    foreach ($line in Get-Content -Encoding UTF8 $path) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith(";") -or $trimmed.StartsWith("#")) { continue }
        $idx = $trimmed.IndexOf("=")
        if ($idx -lt 1) { continue }
        $settings[$trimmed.Substring(0, $idx).Trim()] = $trimmed.Substring($idx + 1).Trim()
    }
    return $settings
}

function Write-Step([string]$text) {
    Write-Host ""
    Write-Host "==> $text" -ForegroundColor Cyan
}

function Get-GmodDir($settings) { Join-Path $settings.SERVER_DIR "gmod" }
function Get-SteamCmd($settings) { Join-Path $settings.SERVER_DIR "steamcmd\steamcmd.exe" }
