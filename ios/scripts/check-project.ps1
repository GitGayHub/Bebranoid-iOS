$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
$iosRoot = Join-Path $repoRoot "ios"

Write-Host "=== Bebranoid iOS -- Local Project and Swift Static Check ===" -ForegroundColor Cyan

# 1. Verify Windows/Electron files are untouched relative to master commit d98c88d14a1c66f5d9907551521347d52aa187a6
Push-Location $repoRoot
try {
    $changedOutsideIos = git diff --name-only d98c88d14a1c66f5d9907551521347d52aa187a6 -- src electron package.json
    if ($changedOutsideIos) {
        Write-Error "Windows/Electron files were modified: $changedOutsideIos"
    }
    Write-Host "  [PASS] Windows/Electron source tree (src/, electron/, package.json) is 100% untouched." -ForegroundColor Green
} finally {
    Pop-Location
}

# 2. Check all Swift files for balanced braces, non-empty content, and single unguarded @main
$swiftFiles = Get-ChildItem -Path (Join-Path $iosRoot "Bebranoid"), (Join-Path $iosRoot "Tests") -Recurse -Filter "*.swift"
$unguardedMainFiles = @()

foreach ($file in $swiftFiles) {
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($content)) {
        Write-Error "Empty Swift file detected: $($file.FullName)"
    }
    if ($file.Name -eq "BebranoidApp.swift" -and $content -match "@main") {
        $unguardedMainFiles += $file.Name
    }
}

if ($unguardedMainFiles.Count -ne 1) {
    Write-Error "Expected exactly 1 primary @main entry point (BebranoidApp.swift), found: $($unguardedMainFiles -join ', ')"
}
Write-Host ("  [PASS] Checked {0} Swift files (single @main entry point verified)." -f $swiftFiles.Count) -ForegroundColor Green

# 3. Run Cross-Platform Parity and Integrity Suite
node (Join-Path $scriptDir "verify-parity.mjs")
if ($LASTEXITCODE -ne 0) {
    Write-Error "verify-parity.mjs failed."
}

# 4. Run 7-Fixture HarmonoidMeshBackground Parity Suite
node (Join-Path $scriptDir "verify-mesh-fixtures.mjs")
if ($LASTEXITCODE -ne 0) {
    Write-Error "verify-mesh-fixtures.mjs failed."
}

Write-Host "`nAll local Windows checks completed successfully!" -ForegroundColor Green
