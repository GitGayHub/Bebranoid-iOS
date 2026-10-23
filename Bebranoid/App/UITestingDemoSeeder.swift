import Foundation

#if DEBUG
/// Режим детерминированной инициализации только для DEBUG / UI-тестирования в iOS Simulator (`--ui-testing-demo`).
/// Не компилируется в Release и никак не влияет на обычную работу приложения.
/// Заполняет безопасные тестовые метаданные треков, альбомов, артистов, плейлистов, очереди и караоке-лирики,
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
                album: "Midnight Telemetry",
                year: 2025,
                duration: 218.0,
                filename: "02_Velvet_Echoes.flac",
                mimeType: "audio/flac",
                fileSize: 24_800_000,
                dateAdded: now.addingTimeInterval(-3600),
                sourceKind: .telegram,
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

        // Применяем эталонную фикстуру HarmonoidMeshBackground (по умолчанию vividMulticolor)
        let fixtureKind = requestedMeshFixture ?? .vividMulticolor
        let rgba = HarmonoidMeshFixtures.makeRGBA64x64(for: fixtureKind)
        let rawPalette = HarmonoidMeshEngine.extractCoverPalette(fromRGBA: rgba)
        appState.currentPalette = HarmonoidMeshEngine.mapPaletteToMeshColors(rawPalette)
        appState.accentRGB = HarmonoidMeshEngine.pickAccentFromPalette(rawPalette)
        appState.demoFixedMeshTime = requestedMeshTime

        // Маршрутизация экрана по аргументу `--screen=...`
        switch requestedScreen {
        case "library", "tracks", "mini-player", nil:
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
        default:
            appState.selectedTab = 0
            appState.demoDirectScreenOverride = nil
        }
    }
}
#endif
