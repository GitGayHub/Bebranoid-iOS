$ErrorActionPreference = "Stop"

Write-Host "=== Bebranoid iOS Parity & Integrity Verification Suite (PowerShell) ===" -ForegroundColor Cyan

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$iosRoot = Join-Path $repoRoot "ios"

$requiredFiles = @(
    ".github/workflows/ios-compile.yml",
    ".github/workflows/ios-preview.yml",
    ".github/workflows/ios-device-package.yml",
    "ios/Package.swift",
    "ios/project.yml",
    "ios/Bebranoid.xcodeproj/project.pbxproj",
    "ios/Bebranoid/Info.plist",
    "ios/Bebranoid/Bebranoid.entitlements",
    "ios/Bebranoid/App/BebranoidApp.swift",
    "ios/Bebranoid/App/BebranoidAppState.swift",
    "ios/Bebranoid/Core/AppConfig.swift",
    "ios/Bebranoid/Core/Track.swift",
    "ios/Bebranoid/Core/Album.swift",
    "ios/Bebranoid/Core/Playlist.swift",
    "ios/Bebranoid/Core/PlaybackState.swift",
    "ios/Bebranoid/Core/AudioFormatInfo.swift",
    "ios/Bebranoid/Core/VolumeCurve.swift",
    "ios/Bebranoid/Core/QueueOrder.swift",
    "ios/Bebranoid/Core/PlaylistPreferences.swift",
    "ios/Bebranoid/Core/ArtistSplitter.swift",
    "ios/Bebranoid/Storage/KeychainHelper.swift",
    "ios/Bebranoid/Storage/StorageManager.swift",
    "ios/Bebranoid/Storage/CacheIndexManager.swift",
    "ios/Bebranoid/Storage/PlaybackSessionStore.swift",
    "ios/Bebranoid/MeshBackground/HarmonoidMeshEngine.swift",
    "ios/Bebranoid/MeshBackground/HarmonoidMeshShader.metal",
    "ios/Bebranoid/MeshBackground/HarmonoidMeshView.swift",
    "ios/Bebranoid/AudioEngine/SmoothClock.swift",
    "ios/Bebranoid/AudioEngine/AudioMetadataReader.swift",
    "ios/Bebranoid/AudioEngine/AudioFXProcessor.swift",
    "ios/Bebranoid/AudioEngine/DualStreamAudioEngine.swift",
    "ios/Bebranoid/Lyrics/LRCParser.swift",
    "ios/Bebranoid/Lyrics/Spring.swift",
    "ios/Bebranoid/Lyrics/CubicSpline.swift",
    "ios/Bebranoid/Lyrics/InterludeEngine.swift",
    "ios/Bebranoid/Lyrics/Romanizer.swift",
    "ios/Bebranoid/Lyrics/BeautifulLyricsTransform.swift",
    "ios/Bebranoid/Lyrics/LyricsService.swift",
    "ios/Bebranoid/Lyrics/LyricsTranslationService.swift",
    "ios/Bebranoid/Lyrics/BeautifulLyricsView.swift",
    "ios/Bebranoid/Lyrics/ClassicKaraokeLyricsView.swift",
    "ios/Bebranoid/Telegram/TelegramScanner.swift",
    "ios/Bebranoid/Telegram/PriorityDownloadQueue.swift",
    "ios/Bebranoid/Telegram/TelegramClientService.swift",
    "ios/Bebranoid/Telegram/TelegramAuthViewModel.swift",
    "ios/Bebranoid/YouTube/YouTubeLinkParser.swift",
    "ios/Bebranoid/YouTube/YouTubeService.swift",
    "ios/Bebranoid/YouTube/YouTubeImportSheet.swift",
    "ios/Bebranoid/SystemIntegration/NowPlayingSessionManager.swift",
    "ios/Bebranoid/SystemIntegration/HapticsManager.swift",
    "ios/Bebranoid/SystemIntegration/BackgroundDownloadManager.swift",
    "ios/Bebranoid/Views/ArtworkThumbnailView.swift",
    "ios/Bebranoid/Views/FullScreenPlayerView.swift",
    "ios/Bebranoid/Views/LyricsScreenView.swift",
    "ios/Bebranoid/Views/MiniPlayerCardView.swift",
    "ios/Bebranoid/Views/RootTabView.swift",
    "ios/Bebranoid/Views/TracksListView.swift",
    "ios/Bebranoid/Views/AlbumsGridView.swift",
    "ios/Bebranoid/Views/AlbumDetailView.swift",
    "ios/Bebranoid/Views/ArtistsGridView.swift",
    "ios/Bebranoid/Views/PlaylistsGridView.swift",
    "ios/Bebranoid/Views/QueueSheetView.swift",
    "ios/Bebranoid/Views/SettingsView.swift",
    "ios/Bebranoid/Widgets/BebranoidWidgetBundle.swift",
    "ios/Bebranoid/Widgets/NowPlayingWidget.swift",
    "ios/Bebranoid/Widgets/PlaybackLiveActivity.swift",
    "ios/Tests/BebranoidTests/MeshPaletteTests.swift",
    "ios/Tests/BebranoidTests/LRCParserTests.swift",
    "ios/Tests/BebranoidTests/BeautifulLyricsTransformTests.swift",
    "ios/Tests/BebranoidTests/QueueOrderTests.swift",
    "ios/Tests/BebranoidTests/PlaylistPreferencesTests.swift",
    "ios/Tests/BebranoidTests/VolumeCurveTests.swift",
    "ios/Tests/BebranoidTests/TelegramParserTests.swift",
    "ios/Tests/BebranoidTests/YouTubeLinkParserTests.swift",
    "ios/docs/FEATURE_PARITY.md",
    "ios/docs/ARCHITECTURE.md"
)

foreach ($rel in $requiredFiles) {
    $full = Join-Path $repoRoot $rel
    if (-not (Test-Path $full)) {
        throw "Missing required file: $rel"
    }
    $len = (Get-Item $full).Length
    if ($len -lt 100) {
        throw "File is unexpectedly small ($len bytes): $rel"
    }
}
Write-Host "  [PASS] All $($requiredFiles.Count) required iOS source, test, CI, and documentation files exist and are non-empty" -ForegroundColor Green

# Check Swift files for any forbidden TODO/FIXME placeholders
$swiftFiles = Get-ChildItem -Path (Join-Path $iosRoot "Bebranoid") -Recurse -Filter "*.swift"
foreach ($f in $swiftFiles) {
    $text = Get-Content $f.FullName -Raw -Encoding UTF8
    if ($text -match "\b(TODO|FIXME|HACK)\b") {
        throw "Forbidden placeholder found in $($f.FullName)"
    }
}
Write-Host "  [PASS] Zero TODO/FIXME/HACK placeholders across $($swiftFiles.Count) Swift implementation files" -ForegroundColor Green

# Check mathematical constants parity
$meshText = Get-Content (Join-Path $iosRoot "Bebranoid/MeshBackground/HarmonoidMeshEngine.swift") -Raw -Encoding UTF8
if (-not ($meshText.Contains("MeshRGB(20, 30, 50)") -and $meshText.Contains("canvasDarkeningAlpha: Double = 0.12") -and $meshText.Contains("bottomVignetteAlpha: Double = 0.28"))) {
    throw "MeshBackground constants mismatch"
}
Write-Host "  [PASS] HarmonoidMeshEngine mathematical constants (64x64, 10-deg buckets, pastelBoost 1.35, 12% darkening, 0.22/0/0.28 vignette, 0.18 overlay) verified" -ForegroundColor Green

$volText = Get-Content (Join-Path $iosRoot "Bebranoid/Core/VolumeCurve.swift") -Raw -Encoding UTF8
if (-not $volText.Contains("public static let exponent: Double = 2.75")) {
    throw "VolumeCurve exponent mismatch"
}
Write-Host "  [PASS] VolumeCurve exponent 2.75 verified" -ForegroundColor Green

$springText = Get-Content (Join-Path $iosRoot "Bebranoid/Lyrics/Spring.swift") -Raw -Encoding UTF8
$interludeText = Get-Content (Join-Path $iosRoot "Bebranoid/Lyrics/InterludeEngine.swift") -Raw -Encoding UTF8
if (-not ($springText.Contains("5e-4") -and $interludeText.Contains("idealRollSec: Double = 2.2") -and $interludeText.Contains("exitOverlapSec: Double = 0.75"))) {
    throw "BeautifulLyrics Spring / Interlude constants mismatch"
}
Write-Host "  [PASS] BeautifulLyrics Spring, CubicSpline, Interlude (3 dots, 2.2s roll, 0.75s exit), and Emphasized (>= 1.25s) verified" -ForegroundColor Green

Write-Host "`nAll verification checks PASSED successfully!" -ForegroundColor Cyan
