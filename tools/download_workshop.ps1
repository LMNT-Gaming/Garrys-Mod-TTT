<#
    LMNT | TTT2 – Workshop-Inhalte direkt per SteamCMD auf den Server laden

    Alternative zu +host_workshop_collection: funktioniert ohne Collection und ohne Web-API-Key.
    Lädt jedes Item aus garrysmod\data\lmnt\workshop.json und entpackt es nach
    garrysmod\addons\ws_<id>\  (der Dedicated Server bindet nur Ordner ein, keine losen .gma-Dateien).
    Alte, komprimierte Items (*_legacy.bin, LZMA) werden vorher dekomprimiert.

    Hinweis: Clients laden die Items trotzdem über den Workshop (resource.AddWorkshop in lmnt_core).

    Aufruf:  powershell -ExecutionPolicy Bypass -File tools\download_workshop.ps1
#>

. "$PSScriptRoot\..\server\common.ps1"
$s = Read-LmntSettings

$steamcmd  = Get-SteamCmd $s
$addons    = Join-Path (Get-GmodDir $s) "garrysmod\addons"
$extractor = Join-Path $PSScriptRoot "gma_extract.py"
if (-not (Test-Path $steamcmd)) { throw "SteamCMD fehlt – zuerst server\install.ps1 ausführen." }

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { throw "Python wird zum Entpacken der Workshop-Dateien benötigt." }

$data  = Get-Content -Raw -Encoding UTF8 (Join-Path $script:ProjectRoot "garrysmod\data\lmnt\workshop.json") | ConvertFrom-Json
$items = @($data.content) + @($data.maps)

Write-Step "Lade $($items.Count) Workshop-Items über SteamCMD"
$cmdArgs = @("+login", "anonymous")
foreach ($it in $items) { $cmdArgs += @("+workshop_download_item", "4000", [string]$it.id) }
$cmdArgs += "+quit"
& $steamcmd @cmdArgs | Select-String -Pattern "Success|ERROR|Failed" | ForEach-Object { "  $($_.Line.Trim())" }

$contentRoot = Join-Path (Split-Path $steamcmd) "steamapps\workshop\content\4000"

# Altlasten früherer Versionen dieses Skripts: lose .gma-Dateien werden nicht geladen
Get-ChildItem $addons -Filter "ws_*.gma" -File -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Step "Entpacke nach $addons"
$failed = 0
foreach ($it in $items) {
    $dir = Join-Path $contentRoot $it.id
    $file = Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $targetDir = Join-Path $addons "ws_$($it.id)"

    if (-not $file) {
        Write-Host "  [FEHLT] $($it.id) $($it.name) – Download fehlgeschlagen" -ForegroundColor Red
        $failed++
        continue
    }

    $gma = $file.FullName
    if ($file.Extension -ne ".gma") {
        # Alte Workshop-Dateien sind LZMA ("alone") ohne Endmarker – deshalb Decompressor-Objekt statt lzma.decompress
        $gma = Join-Path $dir "lmnt_extracted.gma"
        & $python -I -c "import lzma,sys; d=lzma.LZMADecompressor(format=lzma.FORMAT_ALONE); open(sys.argv[2],'wb').write(d.decompress(open(sys.argv[1],'rb').read()))" $file.FullName $gma
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FEHLER] $($it.name) konnte nicht dekomprimiert werden" -ForegroundColor Red
            $failed++
            continue
        }
    }

    if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
    $result = & $python -I $extractor $gma $targetDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FEHLER] $($it.name): $result" -ForegroundColor Red
        $failed++
        continue
    }

    Write-Host "  [OK] ws_$($it.id)  $result" -ForegroundColor Green

    # BSP-Name prüfen (verhindert falsche Einträge in mapcycle.txt)
    if ($it.map) {
        $bsps = Get-ChildItem (Join-Path $targetDir "maps") -Filter *.bsp -ErrorAction SilentlyContinue | ForEach-Object BaseName
        if ($bsps -notcontains $it.map) {
            Write-Host "       WARNUNG: workshop.json nennt '$($it.map)', im Paket liegt: $($bsps -join ', ')" -ForegroundColor Yellow
        }
    }
}

if ($failed -gt 0) { Write-Host "`n$failed Item(s) fehlgeschlagen." -ForegroundColor Red; exit 1 }
Write-Host "`nAlle Workshop-Inhalte bereit." -ForegroundColor Green
