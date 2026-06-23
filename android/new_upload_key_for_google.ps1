# Novy upload keystore + PEM certifikat pre Google Play (reset upload kluca).
# Spustenie:  cd android; .\new_upload_key_for_google.ps1
#
# Potom v Play Console: Integrita aplikacie -> poziadat o reset upload kluca
# Nahraj subor: upload_certificate.pem z tohto priecinka.

$ErrorActionPreference = "Stop"

$signingDir = Join-Path $env:USERPROFILE ".menopocasie\android"
$keystorePath = Join-Path $signingDir "upload-keystore.jks"
$pemPath = Join-Path $PSScriptRoot "upload_certificate.pem"
$alias = "upload"

$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) { throw "Nainstaluj JDK (keytool)." }

New-Item -ItemType Directory -Force -Path $signingDir | Out-Null

if (Test-Path $keystorePath) {
    $ans = Read-Host "upload-keystore.jks uz existuje. Prepisat? (ano/nie)"
    if ($ans -notmatch '^a') { exit 0 }
}

Write-Host "Vytvaram NOVY upload keystore (pouzitelny az po schvaleni v Play Console)."
$storePass = Read-Host "Nove store password (min. 6 znakov)" -AsSecureString
$keyPass = Read-Host "Key password (Enter = rovnake)" -AsSecureString

$storePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($storePass))
$keyPassword = if ($keyPass.Length -eq 0) { $storePassword } else {
    [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyPass))
}

& $keytool -genkeypair -v `
    -keystore $keystorePath `
    -alias $alias `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass $storePassword -keypass $keyPassword `
    -dname "CN=Meno Pocasie, OU=Mobile, O=Meno Pocasie, L=Bratislava, ST=Slovakia, C=SK"

& $keytool -export -rfc -keystore $keystorePath -alias $alias `
    -file $pemPath -storepass $storePassword

$list = & $keytool -list -v -keystore $keystorePath -storepass $storePassword -alias $alias 2>&1
$sha1Line = $list | Where-Object { $_ -match 'SHA1:' } | Select-Object -First 1
$newSha1 = ($sha1Line -replace '.*SHA1:\s*', '').Trim()

@"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$alias
storeFile=upload-keystore.jks
"@ | Set-Content -Path (Join-Path $signingDir "signing.properties") -Encoding ASCII

Set-Content -Path (Join-Path $PSScriptRoot "play_upload_sha1.txt") -Value $newSha1 -Encoding ASCII

Write-Host ""
Write-Host "Hotovo."
Write-Host "Keystore: $keystorePath"
Write-Host "PEM pre Google: $pemPath"
Write-Host "Novy SHA-1: $newSha1"
Write-Host ""
Write-Host "1) Play Console -> Integrita aplikacie -> reset upload kluca -> nahraj upload_certificate.pem"
Write-Host "2) Po schvaleni Google aktualizuj SHA-1 v android/app/build.gradle.kts (playUploadSha1)"
Write-Host "   alebo skopiruj z android/play_upload_sha1.txt"
Write-Host "3) .\export_signing.ps1  (zaloha)"
Write-Host "4) cd .. ; .\build_play_release.ps1"
