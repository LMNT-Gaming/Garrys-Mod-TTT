<#
    LMNT | TTT2 – Workshop-Werkzeug

    - Prüft jede ID aus garrysmod\data\lmnt\workshop.json über die Steam-API (existiert? richtiger Titel? Größe?)
    - Vergleicht mit deiner Steam-Kollektion (COLLECTION_ID in settings.ini): fehlt etwas, ist etwas zu viel?
    - Erzeugt garrysmod\cfg\mapcycle.txt aus der Map-Liste

    Aufruf:  powershell -ExecutionPolicy Bypass -File tools\workshop.ps1
#>

. "$PSScriptRoot\..\server\common.ps1"
$s = Read-LmntSettings

$jsonPath = Join-Path $script:ProjectRoot "garrysmod\data\lmnt\workshop.json"
$data = Get-Content -Raw -Encoding UTF8 $jsonPath | ConvertFrom-Json
$items = @($data.content) + @($data.maps)

Write-Step "Prüfe $($items.Count) Workshop-Einträge über die Steam-API"
$body = @{ itemcount = $items.Count }
for ($i = 0; $i -lt $items.Count; $i++) { $body["publishedfileids[$i]"] = $items[$i].id }
$details = (Invoke-RestMethod -Method Post -Uri "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" -Body $body).response.publishedfiledetails

$totalMB = 0
$problems = 0
foreach ($d in $details) {
    $entry = $items | Where-Object { $_.id -eq $d.publishedfileid } | Select-Object -First 1
    if ($d.result -ne 1 -or $d.consumer_app_id -ne 4000) {
        Write-Host ("  [FEHLT]  {0}  {1}" -f $d.publishedfileid, $entry.name) -ForegroundColor Red
        $problems++
        continue
    }
    $mb = [math]::Round($d.file_size / 1MB, 1)
    $totalMB += $mb
    Write-Host ("  [OK]     {0,-11} {1,-32} {2,6} MB" -f $d.publishedfileid, $d.title, $mb) -ForegroundColor Green
}
Write-Host ("  Gesamtgröße: {0} MB" -f [math]::Round($totalMB, 1))

if ($s.COLLECTION_ID) {
    Write-Step "Vergleiche mit Kollektion $($s.COLLECTION_ID)"
    $col = Invoke-RestMethod -Method Post -Uri "https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/" -Body @{ collectioncount = 1; "publishedfileids[0]" = $s.COLLECTION_ID }
    $inCollection = @($col.response.collectiondetails[0].children | ForEach-Object { [string]$_.publishedfileid })
    $wanted = @($items | ForEach-Object { [string]$_.id })

    foreach ($id in $wanted) {
        if ($inCollection -notcontains $id) {
            Write-Host "  Fehlt in der Kollektion: $id  ->  https://steamcommunity.com/sharedfiles/filedetails/?id=$id" -ForegroundColor Yellow
            $problems++
        }
    }
    foreach ($id in $inCollection) {
        if ($wanted -notcontains $id) {
            Write-Host "  Nur in der Kollektion (nicht in workshop.json): $id" -ForegroundColor Yellow
        }
    }
    if ($problems -eq 0) { Write-Host "  Kollektion und workshop.json stimmen überein." -ForegroundColor Green }
} else {
    Write-Step "Keine COLLECTION_ID gesetzt – diese Items gehören in deine Kollektion:"
    foreach ($it in $items) { Write-Host "  https://steamcommunity.com/sharedfiles/filedetails/?id=$($it.id)   ($($it.name))" }
}

Write-Step "Schreibe mapcycle.txt"
$mapcycle = ($data.maps | ForEach-Object { $_.map }) -join "`r`n"
$target = Join-Path $script:ProjectRoot "garrysmod\cfg\mapcycle.txt"
[IO.File]::WriteAllText($target, $mapcycle + "`r`n", (New-Object Text.UTF8Encoding $false))
Write-Host "  $target"

if ($problems -gt 0) { Write-Host "`n$problems Problem(e) gefunden." -ForegroundColor Yellow } else { Write-Host "`nAlles in Ordnung." -ForegroundColor Green }
