import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

#if DEBUG
/// Режим детерминированной инициализации только для DEBUG / UI-тестирования в iOS Simulator (`--ui-testing-demo`).
/// Не компилируется в Release и никак не влияет на обычную работу приложения.
/// Генерирует настоящие растровые обложки высокого разрешения (`600×600` JPEG) и реальные WAV-аудиофайлы на диске,
/// заполняет метаданные треков, альбомов, артистов, плейлистов, очереди и караоке-лирики,
/// а также позволяет переключать эталонные фикстуры `HarmonoidMeshBackground` (`--mesh-fixture=...`, `--mesh-time=...`)
/// и открывать целевой экран (`--screen=...`) для автоматического снятия скриншотов в GitHub Actions.
@MainActor
public enum UITestingDemoSeeder {
    public static let demoMainChatId = "-1001000000001"
    public static let demoArchiveChatId = "-1001000000002"

    public static var isDemoModeActive: Bool {
        CommandLine.arguments.contains("--ui-testing-demo")
    }

    public static var requestedScreen: String? {
        for arg in CommandLine.arguments {
            if arg.hasPrefix("--screen=") {
                return String(arg.dropFirst("--screen=".count)).lowercased()
            }
        }
        return nil
    }

    public static var requestedMeshFixture: HarmonoidMeshFixtureKind? {
        for arg in CommandLine.arguments {
            if arg.hasPrefix("--mesh-fixture=") {
                let raw = String(arg.dropFirst("--mesh-fixture=".count)).lowercased()
                return HarmonoidMeshFixtureKind(rawValue: raw)
            }
        }
        return nil
    }

    public static var requestedMeshTime: Double? {
        for arg in CommandLine.arguments {
            if arg.hasPrefix("--mesh-time=") {
                let raw = String(arg.dropFirst("--mesh-time=".count))
                return Double(raw)
            }
        }
        return nil
    }

    public static func applyIfNeeded(to appState: BebranoidAppState) {
        guard isDemoModeActive else { return }

        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let storage = StorageManager.shared

        // 1. Генерируем 6 уникальных растровых обложек высокого разрешения (600x600 JPEG) на диске
        let coverMidnight = generateDemoCoverOnDisk(
            filename: "demo_cover_midnight_telemetry.jpg",
            theme: .synthwaveHorizon
        )
        let coverAurora = generateDemoCoverOnDisk(
            filename: "demo_cover_aurora_echoes.jpg",
            theme: .emeraldAurora
        )
        let coverKino = generateDemoCoverOnDisk(
            filename: "demo_cover_kino_zvezda.jpg",
            theme: .constructivistSun
        )
        let coverYouTube = generateDemoCoverOnDisk(
            filename: "demo_cover_youtube_modular.jpg",
            theme: .modularSunset
        )
        let coverEmergence = generateDemoCoverOnDisk(
            filename: "demo_cover_emergence_cooper.jpg",
            theme: .cobaltPrism
        )
        let coverFavorites = generateDemoCoverOnDisk(
            filename: "demo_cover_favorites_ruby.jpg",
            theme: .rubyCrystal
        )

        appState.libraryState.selectedTelegramChatId = demoMainChatId
        appState.libraryState.selectedTelegramChatTitle = "Bebranoid Cloud Music"
        appState.libraryState.selectedTelegramArchiveChatId = demoArchiveChatId
        appState.libraryState.selectedTelegramArchiveChatTitle = "Bebranoid Lossless Archive"

        let demoTracks: [Track] = [
            Track(
                id: "\(demoMainChatId):1001",
                messageId: 1001,
                chatId: demoMainChatId,
                title: "Neon Horizon",
                artist: "Kino & M83",
                album: "Midnight Telemetry",
                year: 2025,
                duration: 244.0,
                filename: "01_Neon_Horizon.flac",
                mimeType: "audio/flac",
                fileSize: 31_457_280,
                dateAdded: now,
                sourceKind: .telegram,
                coverPath: coverMidnight,
                formatInfo: AudioFormatInfo(
                    codec: "FLAC",
                    container: "FLAC",
                    bitrateKbps: 1031,
                    sampleRateHz: 96000,
                    bitsPerSample: 24,
                    channels: 2,
                    lossless: true
                )
            ),
            Track(
                id: "\(demoMainChatId):1002",
                messageId: 1002,
                chatId: demoMainChatId,
                title: "Velvet Echoes (feat. Aurora)",
                artist: "Submotion Orchestra feat. Aurora",
                album: "Velvet Echoes EP",
                year: 2025,
                duration: 218.0,
                filename: "02_Velvet_Echoes.flac",
                mimeType: "audio/flac",
                fileSize: 24_800_000,
                dateAdded: now.addingTimeInterval(-3600),
                sourceKind: .telegram,
                coverPath: coverAurora,
                formatInfo: AudioFormatInfo(
                    codec: "FLAC",
                    container: "FLAC",
                    bitrateKbps: 910,
                    sampleRateHz: 44100,
                    bitsPerSample: 16,
                    channels: 2,
                    lossless: true
                )
            ),
            Track(
                id: "\(demoArchiveChatId):940",
                messageId: 940,
                chatId: demoArchiveChatId,
                title: "Звезда по имени Солнце (Remaster)",
                artist: "Кино",
                album: "Звезда по имени Солнце",
                year: 1989,
                duration: 225.0,
                filename: "03_Zvezda_Po_Imeni_Solntse.flac",
                mimeType: "audio/flac",
                fileSize: 26_120_000,
                dateAdded: now.addingTimeInterval(-7200),
                sourceKind: .telegram,
                isFromArchive: true,
                coverPath: coverKino,
                formatInfo: AudioFormatInfo(
                    codec: "FLAC",
                    container: "FLAC",
                    bitrateKbps: 952,
                    sampleRateHz: 44100,
                    bitsPerSample: 16,
                    channels: 2,
                    lossless: true
                )
            ),
            Track(
                id: "youtube:dQw4w9WgXcQ",
                title: "Solaris Drift (Live Modular Session)",
                artist: "Bebra Synth Lab x Carbon Based",
                album: "YouTube Sessions",
                year: 2026,
                duration: 312.0,
                filename: "youtube-dQw4w9WgXcQ.m4a",
                mimeType: "audio/mp4",
                fileSize: 10_485_760,
                dateAdded: now.addingTimeInterval(-10800),
                sourceKind: .youtube,
                coverPath: coverYouTube,
                youtubeVideoId: "dQw4w9WgXcQ",
                youtubeUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                formatInfo: AudioFormatInfo(
                    codec: "AAC",
                    container: "M4A",
                    bitrateKbps: 256,
                    sampleRateHz: 48000,
                    bitsPerSample: 16,
                    channels: 2,
                    lossless: false
                )
            ),
            Track(
                id: "\(demoMainChatId):1005",
                messageId: 1005,
                chatId: demoMainChatId,
                title: "Pale Blue Dot",
                artist: "Max Cooper, Rival Consoles",
                album: "Emergence",
                year: 2024,
                duration: 289.0,
                filename: "05_Pale_Blue_Dot.flac",
                mimeType: "audio/flac",
                fileSize: 33_200_000,
                dateAdded: now.addingTimeInterval(-14400),
                sourceKind: .telegram,
                coverPath: coverEmergence,
                formatInfo: AudioFormatInfo(
                    codec: "FLAC",
                    container: "FLAC",
                    bitrateKbps: 920,
                    sampleRateHz: 48000,
                    bitsPerSample: 24,
                    channels: 2,
                    lossless: true
                )
            )
        ]

        // 2. Создаём реальные локальные аудиофайлы в кеше для первых 3 треков
        for (idx, track) in demoTracks.prefix(3).enumerated() {
            seedPlayableAudioCacheFile(for: track, frequencyHz: 220.0 + Double(idx) * 110.0, storage: storage)
        }

        // 3. Сохраняем обложки альбомов и прогреваем кэш ArtworkService
        appState.libraryState.customAlbumCovers = [
            AppConfig.favoritesAlbumName: coverFavorites,
            "Midnight Telemetry": coverMidnight,
            "Velvet Echoes EP": coverAurora,
            "Звезда по имени Солнце": coverKino,
            "YouTube Sessions": coverYouTube,
            "Emergence": coverEmergence
        ]

        for track in demoTracks {
            if let path = track.coverPath {
                let url = URL(fileURLWithPath: path)
                _ = ArtworkService.shared.loadPlatformImage(from: url, tier: .listThumbnail)
                _ = ArtworkService.shared.loadPlatformImage(from: url, tier: .grid384)
                _ = ArtworkService.shared.loadPlatformImage(from: url, tier: .playerFull)
            }
        }

        appState.libraryState.tracks = demoTracks
        appState.libraryState.favoriteTrackFilenames = [
            demoTracks[0].cacheKey,
            demoTracks[2].cacheKey
        ]
        appState.libraryState.playCounts = [
            demoTracks[0].cacheKey: 42,
            demoTracks[1].cacheKey: 19,
            demoTracks[2].cacheKey: 87,
            demoTracks[3].cacheKey: 12
        ]
        appState.libraryState.playlists = [
            Playlist(
                id: "demo-playlist-synth",
                name: "Ночной Синтвейв & Lossless",
                kind: .userCustom,
                trackFilenames: [demoTracks[0].cacheKey, demoTracks[1].cacheKey, demoTracks[4].cacheKey],
                tracksSnapshot: [demoTracks[0], demoTracks[1], demoTracks[4]],
                customCoverPath: coverMidnight,
                createdAt: now
            ),
            Playlist(
                id: "demo-playlist-yt",
                name: "YouTube Ambient Live",
                kind: .youtube,
                trackFilenames: [demoTracks[3].cacheKey],
                tracksSnapshot: [demoTracks[3]],
                sourceUrl: "https://www.youtube.com/playlist?list=PLBebranoidDemo01",
                youtubePlaylistId: "PLBebranoidDemo01",
                customCoverPath: coverYouTube,
                lastSyncedAt: now,
                createdAt: now
            )
        ]

        appState.queue = demoTracks
        appState.originalQueueSource = demoTracks
        appState.currentIndex = 0
        appState.currentTrack = demoTracks[0]
        appState.duration = demoTracks[0].duration
        appState.currentTime = 46.4
        appState.isPlaying = true

        // Заполняем синхронизированную по словам караоке-лирику с переводом на русский
        let rawEnhancedLRC = """
        [00:12.00] <00:12.00>Through <00:13.10>the <00:13.80>violet <00:15.20>horizon <00:17.00>we <00:17.80>drift
        [00:20.00] <00:20.00>City <00:21.20>lights <00:22.40>dissolve <00:24.00>into <00:25.10>sound
        [00:44.00] <00:44.00>Hold <00:44.90>the <00:45.60>signal <00:47.10>across <00:48.50>the <00:49.20>night
        [00:52.00] <00:52.00>Every <00:53.20>wave <00:54.50>returns <00:56.00>in <00:56.80>time
        [01:02.00] <01:02.00>Звёзды <01:03.40>тают <01:04.80>над <01:05.60>утренней <01:07.20>рекой
        """
        var parsedDoc = LRCParser.parseLRC(rawEnhancedLRC)
        let demoTranslations = [
            "Сквозь фиолетовый горизонт мы плывём",
            "Огни города растворяются в звуке",
            "Удерживай сигнал сквозь ночь",
            "Каждая волна возвращается вовремя",
            "Stars melt above the morning river"
        ]
        for idx in parsedDoc.lines.indices where idx < demoTranslations.count {
            parsedDoc.lines[idx].translation = demoTranslations[idx]
        }
        appState.currentLyricsDocument = parsedDoc
        appState.currentBeautifulNodes = BeautifulLyricsTransform.transform(document: parsedDoc)
        appState.showLyricsTranslation = true

        // Применяем палитру из реальной обложки активного трека либо эталонную фикстуру HarmonoidMeshBackground
        if let explicitFixture = requestedMeshFixture {
            let rgba = HarmonoidMeshFixtures.makeRGBA64x64(for: explicitFixture)
            let rawPalette = HarmonoidMeshEngine.extractCoverPalette(fromRGBA: rgba)
            appState.currentPalette = HarmonoidMeshEngine.mapPaletteToMeshColors(rawPalette)
            appState.accentRGB = HarmonoidMeshEngine.pickAccentFromPalette(rawPalette)
        } else {
            appState.updatePalette(for: demoTracks[0])
        }
        appState.demoFixedMeshTime = requestedMeshTime

        // Маршрутизация экрана по аргументу `--screen=...` (все 10 экранов визуально и побайтово уникальны)
        switch requestedScreen {
        case "library":
            appState.selectedTab = 0
            appState.demoDirectScreenOverride = "library"
        case "tracks", nil:
            appState.selectedTab = 0
            appState.demoDirectScreenOverride = nil
        case "albums":
            appState.selectedTab = 1
            appState.demoDirectScreenOverride = nil
        case "artists":
            appState.selectedTab = 2
            appState.demoDirectScreenOverride = nil
        case "playlists":
            appState.selectedTab = 3
            appState.demoDirectScreenOverride = nil
        case "settings":
            appState.selectedTab = 4
            appState.demoDirectScreenOverride = nil
        case "player":
            appState.demoDirectScreenOverride = "player"
        case "lyrics":
            appState.demoDirectScreenOverride = "lyrics"
        case "queue":
            appState.demoDirectScreenOverride = "queue"
        case "mini-player":
            appState.selectedTab = 0
            appState.currentIndex = 1
            appState.currentTrack = demoTracks[1]
            appState.duration = demoTracks[1].duration
            appState.currentTime = 118.5
            appState.audioFXMode = .slowedReverb
            appState.bassBoostEnabled = true
            if requestedMeshFixture == nil {
                appState.updatePalette(for: demoTracks[1])
            }
            appState.demoDirectScreenOverride = "mini-player"
        case "diagnostics":
            appState.demoDirectScreenOverride = "diagnostics"
        default:
            appState.selectedTab = 0
            appState.demoDirectScreenOverride = nil
        }
    }

    // MARK: - Real Raster Cover Generation (600x600 JPEG on Disk)

    private enum DemoCoverTheme {
        case synthwaveHorizon
        case emeraldAurora
        case constructivistSun
        case modularSunset
        case cobaltPrism
        case rubyCrystal
    }

    private static func generateDemoCoverOnDisk(filename: String, theme: DemoCoverTheme) -> String {
        let coversDir = StorageManager.shared.coversDirectory
        try? FileManager.default.createDirectory(at: coversDir, withIntermediateDirectories: true)
        let targetURL = coversDir.appendingPathComponent(filename)

        let size = 600
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return targetURL.path
        }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)

        let colors: (top: [CGFloat], mid: [CGFloat], bot: [CGFloat], accent: [CGFloat], secondary: [CGFloat])
        switch theme {
        case .synthwaveHorizon:
            colors = (
                top: [0.09, 0.04, 0.24, 1.0],
                mid: [0.46, 0.10, 0.58, 1.0],
                bot: [0.96, 0.24, 0.56, 1.0],
                accent: [1.00, 0.78, 0.28, 1.0],
                secondary: [0.18, 0.88, 0.98, 1.0]
            )
        case .emeraldAurora:
            colors = (
                top: [0.03, 0.16, 0.20, 1.0],
                mid: [0.07, 0.48, 0.44, 1.0],
                bot: [0.16, 0.82, 0.62, 1.0],
                accent: [0.98, 0.86, 0.42, 1.0],
                secondary: [0.42, 0.96, 0.88, 1.0]
            )
        case .constructivistSun:
            colors = (
                top: [0.12, 0.05, 0.06, 1.0],
                mid: [0.58, 0.11, 0.14, 1.0],
                bot: [0.88, 0.28, 0.16, 1.0],
                accent: [1.00, 0.82, 0.22, 1.0],
                secondary: [0.98, 0.48, 0.18, 1.0]
            )
        case .modularSunset:
            colors = (
                top: [0.16, 0.08, 0.28, 1.0],
                mid: [0.72, 0.24, 0.34, 1.0],
                bot: [0.98, 0.58, 0.20, 1.0],
                accent: [1.00, 0.92, 0.56, 1.0],
                secondary: [0.52, 0.84, 1.00, 1.0]
            )
        case .cobaltPrism:
            colors = (
                top: [0.04, 0.09, 0.26, 1.0],
                mid: [0.10, 0.34, 0.72, 1.0],
                bot: [0.18, 0.74, 0.94, 1.0],
                accent: [0.72, 0.94, 1.00, 1.0],
                secondary: [0.56, 0.38, 0.98, 1.0]
            )
        case .rubyCrystal:
            colors = (
                top: [0.18, 0.04, 0.16, 1.0],
                mid: [0.64, 0.10, 0.38, 1.0],
                bot: [0.96, 0.32, 0.54, 1.0],
                accent: [1.00, 0.84, 0.68, 1.0],
                secondary: [0.98, 0.54, 0.82, 1.0]
            )
        }

        // 1. Фоновый линейный градиент
        let gradComponents = colors.top + colors.mid + colors.bot
        let locations: [CGFloat] = [0.0, 0.52, 1.0]
        if let gradient = CGGradient(colorSpace: colorSpace, colorComponents: gradComponents, locations: locations, count: 3) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: CGFloat(size)),
                end: CGPoint(x: CGFloat(size), y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // 2. Световой радиальный ореол (Центральное солнце / призма)
        let glowComponents = [
            colors.accent[0], colors.accent[1], colors.accent[2], 0.88,
            colors.secondary[0], colors.secondary[1], colors.secondary[2], 0.32,
            0.0, 0.0, 0.0, 0.0
        ]
        if let radial = CGGradient(colorSpace: colorSpace, colorComponents: glowComponents, locations: [0.0, 0.5, 1.0], count: 3) {
            let center = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.54)
            ctx.drawRadialGradient(
                radial,
                startCenter: center,
                startRadius: 12,
                endCenter: center,
                endRadius: CGFloat(size) * 0.44,
                options: []
            )
        }

        // 3. Уникальная геометрическая графика для каждого альбома
        ctx.saveGState()
        switch theme {
        case .synthwaveHorizon:
            // Солнечный диск с полосами и перспективная сетка
            ctx.setFillColor(red: colors.accent[0], green: colors.accent[1], blue: colors.accent[2], alpha: 0.92)
            ctx.fillEllipse(in: CGRect(x: 170, y: 210, width: 260, height: 260))
            ctx.setStrokeColor(red: colors.secondary[0], green: colors.secondary[1], blue: colors.secondary[2], alpha: 0.55)
            ctx.setLineWidth(3.0)
            for i in 0..<9 {
                let y = CGFloat(60 + i * 22)
                ctx.move(to: CGPoint(x: 40, y: y))
                ctx.addLine(to: CGPoint(x: 560, y: y))
            }
            ctx.strokePath()

        case .emeraldAurora:
            // Концентрические звуковые кольца и призма
            for ring in 1...6 {
                let r = CGFloat(ring * 42)
                ctx.setStrokeColor(red: colors.accent[0], green: colors.accent[1], blue: colors.accent[2], alpha: CGFloat(0.75 - Double(ring) * 0.09))
                ctx.setLineWidth(4.5)
                ctx.strokeEllipse(in: CGRect(x: 300 - r, y: 300 - r, width: r * 2, height: r * 2))
            }

        case .constructivistSun:
            // Лучи звезды и геометрический диск
            ctx.setStrokeColor(red: colors.accent[0], green: colors.accent[1], blue: colors.accent[2], alpha: 0.85)
            ctx.setLineWidth(8.0)
            for angleIdx in 0..<12 {
                let angle = Double(angleIdx) * (.pi / 6.0)
                let x2 = 300.0 + cos(angle) * 250.0
                let y2 = 300.0 + sin(angle) * 250.0
                ctx.move(to: CGPoint(x: 300, y: 300))
                ctx.addLine(to: CGPoint(x: x2, y: y2))
            }
            ctx.strokePath()
            ctx.setFillColor(red: colors.accent[0], green: colors.accent[1], blue: colors.accent[2], alpha: 0.95)
            ctx.fillEllipse(in: CGRect(x: 210, y: 210, width: 180, height: 180))

        case .modularSunset:
            // Эквалайзер / осциллограмма
            ctx.setFillColor(red: colors.accent[0], green: colors.accent[1], blue: colors.accent[2], alpha: 0.88)
            for bar in 0..<16 {
                let barH = CGFloat(90 + ((bar * 47) % 240))
                let barX = CGFloat(76 + bar * 28)
                let barY = (600.0 - barH) * 0.5
                ctx.fill(CGRect(x: barX, y: barY, width: 16, height: barH))
            }

        case .cobaltPrism:
            // Кристаллическая решётка
            ctx.setStrokeColor(red: colors.accent[0], green: colors.accent[1], blue: colors.accent[2], alpha: 0.82)
            ctx.setLineWidth(4.0)
            for step in 0..<7 {
                let inset = CGFloat(80 + step * 30)
                let box = CGRect(x: inset, y: inset, width: 600 - inset * 2, height: 600 - inset * 2)
                ctx.stroke(box)
            }

        case .rubyCrystal:
            // Диагональные грани рубина
            ctx.setFillColor(red: colors.accent[0], green: colors.accent[1], blue: colors.accent[2], alpha: 0.82)
            ctx.fillEllipse(in: CGRect(x: 160, y: 160, width: 280, height: 280))
            ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.65)
            ctx.setLineWidth(5.0)
            ctx.strokeEllipse(in: CGRect(x: 130, y: 130, width: 340, height: 340))
        }
        ctx.restoreGState()

        // 4. Декоративная виниловая рамка обложки
        ctx.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24)
        ctx.setLineWidth(6.0)
        ctx.stroke(rect.insetBy(dx: 18, dy: 18))

        #if canImport(UIKit)
        if let cgImage = ctx.makeImage() {
            let uiImage = UIImage(cgImage: cgImage)
            if let jpegData = uiImage.jpegData(compressionQuality: 0.92) {
                try? jpegData.write(to: targetURL, options: .atomic)
            }
        }
        #endif

        return targetURL.path
    }

    // MARK: - Playable WAV Audio Cache Seeding

    private static func seedPlayableAudioCacheFile(for track: Track, frequencyHz: Double, storage: StorageManager) {
        let destURL = storage.cachedAudioFileURL(for: track)
        if !FileManager.default.fileExists(atPath: destURL.path) {
            let wavData = makeStereoSineWaveWAV(frequencyHz: frequencyHz, durationSeconds: 2.5, sampleRate: 44100)
            try? wavData.write(to: destURL, options: .atomic)
        }
        CacheIndexManager.shared.registerCachedFile(for: track, fileURL: destURL)
    }

    public static func makeStereoSineWaveWAV(frequencyHz: Double, durationSeconds: Double, sampleRate: Int = 44100) -> Data {
        let totalFrames = max(1, Int(Double(sampleRate) * durationSeconds))
        let channels = 2
        let bytesPerSample = 2
        let blockAlign = channels * bytesPerSample
        let byteRate = sampleRate * blockAlign
        let dataChunkSize = totalFrames * blockAlign
        let riffChunkSize = 36 + dataChunkSize

        var data = Data(capacity: 44 + dataChunkSize)
        data.append(contentsOf: "RIFF".utf8)
        data.append(uint32LE(UInt32(riffChunkSize)))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(uint32LE(16))
        data.append(uint16LE(1)) // PCM
        data.append(uint16LE(UInt16(channels)))
        data.append(uint32LE(UInt32(sampleRate)))
        data.append(uint32LE(UInt32(byteRate)))
        data.append(uint16LE(UInt16(blockAlign)))
        data.append(uint16LE(UInt16(bytesPerSample * 8)))
        data.append(contentsOf: "data".utf8)
        data.append(uint32LE(UInt32(dataChunkSize)))

        var pcmBytes = [UInt8](repeating: 0, count: dataChunkSize)
        for frame in 0..<totalFrames {
            let t = Double(frame) / Double(sampleRate)
            let env = min(1.0, min(t * 20.0, (durationSeconds - t) * 20.0))
            let leftSample = Int16(clamping: Int(sin(2.0 * .pi * frequencyHz * t) * 14000.0 * env))
            let rightSample = Int16(clamping: Int(sin(2.0 * .pi * (frequencyHz * 1.25) * t) * 14000.0 * env))
            let offset = frame * 4
            let uLeft = UInt16(bitPattern: leftSample)
            let uRight = UInt16(bitPattern: rightSample)
            pcmBytes[offset] = UInt8(uLeft & 0xFF)
            pcmBytes[offset + 1] = UInt8((uLeft >> 8) & 0xFF)
            pcmBytes[offset + 2] = UInt8(uRight & 0xFF)
            pcmBytes[offset + 3] = UInt8((uRight >> 8) & 0xFF)
        }
        data.append(contentsOf: pcmBytes)
        return data
    }

    private static func uint16LE(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
    }

    private static func uint32LE(_ v: UInt32) -> [UInt8] {
        [
            UInt8(v & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 24) & 0xFF)
        ]
    }
}
#endif
