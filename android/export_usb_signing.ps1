# Zkopiruje podpis na USB (spusti pred vlozenim USB disku).
#   cd android
#   .\export_usb_signing.ps1 -UsbDir "E:\menopocasie-podpis"

param(
    [Parameter(Mandatory = $true)]
    [string]$UsbDir
)

$ErrorActionPreference = "Stop"
$srcDir = Join-Path $env:USERPROFILE ".menopocasie\android"
$localBackup = Join-Path $PSScriptRoot "signing-backup-USB"

New-Item -ItemType Directory -Force -Path $UsbDir | Out-Null
New-Item -ItemType Directory -Force -Path $localBackup | Out-Null

$files = @(
    @{ Src = Join-Path $srcDir "upload-keystore.jks"; Name = "upload-keystore.jks" },
    @{ Src = Join-Path $localBackup "key.properties"; Name = "key.properties" },
    @{ Src = Join-Path $PSScriptRoot "upload_certificate.pem"; Name = "upload_certificate.pem" }
)

foreach ($f in $files) {
    if (-not (Test-Path $f.Src)) { throw "Chyba: $($f.Src)" }
    Copy-Item $f.Src (Join-Path $UsbDir $f.Name) -Force
    Copy-Item $f.Src (Join-Path $localBackup $f.Name) -Force -ErrorAction SilentlyContinue
}

# import_signing.ps1 ocakava signing.properties
Copy-Item (Join-Path $localBackup "key.properties") (Join-Path $UsbDir "signing.properties") -Force
Copy-Item (Join-Path $localBackup "key.properties") (Join-Path $localBackup "signing.properties") -Force

@"
Menopocasie - zaloha podpisu pre Google Play
SHA-1 upload: 2B:D8:28:2F:2C:74:56:DB:18:BE:F9:ED:03:46:91:F3:39:A8:05:45

Subory na USB:
  upload-keystore.jks
  key.properties
  upload_certificate.pem

Na novom PC:
  cd android
  .\import_signing.ps1 -SourceDir "E:\menopocasie-podpis"
"@ | Set-Content (Join-Path $UsbDir "README.txt") -Encoding UTF8

Write-Host "Hotovo: $UsbDir"
Write-Host "Skopirovane: upload-keystore.jks, key.properties, upload_certificate.pem"
