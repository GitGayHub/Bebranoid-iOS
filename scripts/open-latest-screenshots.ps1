param(
    [string]$ArtifactsDir = "artifacts"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $ArtifactsDir)) {
    Write-Warning "Artifacts directory '$ArtifactsDir' does not exist yet. Run .\scripts\download-preview.ps1 first."
    exit 1
}

$screenshotsDir = Get-ChildItem -Path $ArtifactsDir -Recurse -Directory | Where-Object { $_.Name -eq "screenshots" } | Select-Object -First 1
if ($screenshotsDir) {
    Write-Host "Opening Simulator screenshots directory: $($screenshotsDir.FullName)" -ForegroundColor Cyan
    Invoke-Item $screenshotsDir.FullName
} else {
    Write-Warning "No 'screenshots' directory found inside '$ArtifactsDir'."
}
