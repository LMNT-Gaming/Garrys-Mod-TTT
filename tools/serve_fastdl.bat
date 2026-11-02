@echo off
rem =====================================================================
rem  LMNT - einfacher FastDL-Webserver (Python) fuer fastdl\www
rem  Fuer den Dauerbetrieb besser Caddy/nginx/IIS verwenden (siehe docs\FASTDL.md).
rem =====================================================================
setlocal
cd /d "%~dp0\.."

for /f "usebackq eol=; tokens=1,* delims==" %%a in ("server\settings.ini") do set "%%a=%%b"
if "%FASTDL_PORT%"=="" set "FASTDL_PORT=8080"

if not exist "fastdl\www" (
    echo fastdl\www fehlt - bitte zuerst tools\build_fastdl.ps1 ausfuehren.
    pause
    exit /b 1
)

echo FastDL laeuft auf Port %FASTDL_PORT%  (STRG+C beendet)
python -m http.server %FASTDL_PORT% --bind 0.0.0.0 --directory "fastdl\www"
