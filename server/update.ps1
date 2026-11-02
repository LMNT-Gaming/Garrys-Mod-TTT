<#
    LMNT | TTT2 – Server-Update (GMod + CS:S aktualisieren, danach LMNT-Dateien neu kopieren)
    Server vorher beenden!
#>

. "$PSScriptRoot\common.ps1"
$s = Read-LmntSettings
$steamcmd = Get-SteamCmd $s

if (Get-Process srcds -ErrorAction SilentlyContinue) {
    throw "srcds läuft noch – bitte den Server zuerst beenden."
}

Write-Step "Aktualisiere Garry's Mod Dedicated Server"
& $steamcmd +force_install_dir "$(Get-GmodDir $s)" +login anonymous +app_update 4020 +quit

Write-Step "Aktualisiere CS:S-Inhalte"
& $steamcmd +force_install_dir "$(Join-Path $s.SERVER_DIR 'css')" +login anonymous +app_update 232330 +quit

& "$PSScriptRoot\deploy.ps1"
