param(
    [string]$RunId = "",
    [string]$OutputDir = "ios\artifacts"
)

$ErrorActionPreference = "Stop"
$ghExe = "gh"
if (-not (Get-Command $ghExe -ErrorAction SilentlyContinue)) {
    $fallbackGh = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path $fallbackGh) { $ghExe = $fallbackGh }
}

Write-Host "=== Bebranoid iOS -- Download Simulator Preview and IPA Artifacts ===" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $runs = & $ghExe run list --branch feature/ios-port --limit 10 --json databaseId,conclusion,workflowName | ConvertFrom-Json
    $successRun = $runs | Where-Object { $_.conclusion -eq "success" } | Select-Object -First 1
    if (-not $successRun) {
        Write-Warning "No completed successful GitHub Actions run found on branch feature/ios-port yet."
        Write-Host "Run .\ios\scripts\ci-status.ps1 to inspect the current GitHub Actions run status or billing quota." -ForegroundColor Yellow
        exit 1
    }
    $RunId = $successRun.databaseId.ToString()
    Write-Host "Selected latest successful run: $RunId ($($successRun.workflowName))" -ForegroundColor Green
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

& $ghExe run download $RunId --dir $OutputDir
Write-Host "Downloaded artifacts to: $(Resolve-Path $OutputDir)" -ForegroundColor Green

$screenshotsDir = Get-ChildItem -Path $OutputDir -Recurse -Directory | Where-Object { $_.Name -eq "screenshots" } | Select-Object -First 1
if ($screenshotsDir) {
    Write-Host "Opening Simulator screenshots directory: $($screenshotsDir.FullName)" -ForegroundColor Cyan
    Invoke-Item $screenshotsDir.FullName
}
