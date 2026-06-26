# Importuje JEDINÝ platný Play Store upload keystore (SHA-1 musí sedieť).
#
#   .\import_signing.ps1 -KeystoreFile "D:\zaloha\upload-keystore.jks"
#   .\import_signing.ps1 -SourceDir ".\signing-backup-2026-06-11"

param(
    [string]$SourceDir = "",
    [string]$KeystoreFile = "",
    [string]$KeyAlias = "upload"
)

$ErrorActionPreference = "Stop"
$ExpectedSha1 = (Get-Content (Join-Path $PSScriptRoot "play_upload_sha1.txt") |
    Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() } | Select-Object -Last 1).Trim()

function Get-KeystoreSha1([string]$Path, [string]$StorePass, [string]$Alias) {
    $keytool = Get-Command keytool -ErrorAction Stop
    $out = & $keytool.Source -list -v -keystore $Path -storepass $StorePass -alias $Alias 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Keystore/heslo/alias nesedí." }
    $line = $out | Where-Object { $_ -match 'SHA1:\s*' } | Select-Object -First 1
    if (-not $line) { throw "Nepodarilo sa prečítať SHA-1 z keystore." }
    return ($line -replace '.*SHA1:\s*', '').Trim()
}

$signingDir = Join-Path $env:USERPROFILE ".menopocasie\android"
$destKeystore = Join-Path $signingDir "upload-keystore.jks"
$destProps = Join-Path $signingDir "signing.properties"

if ([string]::IsNullOrWhiteSpace($SourceDir) -and [string]::IsNullOrWhiteSpace($KeystoreFile)) {
    throw "Zadaj -KeystoreFile alebo -SourceDir."
}
if (-not [string]::IsNullOrWhiteSpace($SourceDir) -and -not [string]::IsNullOrWhiteSpace($KeystoreFile)) {
    throw "Použi len jedno z: -SourceDir alebo -KeystoreFile."
}

New-Item -ItemType Directory -Force -Path $signingDir | Out-Null

if (-not [string]::IsNullOrWhiteSpace($SourceDir)) {
    $source = Resolve-Path $SourceDir
    $srcKeystore = Join-Path $source "upload-keystore.jks"
    $srcProps = Join-Path $source "signing.properties"
    if (-not (Test-Path $srcProps)) {
        $srcProps = Join-Path $source "key.properties"
    }
    if (-not (Test-Path $srcKeystore)) { throw "Chýba upload-keystore.jks" }
    if (-not (Test-Path $srcProps)) { throw "Chýba signing.properties alebo key.properties" }
    Copy-Item $srcKeystore $destKeystore -Force
    Copy-Item $srcProps $destProps -Force
    $props = @{}
    Get-Content $destProps | ForEach-Object {
        if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
        $kv = $_ -split '=', 2
        if ($kv.Length -eq 2) { $props[$kv[0].Trim()] = $kv[1].Trim() }
    }
    $sha1 = Get-KeystoreSha1 $destKeystore $props.storePassword $props.keyAlias
} else {
    $src = Resolve-Path $KeystoreFile
    Copy-Item $src $destKeystore -Force
    Write-Host "Import: $src"
    $storePass = Read-Host "Store password" -AsSecureString
    $keyPass = Read-Host "Key password (Enter = rovnaké)" -AsSecureString
    $aliasInput = Read-Host "Key alias (Enter = upload)"
    if (-not [string]::IsNullOrWhiteSpace($aliasInput)) { $KeyAlias = $aliasInput }

    $storePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($storePass))
    $keyPassword = if ($keyPass.Length -eq 0) { $storePassword } else {
        [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyPass))
    }

    $sha1 = Get-KeystoreSha1 $destKeystore $storePassword $KeyAlias
    if ($sha1.ToUpper() -ne $ExpectedSha1.ToUpper()) {
        Remove-Item $destKeystore -Force -ErrorAction SilentlyContinue
        throw @"
NESPRÁVNY KĽÚČ — Play Store ho odmietne.
Očakávaný SHA-1: $ExpectedSha1
Tvoj súbor SHA-1: $sha1
"@
    }

    @"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$KeyAlias
storeFile=upload-keystore.jks
"@ | Set-Content -Path $destProps -Encoding ASCII
}

if ($sha1.ToUpper() -ne $ExpectedSha1.ToUpper()) {
    Remove-Item $destKeystore -Force -ErrorAction SilentlyContinue
    Remove-Item $destProps -Force -ErrorAction SilentlyContinue
    throw "Záloha má zlý SHA-1: $sha1 (potrebný: $ExpectedSha1)"
}

Write-Host ""
Write-Host "OK — Play Store upload podpis je nastavený."
Write-Host "SHA-1: $sha1"
Write-Host "Cesta: $signingDir"
Write-Host ""
Write-Host "Záloha:  .\export_signing.ps1"
Write-Host "Build:   flutter build appbundle --release"
