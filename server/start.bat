@echo off
rem =====================================================================
rem  LMNT ^| TTT2 - Serverstart mit automatischem Neustart nach Absturz
rem  Einstellungen: settings.ini
rem =====================================================================
setlocal EnableExtensions
cd /d "%~dp0"

if not exist "settings.ini" (
    echo settings.ini fehlt - bitte settings.example.ini nach settings.ini kopieren und anpassen.
    pause
    exit /b 1
)

for /f "usebackq eol=; tokens=1,* delims==" %%a in ("settings.ini") do set "%%a=%%b"

set "GMOD=%SERVER_DIR%\gmod"
if not exist "%GMOD%\srcds.exe" (
    echo Server nicht gefunden unter "%GMOD%".
    echo Bitte zuerst ausfuehren:  powershell -ExecutionPolicy Bypass -File install.ps1
    pause
    exit /b 1
)

rem -usercon aktiviert TCP-RCON (Fernsteuerung, z. B. tools\rcon.py) - geschuetzt durch RCON_PASSWORD
set "ARGS=-console -usercon -game garrysmod -port %PORT% -tickrate %TICKRATE% +maxplayers %MAXPLAYERS% +gamemode terrortown +map %MAP%"
if not "%COLLECTION_ID%"=="" set "ARGS=%ARGS% +host_workshop_collection %COLLECTION_ID%"
if not "%STEAM_AUTHKEY%"=="" set "ARGS=%ARGS% -authkey %STEAM_AUTHKEY%"
if not "%GSLT%"=="" set "ARGS=%ARGS% +sv_setsteamaccount %GSLT%"

if "%COLLECTION_ID%"=="" echo WARNUNG: COLLECTION_ID ist leer - TTT2 und Maps werden nicht geladen!

:loop
echo [%date% %time%] Starte LMNT-Server auf Port %PORT% ...
"%GMOD%\srcds.exe" %ARGS%
echo [%date% %time%] Server beendet (Code %errorlevel%). Neustart in 10 Sekunden - STRG+C zum Abbrechen.
timeout /t 10
goto loop
