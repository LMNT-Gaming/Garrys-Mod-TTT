<#
    LMNT | TTT2 – Windows-Firewall-Regeln für Gameserver und FastDL anlegen
    Muss als Administrator ausgeführt werden. Vorher prüfen, ob die Ports zu settings.ini passen!
#>

. "$PSScriptRoot\..\server\common.ps1"
$s = Read-LmntSettings

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Bitte PowerShell als Administrator starten." }

New-NetFirewallRule -DisplayName "LMNT GMod UDP $($s.PORT)" -Direction Inbound -Protocol UDP -LocalPort $s.PORT -Action Allow | Out-Null
New-NetFirewallRule -DisplayName "LMNT GMod TCP $($s.PORT) (RCON)" -Direction Inbound -Protocol TCP -LocalPort $s.PORT -Action Allow | Out-Null
New-NetFirewallRule -DisplayName "LMNT FastDL TCP $($s.FASTDL_PORT)" -Direction Inbound -Protocol TCP -LocalPort $s.FASTDL_PORT -Action Allow | Out-Null

Write-Host "Firewall-Regeln angelegt. Im Router zusätzlich Portweiterleitung einrichten: UDP+TCP $($s.PORT), TCP $($s.FASTDL_PORT)." -ForegroundColor Green
