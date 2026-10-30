$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== Bebranoid iOS Parity & Security Verification Suite (PowerShell) ===" -ForegroundColor Cyan
node (Join-Path $scriptDir "verify-parity.mjs")
if ($LASTEXITCODE -ne 0) {
    throw "verify-parity.mjs failed!"
}
