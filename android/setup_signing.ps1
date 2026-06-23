# Nastaví Play Store upload podpis. NOVÝ keystore sa NEVYTVÁRA (app už je na Play).
# Použi len import existujúceho .jks:
#
#   .\import_signing.ps1 -KeystoreFile "cesta\upload-keystore.jks"
#
# Záloha po importe:
#   .\export_signing.ps1

$signingDir = Join-Path $env:USERPROFILE ".menopocasie\android"
if (Test-Path (Join-Path $signingDir "signing.properties")) {
    Write-Host "Podpis už je OK: $signingDir"
    exit 0
}

Write-Host "Na tomto PC ešte nie je Play Store upload podpis."
Write-Host ""
Write-Host "1) Ak máš .jks súbor:"
Write-Host '   .\import_signing.ps1 -KeystoreFile "D:\cesta\upload-keystore.jks"'
Write-Host ""
Write-Host "2) Hľadanie na disku/USB:"
Write-Host "   .\find_signing.ps1"
Write-Host '   .\find_signing.ps1 -ExtraRoots "E:\","D:\"'
Write-Host ""
Write-Host "3) Bez .jks: Play Console → Integrita aplikácie → požiadať o reset upload kľúča"
Write-Host ""
Write-Host "Očakávaný SHA-1: B9:C2:3E:69:E6:D7:05:3F:C8:10:18:13:1C:94:C5:8B:7A:5A:78:28"
exit 1
