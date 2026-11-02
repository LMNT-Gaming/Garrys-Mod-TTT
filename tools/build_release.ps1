<#
    LMNT | TTT2 – Release-Pakete bauen

    dist\LMNT-TTT2-<Version>.zip          komplettes Set (Addons, Configs, Server-Skripte, Tools, Ladebildschirm, Doku)
    dist\LMNT-TTT2-Addons-<Version>.zip   nur garrysmod\ (für bestehende Server)
    dist\SHA256SUMS.txt                   Prüfsummen

    Lokale Dateien (settings.ini, secrets.json, owners.txt, Logs, node_modules, fastdl\www) werden nie gepackt.
    Vorher läuft der Lint; bei Fehlern wird abgebrochen.

    Aufruf:  powershell -ExecutionPolicy Bypass -File tools\build_release.ps1
#>
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
$dist = Join-Path $root "dist"
$stage = Join-Path $dist "stage"

& (Join-Path $PSScriptRoot "lint.ps1")
if ($LASTEXITCODE -ne 0) { throw "Lint fehlgeschlagen – kein Release." }

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

$excludeFiles = @("settings.ini", "secrets.json", "owners.txt", "last_test_console.log", "*.log")
$excludeDirs = @("node_modules", "www", "__pycache__", ".git", ".github", "dist", ".claude")

function Copy-Tree([string]$rel) {
    $src = Join-Path $root $rel
    $dst = Join-Path $stage $rel
    if (Test-Path $src -PathType Leaf) {
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item $src $dst
        return
    }
    robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP /XF $excludeFiles /XD $excludeDirs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy-Fehler bei $rel (Code $LASTEXITCODE)" }
}

foreach ($item in "garrysmod", "server", "tools", "fastdl", "docs", "README.md", "LICENSE", "CHANGELOG.md", "SECURITY.md", "CONTRIBUTING.md", "VERSION") {
    Copy-Tree $item
}

# Sicherheitsnetz: nichts Lokales im Paket
$leaks = Get-ChildItem $stage -Recurse -File | Where-Object { $excludeFiles -contains $_.Name }
if ($leaks) { throw "Lokale Datei im Paket: $($leaks.FullName -join ', ')" }

$full = Join-Path $dist "LMNT-TTT2-$version.zip"
$addons = Join-Path $dist "LMNT-TTT2-Addons-$version.zip"
# Eigene ZIP-Erzeugung: Compress-Archive (PowerShell 5.1) schreibt Backslashes in die Pfade, die Linux-Server falsch entpacken
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
function New-Zip([string]$target, [string]$baseDir, [string]$subDir) {
    $zip = [IO.Compression.ZipFile]::Open($target, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem (Join-Path $baseDir $subDir) -Recurse -File) {
            $entry = $f.FullName.Substring($baseDir.Length).TrimStart('\').Replace('\', '/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }
}
New-Zip $full $stage ""
New-Zip $addons $stage "garrysmod"
Remove-Item $stage -Recurse -Force

$sums = foreach ($z in $full, $addons) {
    "{0}  {1}" -f (Get-FileHash $z -Algorithm SHA256).Hash.ToLower(), (Split-Path $z -Leaf)
}
[IO.File]::WriteAllText((Join-Path $dist "SHA256SUMS.txt"), (($sums -join "`n") + "`n"))

Write-Host ""
Get-ChildItem $dist | ForEach-Object { Write-Host ("  {0,-40} {1,8:N0} KB" -f $_.Name, ($_.Length / 1KB)) }
Write-Host "Release $version gebaut -> $dist" -ForegroundColor Green
