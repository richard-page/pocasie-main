# Záloha podpisu pre nový PC alebo pre bezpečné uloženie.
# Spustenie:  cd android; .\export_signing.ps1

$ErrorActionPreference = "Stop"

$signingDir = Join-Path $env:USERPROFILE ".menopocasie\android"
$keystorePath = Join-Path $signingDir "upload-keystore.jks"
$keyPropsPath = Join-Path $signingDir "signing.properties"

if (-not (Test-Path $keystorePath) -or -not (Test-Path $keyPropsPath)) {
    throw "Podpis nie je nastavený. Najprv spusti: .\setup_signing.ps1"
}

$stamp = Get-Date -Format "yyyy-MM-dd"
$exportDir = Join-Path $PSScriptRoot "signing-backup-$stamp"
New-Item -ItemType Directory -Force -Path $exportDir | Out-Null

Copy-Item $keystorePath (Join-Path $exportDir "upload-keystore.jks") -Force
Copy-Item $keyPropsPath (Join-Path $exportDir "signing.properties") -Force

@"
Menopocasie Android signing backup
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm")

Na novom PC:
  1. Skopíruj túto zložku na USB / cloud (NIKDY do verejného gitu).
  2. cd android
  3. .\import_signing.ps1 -SourceDir "cesta\k\tomuto\priečinku"
"@ | Set-Content -Path (Join-Path $exportDir "README.txt") -Encoding UTF8

Write-Host "Záloha vytvorená:"
Write-Host "  $exportDir"
Write-Host ""
Write-Host "Ulož ju na bezpečné miesto. Na novom PC použi import_signing.ps1."
