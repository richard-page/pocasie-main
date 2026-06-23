# AAB pre Google Play - skontroluje SHA-1 pred odporucanim nahratia.
#   .\nahrat_na_play.ps1

$ErrorActionPreference = "Stop"
$expected = "B9:C2:3E:69:E6:D7:05:3F:C8:10:18:13:1C:94:C5:8B:7A:5A:78:28"
$signingDir = Join-Path $env:USERPROFILE ".menopocasie\android"
$projJks = Join-Path $PSScriptRoot "android\upload-keystore.jks"
$projProps = Join-Path $PSScriptRoot "android\key.properties"

$hasSigning = (Test-Path (Join-Path $signingDir "signing.properties")) -or
    ((Test-Path $projJks) -and (Test-Path $projProps))

if (-not $hasSigning) {
    Write-Host ""
    Write-Host "CHYBA: Nemas Play upload kluc na tomto PC." -ForegroundColor Red
    Write-Host ""
    Write-Host "Rychle riesenie - skopiruj 2 subory do android\ :"
    Write-Host "  upload-keystore.jks   (zo zalohy / stareho PC)"
    Write-Host "  key.properties        (skopiruj z key.properties.example, dopln hesla)"
    Write-Host ""
    Write-Host "Alebo: cd android ; .\import_signing.ps1 -KeystoreFile `"D:\cesta\upload-keystore.jks`""
    Write-Host ""
    exit 1
}

Set-Location $PSScriptRoot
flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$aab = "build\app\outputs\bundle\release\app-release.aab"
$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) { Write-Host "AAB: $aab"; exit 0 }

$out = & $keytool -printcert -jarfile $aab 2>&1
$sha1 = ($out | Where-Object { $_ -match 'SHA1:' } | Select-Object -First 1) -replace '.*SHA1:\s*', ''

Write-Host ""
Write-Host "SHA-1 AAB:  $sha1"
Write-Host "SHA-1 Play: $expected"

if ($sha1.ToUpper() -ne $expected.ToUpper()) {
    Write-Host ""
    Write-Host "TENTO AAB NAHRAVAJ NA PLAY - ZLY PODPIS!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "OK - nahraj na Play:" -ForegroundColor Green
Write-Host "  $aab"
