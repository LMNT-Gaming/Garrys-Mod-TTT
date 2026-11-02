<#
    LMNT | TTT2 – Syntaxprüfung aller Lua-Dateien in garrysmod\addons
    Benötigt Node.js. Beim ersten Aufruf wird luaparse lokal in tools\lint installiert.
    Exit-Code 0 = alles in Ordnung, 1 = Syntaxfehler gefunden.
#>

$ErrorActionPreference = "Stop"
$lintDir = Join-Path $PSScriptRoot "lint"
$root = Join-Path (Split-Path -Parent $PSScriptRoot) "garrysmod\addons"

if (-not (Test-Path (Join-Path $lintDir "node_modules\luaparse"))) {
    Push-Location $lintDir
    npm install --no-audit --no-fund | Out-Null
    Pop-Location
}

node (Join-Path $lintDir "check.js") $root
exit $LASTEXITCODE
