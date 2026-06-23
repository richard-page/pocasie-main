# Release AAB pre Google Play (kontrola spravneho SHA-1).
#   .\build_play_release.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
flutter build appbundle --release -PplayStoreUpload=true
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "OK pre Play Store: build\app\outputs\bundle\release\app-release.aab" -ForegroundColor Green
}
