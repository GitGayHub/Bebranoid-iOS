$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== Bebranoid iOS -- HarmonoidMeshBackground 1:1 Math and Fixture Verification ===" -ForegroundColor Cyan
node (Join-Path $scriptDir "verify-mesh-fixtures.mjs")
if ($LASTEXITCODE -ne 0) {
    Write-Error "Mesh parity verification failed!"
}
