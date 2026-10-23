param(
    [string]$Repo = "GitGayHub/Bebranoid-iOS",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"
$ghExe = "gh"
if (-not (Get-Command $ghExe -ErrorAction SilentlyContinue)) {
    $fallbackGh = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path $fallbackGh) { $ghExe = $fallbackGh }
}

Write-Host "=== Bebranoid iOS -- Triggering Free macOS Simulator Preview Workflow ===" -ForegroundColor Cyan
& $ghExe workflow run ios-preview.yml --repo $Repo --ref $Branch
Write-Host "Triggered ios-preview.yml on $Repo ($Branch). Use .\scripts\ci-status.ps1 to monitor progress." -ForegroundColor Green
