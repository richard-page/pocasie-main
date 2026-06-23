# Hlada .jks/.keystore a overi SHA-1 voči Google Play.
#   .\find_signing.ps1
#   .\find_signing.ps1 -ExtraRoots "E:\","D:\"

param(
    [string[]]$ExtraRoots = @()
)

$ErrorActionPreference = "SilentlyContinue"
$ExpectedSha1 = "B9:C2:3E:69:E6:D7:05:3F:C8:10:18:13:1C:94:C5:8B:7A:5A:78:28"
$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source

$roots = @(
    $env:USERPROFILE,
    (Join-Path $env:USERPROFILE "Documents"),
    (Join-Path $env:USERPROFILE "Desktop"),
    (Join-Path $env:USERPROFILE "Downloads"),
    (Join-Path $env:USERPROFILE "OneDrive"),
    (Join-Path $env:USERPROFILE "AndroidStudioProjects")
) + $ExtraRoots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$stores = @()
foreach ($root in $roots) {
    Get-ChildItem -Path $root -Include "*.jks", "*.keystore" -Recurse -Depth 8 |
        Where-Object { $_.FullName -notmatch '\\\.gradle\\|\\node_modules\\|\\build\\intermediates\\|flutter\\engine\\' } |
        ForEach-Object { $stores += $_ }
}

Write-Host "Hladam Play upload SHA-1: $ExpectedSha1"
Write-Host ""

$match = $null
foreach ($store in ($stores | Sort-Object FullName -Unique)) {
    Write-Host "Najdene: $($store.FullName)"
    if (-not $keytool) { continue }

  $list = & $keytool -list -v -keystore $store.FullName -storepass "" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  (treba heslo - import: .\import_signing.ps1 -KeystoreFile `"$($store.FullName)`")"
        continue
    }

    $sha1Line = $list | Where-Object { $_ -match 'SHA1:' } | Select-Object -First 1
    if ($sha1Line) {
        $sha1 = ($sha1Line -replace '.*SHA1:\s*', '').Trim()
        Write-Host "  SHA-1: $sha1"
        if ($sha1.ToUpper() -eq $ExpectedSha1.ToUpper()) {
            $match = $store.FullName
        }
    }
}

Write-Host ""
if ($match) {
    Write-Host "SPRAVNY KLUC: $match"
    Write-Host "Import: .\import_signing.ps1 -KeystoreFile `"$match`""
    exit 0
}

Write-Host "Spravny upload keystore na skenovanych cestach NENAJDENY."
Write-Host 'Skus USB: .\find_signing.ps1 -ExtraRoots "E:\","D:\","F:\"'
Write-Host "Bez .jks: Play Console -> Integrita aplikacie -> reset upload kluca."
exit 1
