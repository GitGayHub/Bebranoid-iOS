$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")

Write-Host "=== Bebranoid iOS -- Standalone Project & Swift Static Check ===" -ForegroundColor Cyan

# 1. Check all Swift files for non-empty content and single unguarded @main
$swiftFiles = Get-ChildItem -Path (Join-Path $repoRoot "Bebranoid"), (Join-Path $repoRoot "Tests") -Recurse -Filter "*.swift"
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

# 2. Run Standalone Parity and Security Suite
node (Join-Path $scriptDir "verify-parity.mjs")
if ($LASTEXITCODE -ne 0) {
    Write-Error "verify-parity.mjs failed."
}

# 3. Run 7-Fixture HarmonoidMeshBackground Parity Suite
node (Join-Path $scriptDir "verify-mesh-fixtures.mjs")
if ($LASTEXITCODE -ne 0) {
    Write-Error "verify-mesh-fixtures.mjs failed."
}

Write-Host "`nAll local Windows checks completed successfully!" -ForegroundColor Green
