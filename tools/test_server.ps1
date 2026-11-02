<#
    LMNT | TTT2 – automatischer Server-Integrationstest

    1. Lint aller Lua-Dateien
    2. deploy.ps1
    3. Startet srcds mit -condebug auf einer Test-Map (ohne Collection, nutzt die GMA aus download_workshop.ps1)
    4. Wartet auf den Boot, fügt per RCON Bots hinzu, führt LMNT-Befehle aus (als Konsole)
    5. Wartet auf Rundenstart, slayt alle (Death-Hooks) und wartet auf Rundenende
    6. Wertet console.log aus: Lua-Fehler -> FAIL; Pflicht-Meldungen fehlen -> FAIL
    7. Beendet den Server wieder

    Aufruf:  powershell -ExecutionPolicy Bypass -File tools\test_server.ps1 [-Map ttt_minecraft_b5] [-Bots 6]
#>
param(
    [string]$Map = "ttt_minecraft_b5",
    [int]$Bots = 6,
    [int]$BootTimeout = 180
)

. "$PSScriptRoot\..\server\common.ps1"
$s = Read-LmntSettings
$gmod = Get-GmodDir $s
$log = Join-Path $gmod "garrysmod\console.log"
$python = (Get-Command python).Source
$rcon = Join-Path $PSScriptRoot "rcon.py"
$failures = New-Object System.Collections.Generic.List[string]

$script:rconLog = New-Object System.Text.StringBuilder
function Invoke-Rcon([string[]]$cmds) {
    $out = & $python -I $rcon @cmds 2>&1 | Out-String
    Write-Host $out
    [void]$script:rconLog.Append($out)
    return $out
}

function Wait-Log([string]$pattern, [int]$timeout) {
    $deadline = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path $log) -and (Select-String -Path $log -Pattern $pattern -Quiet)) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

Write-Step "Lint"
& "$PSScriptRoot\lint.ps1"
if ($LASTEXITCODE -ne 0) { throw "Lint fehlgeschlagen – Test abgebrochen." }

Write-Step "Deploy"
& "$PSScriptRoot\..\server\deploy.ps1" | Out-Null

if (Get-Process srcds -ErrorAction SilentlyContinue) { throw "srcds läuft bereits – bitte beenden." }
if (Test-Path $log) { Remove-Item $log -Force }

Write-Step "Starte Testserver ($Map, $Bots Bots)"
# -usercon: ohne diesen Parameter nimmt der GMod-Dedicated-Server keine TCP-RCON-Verbindungen an
$srvArgs = "-console -condebug -usercon -game garrysmod -port $($s.PORT) +maxplayers 16 +gamemode terrortown +map $Map +sv_lan 1"
$proc = Start-Process -FilePath (Join-Path $gmod "srcds.exe") -ArgumentList $srvArgs -WorkingDirectory $gmod -PassThru -WindowStyle Minimized

try {
    if (-not (Wait-Log "Phase: ready" $BootTimeout)) { $failures.Add("LMNT hat die Phase ready nicht erreicht (Timeout $BootTimeout s)") }
    Start-Sleep -Seconds 5

    Write-Step "RCON: Bots und LMNT-Befehle"
    $out = Invoke-Rcon (@("lmnt status", "lmnt modules", "lmnt who", "lmnt special") + (1..$Bots | ForEach-Object { "bot" }))
    if ($out -match "RCON-Fehler") { $failures.Add("RCON nicht erreichbar") }

    Write-Step "Unit-Tests auf dem Server"
    $testOut = Invoke-Rcon @("lmnt test")
    if ($testOut -match "LMNT-TESTS: (\d+) bestanden, (\d+) fehlgeschlagen") {
        if ([int]$Matches[2] -gt 0) { $failures.Add("$($Matches[2]) Unit-Test(s) fehlgeschlagen") }
    } else {
        $failures.Add("Unit-Tests lieferten kein Ergebnis")
    }

    Write-Step "Integrationen"
    $intOut = Invoke-Rcon @("lmnt integrations", "lmnt integration ttt2 test", "lmnt conflicts", "lmnt compatmatrix")
    if ($intOut -notmatch "Integrationstests ttt2: \d+ bestanden, 0 fehlgeschlagen") { $failures.Add("TTT2-Integrationstests nicht bestanden") }

    Write-Step "Modul-Umschaltung zur Laufzeit"
    $modOut = Invoke-Rcon @("lmnt module ttt.stats aus", "lmnt modules", "lmnt hooks", "lmnt module ttt.stats an", "lmnt modules")
    if ($modOut -notmatch "ttt.pointshop: blocked|blocked\s+ttt.pointshop") { Write-Host "  (Hinweis: Kaskade ttt.stats -> ttt.pointshop im Output prüfen)" -ForegroundColor Yellow }

    # ttt_firstpreptime (server.cfg) = 60 s bis zur ersten Runde
    Write-Step "Warte auf Rundenstart (ca. 75 s)"
    Start-Sleep -Seconds 75

    Invoke-Rcon @("lmnt who", "lmnt slay *", "lmnt stats", "lmnt top") | Out-Null
    Start-Sleep -Seconds 25
    Invoke-Rcon @("lmnt roundrestart", "lmnt logs 15") | Out-Null
    Start-Sleep -Seconds 10
}
finally {
    Write-Step "Beende Testserver"
    Invoke-Rcon @("quit") | Out-Null
    Start-Sleep -Seconds 5
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}

Write-Step "Auswertung console.log"
$content = if (Test-Path $log) { Get-Content $log } else { @() }

$required = @(
    @{ Name = "Core geladen";        Pattern = "Modul geladen: core" },
    @{ Name = "Admin geladen";       Pattern = "Modul geladen: admin" },
    @{ Name = "Alle Module gestartet"; Pattern = "\[LMNT\] (\d+)/\1 Module aktiv" },
    @{ Name = "Phase ready";         Pattern = "Phase: ready" },
    @{ Name = "Workshop registriert"; Pattern = "Workshop-Downloads registriert" },
    @{ Name = "FastDL registriert";  Pattern = "FastDL-Dateien registriert" }
)
if ($content | Select-String -Pattern "TTT2 wurde nicht erkannt" -Quiet) {
    Write-Host "  [FAIL] TTT2 nicht aktiv (klassisches TTT geladen?)" -ForegroundColor Red
    $failures.Add("TTT2 nicht aktiv")
} else {
    Write-Host "  [OK]   TTT2 erkannt" -ForegroundColor Green
}

# Unbekannte Befehle aus server.cfg = Scheinkonfiguration (mp_friendlyfire kommt von GMod/TTT2 selbst)
$unknown = $content | Select-String -Pattern '^Unknown command "([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value } |
    Where-Object { $_ -ne "mp_friendlyfire" } | Sort-Object -Unique
if ($unknown) {
    Write-Host "  [FAIL] Unbekannte ConVars/Befehle: $($unknown -join ', ')" -ForegroundColor Red
    $failures.Add("Unbekannte ConVars in der Config: $($unknown -join ', ')")
} else {
    Write-Host "  [OK]   server.cfg ohne unbekannte Befehle" -ForegroundColor Green
}

foreach ($r in $required) {
    if ($content | Select-String -Pattern $r.Pattern -Quiet) { Write-Host "  [OK]   $($r.Name)" -ForegroundColor Green }
    else { Write-Host "  [FAIL] $($r.Name)" -ForegroundColor Red; $failures.Add($r.Name) }
}

# Lua-Fehler: GMod schreibt "[ERROR] <pfad>" bzw. "[<addon>] lua/..." mit Stacktrace
$errors = $content | Select-String -Pattern '^\[ERROR\]|\[lmnt_|lmnt_(core|ttt)/lua/.*:\d+:' | Select-Object -Unique
$lmntErrors = $errors | Where-Object { $_.Line -match 'lmnt' }
$otherErrors = $errors | Where-Object { $_.Line -notmatch 'lmnt' }

# Fehler, die nur in RCON-Antworten auftauchen (z. B. per pcall abgefangene Befehlsfehler)
$rconErrors = $script:rconLog.ToString() -split "`n" | Where-Object { $_ -match "Fehler in Befehl|Lua Error|Beim Ausf.hren ist ein Fehler" } | Select-Object -Unique
if ($rconErrors) {
    Write-Host "`n  Fehler in RCON-Antworten:" -ForegroundColor Red
    $rconErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    $failures.Add("$(@($rconErrors).Count) Fehler in Befehlsantworten")
}

if ($lmntErrors) {
    Write-Host "`n  LMNT-Lua-Fehler:" -ForegroundColor Red
    $lmntErrors | ForEach-Object { Write-Host "    $($_.Line)" -ForegroundColor Red }
    $failures.Add("$(@($lmntErrors).Count) LMNT-Lua-Fehler")
}
if ($otherErrors) {
    Write-Host "`n  Andere Fehler (nicht LMNT, zur Info):" -ForegroundColor Yellow
    $otherErrors | Select-Object -First 15 | ForEach-Object { Write-Host "    $($_.Line)" -ForegroundColor Yellow }
}

# Automatisch erzeugte Kompatibilitätsmatrix ins Projekt übernehmen
$matrix = Join-Path $gmod "garrysmod\data\lmnt\compat_matrix.md"
if (Test-Path $matrix) {
    Copy-Item $matrix (Join-Path $script:ProjectRoot "docs\framework\KOMPATIBILITAET_AUTO.md") -Force
    Write-Host "  Kompatibilitätsmatrix -> docs\framework\KOMPATIBILITAET_AUTO.md"
}

$copy = Join-Path $script:ProjectRoot "tools\last_test_console.log"
if (Test-Path $log) { Copy-Item $log $copy -Force; Write-Host "`n  Log kopiert nach $copy" }

if ($failures.Count -eq 0) { Write-Host "`nERGEBNIS: PASS" -ForegroundColor Green; exit 0 }
Write-Host "`nERGEBNIS: FAIL" -ForegroundColor Red
$failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
exit 1
