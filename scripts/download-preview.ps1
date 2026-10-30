param(
    [string]$Repo = "GitGayHub/Bebranoid-iOS",
    [string]$Branch = "main",
    [string]$RunId = "",
    [string]$OutputDir = "artifacts"
)

$ErrorActionPreference = "Stop"
$ghExe = "gh"
if (-not (Get-Command $ghExe -ErrorAction SilentlyContinue)) {
    $fallbackGh = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path $fallbackGh) { $ghExe = $fallbackGh }
}

Write-Host "=== Bebranoid iOS -- Download Simulator Preview and IPA Artifacts ===" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $runs = & $ghExe run list --repo $Repo --branch $Branch --limit 10 --json databaseId,conclusion,workflowName | ConvertFrom-Json
    $successRun = $runs | Where-Object { $_.conclusion -eq "success" } | Select-Object -First 1
    if (-not $successRun) {
        Write-Warning "No completed successful GitHub Actions run found on $Repo ($Branch) yet."
        Write-Host "Run .\scripts\ci-status.ps1 to inspect the current GitHub Actions run status." -ForegroundColor Yellow
        exit 1
    }
    $RunId = $successRun.databaseId.ToString()
    Write-Host "Selected latest successful run: $RunId ($($successRun.workflowName))" -ForegroundColor Green
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

& $ghExe run download $RunId --repo $Repo --dir $OutputDir
Write-Host "Downloaded artifacts to: $(Resolve-Path $OutputDir)" -ForegroundColor Green
