param(
    [string]$ArtifactsDir = "ios\artifacts"
)

$ErrorActionPreference = "Stop"
Write-Host "=== Bebranoid iOS -- Downloaded Artifacts Verification ===" -ForegroundColor Cyan

if (-not (Test-Path $ArtifactsDir)) {
    Write-Warning "Artifacts directory '$ArtifactsDir' does not exist yet. Run .\ios\scripts\download-preview.ps1 after a successful GitHub Actions run."
    exit 1
}

$expectedScreenshots = @(
    "01-library.png",
    "02-tracks.png",
    "03-albums.png",
    "04-artists.png",
    "05-playlists.png",
    "06-player.png",
    "07-lyrics.png",
    "08-queue.png",
    "09-settings.png",
    "10-mini-player.png"
)

$allFiles = Get-ChildItem -Path $ArtifactsDir -Recurse -File
foreach ($shot in $expectedScreenshots) {
    $found = $allFiles | Where-Object { $_.Name -eq $shot } | Select-Object -First 1
    if ($found -and $found.Length -gt 1024) {
        Write-Host ("  [OK] Screenshot {0,-20} ({1} bytes)" -f $shot, $found.Length) -ForegroundColor Green
    } else {
        Write-Host ("  [MISSING] Screenshot {0}" -f $shot) -ForegroundColor Yellow
    }
}

$ipaFile = $allFiles | Where-Object { $_.Name -eq "Bebranoid-unsigned-sideloadly.ipa" } | Select-Object -First 1
if ($ipaFile) {
    Write-Host ("  [OK] Unsigned IPA Package found: {0} ({1} bytes)" -f $ipaFile.FullName, $ipaFile.Length) -ForegroundColor Green
} else {
    Write-Host "  [INFO] Unsigned IPA Package not downloaded in this folder yet (run workflow ios-device-package.yml)." -ForegroundColor Gray
}
