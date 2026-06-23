# Po schvaleni NOVEHO upload kluca v Play Console (reset kluca).
# Aktualizuje ocakavany SHA-1 z upload_certificate.pem v tomto priecinku.

$ErrorActionPreference = "Stop"
$pem = Join-Path $PSScriptRoot "upload_certificate.pem"
if (-not (Test-Path $pem)) { throw "Chyba $pem" }

$keytool = (Get-Command keytool -ErrorAction Stop).Source
$out = & $keytool -printcert -file $pem 2>&1
$sha1 = ($out | Where-Object { $_ -match 'SHA1:' } | Select-Object -First 1) -replace '.*SHA1:\s*', ''
if (-not $sha1) { throw "Nepodarilo sa precitat SHA-1 z PEM." }

@"
# Po resete upload kluca v Play Console
$sha1
"@ | Set-Content (Join-Path $PSScriptRoot "play_upload_sha1.txt") -Encoding ASCII

Write-Host "play_upload_sha1.txt = $sha1"
Write-Host "Teraz musis mat upload-keystore.jks s rovnakym SHA-1 (new_upload_key_for_google.ps1)."
Write-Host "Potom: cd .. ; .\nahrat_na_play.ps1"
