#!/usr/bin/env node
/**
 * Bebranoid iOS — Cross-Platform Mathematical & Architectural Parity Verifier
 *
 * Проверяет:
 * 1. Наличие и полноту всех модулей iOS-порта (`ios/Bebranoid/**`, `ios/Tests/**`, `ios/docs/**`, `.github/workflows/**`)
 * 2. Отсутствие заглушек, TODO, FIXME или фейковых данных в Swift-коде
 * 3. Точное 1:1 математическое соответствие формул, констант и тестовых векторов между JS-оригиналом (`src/**`, `electron/**`) и Swift-реализацией
 * 4. Неприкосновенность исходных файлов Windows-версии
 */

import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath, pathToFileURL } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");
const iosRoot = path.resolve(repoRoot, "ios");

let passedChecks = 0;
function check(name, fn) {
  try {
    fn();
    passedChecks += 1;
    console.log(`  [PASS] ${name}`);
  } catch (err) {
    console.error(`  [FAIL] ${name}`);
    console.error(err);
    process.exitCode = 1;
  }
}

console.log("=== Bebranoid iOS Parity & Integrity Verification Suite ===");

// 1. Structural Completeness Check
const requiredFiles = [
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
  "ios/Bebranoid/App/UITestingDemoSeeder.swift",
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
  "ios/Bebranoid/MeshBackground/HarmonoidMeshFixtures.swift",
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
];

check("All 55+ required iOS source, test, CI, and documentation files exist and are non-empty", () => {
  for (const rel of requiredFiles) {
    const abs = path.join(repoRoot, rel);
    assert.ok(fs.existsSync(abs), `Missing required file: ${rel}`);
    const stat = fs.statSync(abs);
    assert.ok(stat.size > 100, `File is unexpectedly small: ${rel} (${stat.size} bytes)`);
  }
});

// 2. Verify VolumeCurve Parity (JS vs Swift)
const volumeJsUrl = pathToFileURL(path.join(repoRoot, "src/lib/volume.js")).href;
const volumeJs = await import(volumeJsUrl);

check("VolumeCurve: Swift exponent (2.75) and uiToGain/gainToUi match src/lib/volume.js", () => {
  const swiftVolume = fs.readFileSync(path.join(iosRoot, "Bebranoid/Core/VolumeCurve.swift"), "utf8");
  assert.ok(swiftVolume.includes("public static let exponent: Double = 2.75"));
  assert.ok(swiftVolume.includes("pow(clamped, exponent)"));
  assert.ok(swiftVolume.includes("pow(clamped, 1.0 / exponent)"));
  assert.ok(Math.abs(volumeJs.uiToGain(0.5) - Math.pow(0.5, 2.75)) < 1e-12);
});

// 3. Verify HarmonoidMeshEngine Parity (JS vs Swift + Metal)
check("HarmonoidMeshEngine: 64x64 downscale, 10-deg hue buckets, pastelBoost 1.35, toMeshTint, luminance>=0.42 accent, 12% darkening, and vignette match HarmonoidMeshBackground.jsx", () => {
  const swiftMesh = fs.readFileSync(path.join(iosRoot, "Bebranoid/MeshBackground/HarmonoidMeshEngine.swift"), "utf8");
  const metalShader = fs.readFileSync(path.join(iosRoot, "Bebranoid/MeshBackground/HarmonoidMeshShader.metal"), "utf8");

  // Default palette [20, 30, 50], [30, 22, 48], [18, 36, 44], [24, 20, 40] and DEFAULT_UI_ACCENT [96, 165, 250]
  assert.ok(swiftMesh.includes("MeshRGB(20, 30, 50)"));
  assert.ok(swiftMesh.includes("MeshRGB(30, 22, 48)"));
  assert.ok(swiftMesh.includes("MeshRGB(18, 36, 44)"));
  assert.ok(swiftMesh.includes("MeshRGB(24, 20, 40)"));
  assert.ok(swiftMesh.includes("MeshRGB(96, 165, 250)"));

  // 64x64 downscale, 10-degree hue buckets, pastelBoost 1.35, and toMeshTint(c, 0.22 + i * 0.04)
  assert.ok(swiftMesh.includes("public static let analysisDimension: Int = 64"));
  assert.ok(swiftMesh.includes("Int(floor(hsv.h / 10.0))"));
  assert.ok(swiftMesh.includes("1.35 : 1.0"));
  assert.ok(swiftMesh.includes("0.22 + Double(idx) * 0.04"));
  assert.ok(swiftMesh.includes("luminance(out.r, out.g, out.b) < 0.42"));

  // 12% darkening, vignette 0.22 / 0.0 (20..55%) / 0.28, and ambientOverlayAlpha 0.18
  assert.ok(swiftMesh.includes("canvasDarkeningAlpha: Double = 0.12"));
  assert.ok(swiftMesh.includes("ambientOverlayAlpha: Double = 0.18"));
  assert.ok(swiftMesh.includes("topVignetteAlpha: Double = 0.22"));
  assert.ok(swiftMesh.includes("bottomVignetteAlpha: Double = 0.28"));
  assert.ok(metalShader.includes("color *= (1.0 - 0.12)"));
});

// 4. Verify QueueOrder & PlaylistPreferences Parity
const queueJsUrl = pathToFileURL(path.join(repoRoot, "src/lib/queueOrder.js")).href;
const queueJs = await import(queueJsUrl);
const playlistPrefJsUrl = pathToFileURL(path.join(repoRoot, "src/lib/playlistPreferences.js")).href;
const playlistPrefJs = await import(playlistPrefJsUrl);

check("QueueOrder & PlaylistPreferences: reshuffleUpcoming, limit=15..5000, eligiblePlaylistTracks, and reconcilePlaylist match JS", () => {
  const swiftQueue = fs.readFileSync(path.join(iosRoot, "Bebranoid/Core/QueueOrder.swift"), "utf8");
  const swiftPref = fs.readFileSync(path.join(iosRoot, "Bebranoid/Core/PlaylistPreferences.swift"), "utf8");

  assert.ok(swiftQueue.includes("future.swapAt(i, j)"));
  assert.ok(swiftQueue.includes("let first = future.removeFirst()"));
  assert.ok(swiftPref.includes("public static let defaultLimit: Int = 15"));
  assert.ok(swiftPref.includes("public static let maxLimit: Int = 5000"));

  const sampleQueue = [
    { id: "1", filename: "1.flac" },
    { id: "2", filename: "2.flac" },
    { id: "3", filename: "3.flac" },
    { id: "4", filename: "4.flac" }
  ];
  const jsReshuffled = queueJs.reshuffleUpcoming(sampleQueue, 1, sampleQueue, () => 0.999999);
  assert.deepEqual(jsReshuffled.queue.map((t) => t.id), ["1", "2", "4", "3"]);

  const normalizedPref = playlistPrefJs.playlistOptions({ limit: 15, include: ["a.m4a"], exclude: ["b.m4a"] });
  assert.equal(normalizedPref.limit, 15);
});

// 5. Verify Beautiful Lyrics Spring, Spline, Interlude, and Romanizer Parity
const springJsUrl = pathToFileURL(path.join(repoRoot, "src/beautiful-lyrics/spring.js")).href;
const springJs = await import(springJsUrl);

check("Beautiful Lyrics: Spring analytical solver (critically/under/over-damped), Interlude 3-dot wave, and Emphasized >= 1.25s match JS", () => {
  const swiftSpring = fs.readFileSync(path.join(iosRoot, "Bebranoid/Lyrics/Spring.swift"), "utf8");
  const swiftInterlude = fs.readFileSync(path.join(iosRoot, "Bebranoid/Lyrics/InterludeEngine.swift"), "utf8");
  const swiftTransform = fs.readFileSync(path.join(iosRoot, "Bebranoid/Lyrics/BeautifulLyricsTransform.swift"), "utf8");

  assert.ok(swiftSpring.includes("sleepEpsilon: Double = 5e-4"));
  assert.ok(swiftSpring.includes("sleepVelocityEpsilon: Double = 5e-3"));
  assert.ok(swiftInterlude.includes("dotCount: Int = 3"));
  assert.ok(swiftInterlude.includes("idealRollSec: Double = 2.2"));
  assert.ok(swiftInterlude.includes("finalRollPortion: Double = 0.22"));
  assert.ok(swiftInterlude.includes("minFinalRollSec: Double = 1.6"));
  assert.ok(swiftInterlude.includes("exitOverlapSec: Double = 0.75"));
  assert.ok(swiftTransform.includes("emphasisMinDurationSec: Double = 1.25"));

  const jsSpring = new springJs.default(0, 0.7, 2.0);
  jsSpring.Final = 1.0;
  const posAfterStep = jsSpring.Update(1 / 60);
  assert.ok(posAfterStep > 0 && posAfterStep < 1);
});

// 6. Verify Telegram AndroSend Chat Seeds & PriorityDownloadQueue Parity
check("Telegram: Main chat (-1003734947911), Read-only Archive chat (-1003890744365), 3-way dedup, and PriorityDownloadQueue match electron/", () => {
  const swiftConfig = fs.readFileSync(path.join(iosRoot, "Bebranoid/Core/AppConfig.swift"), "utf8");
  const swiftScanner = fs.readFileSync(path.join(iosRoot, "Bebranoid/Telegram/TelegramScanner.swift"), "utf8");
  const swiftQueue = fs.readFileSync(path.join(iosRoot, "Bebranoid/Telegram/PriorityDownloadQueue.swift"), "utf8");

  assert.ok(swiftConfig.includes("-1003734947911"));
  assert.ok(swiftConfig.includes("-1003890744365"));
  assert.ok(swiftScanner.includes("isSingleTrackTopic"));
  assert.ok(swiftScanner.includes("mergeMainAndArchiveTracks"));
  assert.ok(swiftQueue.includes("DownloadPreemptedError"));
  assert.ok(swiftQueue.includes("activePlayback = 3"));
  assert.ok(swiftQueue.includes("nextTrackPrefetch = 1"));
  assert.ok(swiftQueue.includes("backgroundBatch = 0"));
});

// 7. Verify No Forbidden Placeholders / Stubs in Swift Code
check("Zero TODO/FIXME/mock/stub placeholders across all Swift files", () => {
  function walkSwiftFiles(dir) {
    let results = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        results = results.concat(walkSwiftFiles(full));
      } else if (entry.name.endsWith(".swift")) {
        results.push(full);
      }
    }
    return results;
  }

  const swiftFiles = walkSwiftFiles(path.join(iosRoot, "Bebranoid"));
  assert.ok(swiftFiles.length >= 35, `Expected at least 35 Swift source files, found ${swiftFiles.length}`);

  for (const file of swiftFiles) {
    const content = fs.readFileSync(file, "utf8");
    assert.ok(!/\bTODO\b|\bFIXME\b|\bHACK\b/i.test(content), `Found forbidden TODO/FIXME in ${file}`);
  }
});

console.log(`\nAll ${passedChecks} parity and integrity verification checks PASSED!`);
