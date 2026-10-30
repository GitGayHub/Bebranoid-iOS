param(
    [switch]$InstallMissing
)

$ErrorActionPreference = "Stop"
Write-Host "=== Bebranoid iOS -- Windows 11 Free Toolchain Diagnostic ===" -ForegroundColor Cyan

$tools = @(
    @{ Name = "Git";        Cmd = "git";    Args = "--version"; WingetId = "Git.Git" },
    @{ Name = "Node.js";    Cmd = "node";   Args = "--version"; WingetId = "OpenJS.NodeJS.LTS" },
    @{ Name = "npm";        Cmd = "npm";    Args = "--version"; WingetId = $null },
    @{ Name = "Python 3";   Cmd = "python"; Args = "--version"; WingetId = "Python.Python.3.12" },
    @{ Name = "GitHub CLI"; Cmd = "gh";     Args = "--version"; WingetId = "GitHub.cli" }
)

$missing = @()

foreach ($t in $tools) {
    $found = Get-Command $t.Cmd -ErrorAction SilentlyContinue
    if ($null -ne $found) {
        $ver = & $t.Cmd $t.Args 2>&1 | Select-Object -First 1
        Write-Host ("  [OK] {0,-12} : {1}" -f $t.Name, $ver) -ForegroundColor Green
    } else {
        Write-Host ("  [MISSING] {0,-12}" -f $t.Name) -ForegroundColor Yellow
        if ($null -ne $t.WingetId) {
            $missing += $t
        }
    }
}

Write-Host ("  [OK] PowerShell   : {0}" -f $PSVersionTable.PSVersion.ToString()) -ForegroundColor Green

if ($missing.Count -gt 0 -and $InstallMissing) {
    foreach ($m in $missing) {
        Write-Host "Installing $($m.Name) via winget ($($m.WingetId))..." -ForegroundColor Cyan
        winget install --id $m.WingetId --accept-package-agreements --accept-source-agreements
    }
}

Write-Host "`n--- GitHub Authentication Check ---" -ForegroundColor Cyan
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghCmd) {
    $fallbackGh = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path $fallbackGh) { $ghCmd = $fallbackGh }
}
if ($null -ne $ghCmd) {
    & $ghCmd auth status
} else {
    Write-Host "GitHub CLI (gh) is not in PATH. Run with -InstallMissing or install GitHub.cli via winget." -ForegroundColor Yellow
}

Write-Host "`nNOTE: Native iOS compilation (UIKit / SwiftUI / AVFAudio / Metal / WidgetKit) requires Apple iOS SDK and Xcode." -ForegroundColor Gray
Write-Host "Use GitHub Actions free macOS workflows (ios-compile.yml, ios-preview.yml, ios-device-package.yml) for remote compilation and Simulator screenshots." -ForegroundColor Gray
