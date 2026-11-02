<#
    LMNT | TTT2 – FastDL-Ordner bauen

    Sammelt alle Inhalte (materials, models, sound, resource, maps) aus garrysmod\addons\*
    nach fastdl\www\ – mit identischer Ordnerstruktur, wie Garry's Mod sie erwartet.
    Zusätzlich wird jede Datei als .bz2 komprimiert (7-Zip), damit Clients schneller laden.
    Der Ladebildschirm aus fastdl\loading wird nach www\loading kopiert.

    Aufruf:  powershell -ExecutionPolicy Bypass -File tools\build_fastdl.ps1
#>

. "$PSScriptRoot\..\server\common.ps1"

$addonsDir = Join-Path $script:ProjectRoot "garrysmod\addons"
$fastdlDir = Join-Path $script:ProjectRoot "fastdl"
$www       = Join-Path $fastdlDir "www"
$sevenZip  = @("C:\Program Files\7-Zip\7z.exe", "C:\Program Files (x86)\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $sevenZip) {
    Write-Host "7-Zip nicht gefunden – Dateien werden unkomprimiert bereitgestellt (funktioniert, ist nur langsamer)." -ForegroundColor Yellow
}

Write-Step "Leere $www"
if (Test-Path $www) { Remove-Item $www -Recurse -Force }
New-Item -ItemType Directory -Force $www | Out-Null

$contentFolders = "materials", "models", "sound", "resource", "maps"
$count = 0

Write-Step "Sammle Inhalte"
foreach ($addon in Get-ChildItem $addonsDir -Directory) {
    foreach ($folder in $contentFolders) {
        $srcFolder = Join-Path $addon.FullName $folder
        if (-not (Test-Path $srcFolder)) { continue }

        foreach ($file in Get-ChildItem $srcFolder -Recurse -File) {
            $relative = $file.FullName.Substring($addon.FullName.Length + 1)
            $target = Join-Path $www $relative
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item $file.FullName $target -Force

            if ($sevenZip) {
                & $sevenZip a -tbzip2 -mx=9 -bso0 -bsp0 "$target.bz2" "$target" | Out-Null
            }

            Write-Host "  $relative"
            $count++
        }
    }
}

Write-Step "Ladebildschirm kopieren"
Copy-Item (Join-Path $fastdlDir "loading") (Join-Path $www "loading") -Recurse -Force

Write-Host ""
Write-Host "$count Datei(en) bereit in $www" -ForegroundColor Green
Write-Host "Starten mit: tools\serve_fastdl.bat   (oder Ordner auf einen echten Webserver hochladen)"
