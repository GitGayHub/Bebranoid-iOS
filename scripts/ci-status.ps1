param(
    [string]$Repo = "GitGayHub/Bebranoid-iOS",
    [string]$Branch = "main",
    [int]$Limit = 10
)

$ErrorActionPreference = "Stop"
$ghExe = "gh"
if (-not (Get-Command $ghExe -ErrorAction SilentlyContinue)) {
    $fallbackGh = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path $fallbackGh) { $ghExe = $fallbackGh }
}

Write-Host "=== Bebranoid iOS -- GitHub Actions CI Status ($Repo @ $Branch) ===" -ForegroundColor Cyan
& $ghExe run list --repo $Repo --branch $Branch --limit $Limit

$latestJson = & $ghExe run list --repo $Repo --branch $Branch --limit 1 --json databaseId,workflowName,status,conclusion,url,createdAt | ConvertFrom-Json
if ($latestJson -and $latestJson.Count -gt 0) {
    $run = $latestJson[0]
    Write-Host "`nLatest Run Details:" -ForegroundColor Cyan
    Write-Host "  Workflow   : $($run.workflowName)"
    Write-Host "  Run ID     : $($run.databaseId)"
    Write-Host "  Status     : $($run.status) / $($run.conclusion)"
    Write-Host "  URL        : $($run.url)"
    & $ghExe run view $run.databaseId --repo $Repo
}
