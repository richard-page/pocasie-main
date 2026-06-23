# Vytvori upload keystore + PEM pre Google Play (reset upload kluca).
$ErrorActionPreference = "Stop"

$signingDir = Join-Path $env:USERPROFILE ".menopocasie\android"
$keystorePath = Join-Path $signingDir "upload-keystore.jks"
$propsPath = Join-Path $signingDir "signing.properties"
$pemPath = Join-Path $PSScriptRoot "upload_certificate.pem"
$alias = "upload"

$keytool = (Get-Command keytool -ErrorAction Stop).Source
New-Item -ItemType Directory -Force -Path $signingDir | Out-Null

$chars = (48..57) + (65..90) + (97..122)
$pass = -join (1..20 | ForEach-Object { [char]($chars | Get-Random) })

& $keytool -genkeypair -v `
    -keystore $keystorePath `
    -alias $alias `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass $pass -keypass $pass `
    -dname "CN=Meno Pocasie, OU=Mobile, O=Meno Pocasie, L=Bratislava, ST=Slovakia, C=SK"

& $keytool -export -rfc -keystore $keystorePath -alias $alias `
    -file $pemPath -storepass $pass

$list = & $keytool -list -v -keystore $keystorePath -storepass $pass -alias $alias 2>&1
$sha1 = ($list | Where-Object { $_ -match 'SHA1:' } | Select-Object -First 1) -replace '.*SHA1:\s*', ''

@"
storePassword=$pass
keyPassword=$pass
keyAlias=$alias
storeFile=upload-keystore.jks
"@ | Set-Content $propsPath -Encoding ASCII

@"
# Aktualny upload kluc (po schvaleni v Play Console)
$sha1
"@ | Set-Content (Join-Path $PSScriptRoot "play_upload_sha1.txt") -Encoding ASCII

$backupDir = Join-Path $PSScriptRoot "signing-backup-NEW"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item $keystorePath (Join-Path $backupDir "upload-keystore.jks") -Force
Copy-Item $propsPath (Join-Path $backupDir "signing.properties") -Force
Copy-Item $pemPath (Join-Path $backupDir "upload_certificate.pem") -Force

Write-Host "KEYSTORE: $keystorePath"
Write-Host "SHA-1:    $sha1"
Write-Host "PEM:      $pemPath"
Write-Host "ZALOHA:   $backupDir"
Write-Host "HESLO:    $pass"
