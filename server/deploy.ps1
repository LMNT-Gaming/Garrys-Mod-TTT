<#
    LMNT | TTT2 – Projektdateien in den Server kopieren

    - Spiegelt die LMNT-Addons (fremde Addons im Server bleiben unangetastet)
    - Kopiert server.cfg (Platzhalter aus settings.ini werden ersetzt) und mapcycle.txt
    - Kopiert data/lmnt/workshop.json

    Nach jeder Änderung am Projekt einfach erneut ausführen (Server danach neu starten / Map wechseln).
#>

. "$PSScriptRoot\common.ps1"
$s = Read-LmntSettings

$src = Join-Path $script:ProjectRoot "garrysmod"
$dst = Join-Path (Get-GmodDir $s) "garrysmod"

if (-not (Test-Path $dst)) { throw "Server nicht gefunden unter $dst – zuerst install.ps1 ausführen." }

Write-Step "Addons spiegeln"
foreach ($addon in Get-ChildItem (Join-Path $src "addons") -Directory) {
    $target = Join-Path $dst "addons\$($addon.Name)"
    robocopy $addon.FullName $target /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy-Fehler bei $($addon.Name) (Code $LASTEXITCODE)" }
    Write-Host "  $($addon.Name)"
}

Write-Step "server.cfg schreiben"
$cfg = Get-Content -Raw -Encoding UTF8 (Join-Path $src "cfg\server.cfg")
foreach ($key in "HOSTNAME", "SERVER_PASSWORD", "RCON_PASSWORD", "FASTDL_URL") {
    $cfg = $cfg.Replace("{{$key}}", [string]$s[$key])
}
New-Item -ItemType Directory -Force (Join-Path $dst "cfg") | Out-Null
[IO.File]::WriteAllText((Join-Path $dst "cfg\server.cfg"), $cfg, (New-Object Text.UTF8Encoding $false))

if ($s.RCON_PASSWORD -eq "bitte-aendern-1234") {
    Write-Host "  WARNUNG: Standard-RCON-Passwort! Bitte in settings.ini ändern." -ForegroundColor Yellow
}

$mapcycle = Join-Path $src "cfg\mapcycle.txt"
if (Test-Path $mapcycle) { Copy-Item $mapcycle (Join-Path $dst "cfg\mapcycle.txt") -Force }

Write-Step "Workshop-Liste kopieren"
New-Item -ItemType Directory -Force (Join-Path $dst "data\lmnt") | Out-Null
Copy-Item (Join-Path $src "data\lmnt\workshop.json") (Join-Path $dst "data\lmnt\workshop.json") -Force

Write-Step "Owner-Liste schreiben"
$owners = @(([string]$s.OWNERS) -split "[,;\s]+" | Where-Object { $_ -match '^7656119\d{10}$' })
[IO.File]::WriteAllText((Join-Path $dst "data\lmnt\owners.txt"), (($owners -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
if ($owners.Count -eq 0) {
    Write-Host "  WARNUNG: OWNERS in settings.ini ist leer – Owner per Konsole: lmnt setrankid <SteamID64> owner" -ForegroundColor Yellow
} else {
    Write-Host "  $($owners.Count) Owner"
}

Write-Host ""
Write-Host "Deploy abgeschlossen -> $dst" -ForegroundColor Green
