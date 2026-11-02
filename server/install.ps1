<#
    LMNT | TTT2 – Erstinstallation des Dedicated Servers (Windows)

    1. Lädt SteamCMD (offizielle Valve-Quelle)
    2. Installiert den Garry's Mod Dedicated Server (App 4020)
    3. Installiert Counter-Strike: Source Dedicated Server (App 232330) – Texturen für TTT-Maps
    4. Schreibt mount.cfg, damit GMod die CS:S-Inhalte einbindet
    5. Kopiert LMNT-Addons und Configs (deploy.ps1)

    Aufruf:  powershell -ExecutionPolicy Bypass -File server\install.ps1
#>

. "$PSScriptRoot\common.ps1"
$s = Read-LmntSettings

$serverDir = $s.SERVER_DIR
$steamDir  = Join-Path $serverDir "steamcmd"
$steamcmd  = Get-SteamCmd $s
$gmodDir   = Get-GmodDir $s
$cssDir    = Join-Path $serverDir "css"

Write-Step "Zielordner: $serverDir"
New-Item -ItemType Directory -Force $steamDir | Out-Null

if (-not (Test-Path $steamcmd)) {
    Write-Step "Lade SteamCMD herunter"
    $zip = Join-Path $steamDir "steamcmd.zip"
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $steamDir -Force
    Remove-Item $zip
}

# SteamCMD aktualisiert sich beim ersten Start selbst und ignoriert dabei alle Befehle –
# deshalb erst ein leerer Lauf, danach die eigentlichen Installationen (mit Wiederholung).
Write-Step "SteamCMD-Selbstaktualisierung"
& $steamcmd +quit | Out-Host

function Install-App([string]$dir, [int]$appId, [string]$checkFile) {
    for ($try = 1; $try -le 3; $try++) {
        & $steamcmd +force_install_dir "$dir" +login anonymous +app_update $appId validate +quit | Out-Host
        if (Test-Path (Join-Path $dir $checkFile)) { return }
        Write-Host "  Versuch $try fehlgeschlagen – wiederhole ..." -ForegroundColor Yellow
    }
    throw "App $appId konnte nicht installiert werden ($checkFile fehlt) – SteamCMD-Ausgabe prüfen."
}

Write-Step "Installiere/aktualisiere Garry's Mod Dedicated Server (App 4020) – das dauert beim ersten Mal einige Minuten"
Install-App $gmodDir 4020 "srcds.exe"

Write-Step "Installiere Counter-Strike: Source Dedicated Server (App 232330) für Map-Texturen"
Install-App $cssDir 232330 "cstrike"

Write-Step "Schreibe mount.cfg"
$mount = @"
"mountcfg"
{
	"cstrike"	"$cssDir\cstrike"
}
"@
Set-Content -Encoding ascii -Path (Join-Path $gmodDir "garrysmod\cfg\mount.cfg") -Value $mount

Write-Step "Kopiere LMNT-Dateien"
& "$PSScriptRoot\deploy.ps1"

Write-Host ""
Write-Host "Fertig! Nächste Schritte:" -ForegroundColor Green
Write-Host "  1. server\settings.ini ausfüllen (RCON-Passwort, COLLECTION_ID, STEAM_AUTHKEY, GSLT)"
Write-Host "  2. Deine SteamID64 in lmnt_core\lua\lmnt\core\sh_config.lua unter C.Owners eintragen"
Write-Host "  3. tools\build_fastdl.ps1 und tools\serve_fastdl.bat starten"
Write-Host "  4. server\start.bat starten"
