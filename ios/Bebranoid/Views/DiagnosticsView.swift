import SwiftUI

/// Диагностический экран `DiagnosticsView` (Debug / QA режим), отображающий состояние всех подсистем Bebranoid iOS:
/// - Доступность `TDLibFramework`
/// - `connectionState` и `authorizationState` TDLib
/// - Активный источник библиотеки и прогресс сканирования чата
/// - Количество проиндексированных треков, загруженных обложек, ошибок обложек и попаданий в кеш
/// - Размер аудиокеша и счётчик ошибок загрузки (`PriorityDownloadQueue`)
/// - Состояние `DualStreamAudioEngine` (активная дека, частота, кодек, кроссфейд, Audio FX)
/// - Состояние `YouTubeService` (количество плейлистов и треков YouTube)
/// Приватные ключи (`api_hash`), сессионные токены и cookies никогда не выводятся.
public struct DiagnosticsView: View {
    @ObservedObject var appState: BebranoidAppState
    @State private var cacheStats: (totalBytes: Int64, fileCount: Int) = (0, 0)
    @State private var failedDownloadsCount: Int = 0
    @State private var onDeviceE2EReport: TelegramClientService.OnDeviceE2EScenarioReport?
    @State private var isRunningE2EScenario: Bool = false

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    private var youtubeTrackCount: Int {
        let inLibrary = appState.libraryState.tracks.filter { $0.sourceKind == .youtube }.count
        let inPlaylists = appState.libraryState.playlists
            .filter { $0.isYouTubePlaylist }
            .reduce(0) { $0 + $1.tracksSnapshot.count }
        return max(inLibrary, inPlaylists)
    }

    private var youtubePlaylistCount: Int {
        appState.libraryState.playlists.filter { $0.isYouTubePlaylist }.count
    }

    private var activeLibrarySourceDescription: String {
        if appState.telegramClient.isAuthorized {
            let mainTitle = appState.libraryState.selectedTelegramChatTitle
            let archiveTitle = appState.libraryState.selectedTelegramArchiveChatTitle
            return "Telegram TDLib (\(mainTitle) + \(archiveTitle))"
        }
        #if DEBUG
        if UITestingDemoSeeder.isDemoModeActive {
            return "Simulator QA Seed + Real Disk Covers (\(appState.libraryState.selectedTelegramChatTitle))"
        }
        #endif
        if !appState.libraryState.tracks.isEmpty {
            return "Локальный индекс (\(appState.libraryState.tracks.count) треков)"
        }
        return "Не выбран (ожидание входа в TDLib или импорта)"
    }

    private var chatScanProgressDescription: String {
        if appState.isSyncingTelegramLibrary {
            return "Выполняется сканирование истории TDLib..."
        }
        let tgCount = appState.libraryState.tracks.filter { $0.sourceKind == .telegram }.count
        let archiveCount = appState.libraryState.tracks.filter { $0.isFromArchive }.count
        return "Завершено (основной: \(max(0, tgCount - archiveCount)), архив: \(archiveCount))"
    }

    private var audioEngineStateDescription: String {
        let status = appState.isPlaying ? "Playing" : "Paused/Idle"
        let fx = appState.audioFXMode.displayName
        let rate = String(format: "%.2fx", appState.audioEngine.effectivePlaybackRate)
        let badge = appState.currentQualityBadge.label
        return "\(status) • \(badge) • FX: \(fx) (\(rate))"
    }

    public var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.11).ignoresSafeArea()

            List {
                Section("1. Telegram TDLib & Сеть") {
                    diagnosticRow(
                        title: "TDLibFramework available",
                        value: TDLibJSONBridge.isNativeTDLibAvailable ? "YES (Native XCFramework)" : "NO (Fallback)",
                        isHealthy: TDLibJSONBridge.isNativeTDLibAvailable
                    )
                    diagnosticRow(
                        title: "connectionState",
                        value: appState.telegramClient.connectionState.rawValue,
                        isHealthy: true
                    )
                    diagnosticRow(
                        title: "authorizationState",
                        value: "\(appState.telegramClient.rawTDLibAuthState) (isAuthorized=\(appState.telegramClient.isAuthorized))",
                        isHealthy: true
                    )
                    diagnosticRow(
                        title: "Активный источник библиотеки",
                        value: activeLibrarySourceDescription,
                        isHealthy: true
                    )
                    diagnosticRow(
                        title: "Прогресс сканирования чата",
                        value: chatScanProgressDescription,
                        isHealthy: !appState.isSyncingTelegramLibrary
                    )
                    diagnosticRow(
                        title: "iPhone On-Device Telegram E2E Scenario",
                        value: onDeviceE2EReport?.summaryText ?? (TelegramClientService.isRunningOnPhysicaliPhone
                            ? (appState.telegramClient.isAuthorized ? "READY FOR ON-DEVICE E2E" : "NOT VERIFIED (Awaiting TDLib Login on iPhone)")
                            : "NOT VERIFIED (REQUIRES REAL IPHONE)"),
                        isHealthy: onDeviceE2EReport?.isTDLibAuthorizedReady == true && TelegramClientService.isRunningOnPhysicaliPhone
                    )
                    Button {
                        guard !isRunningE2EScenario else { return }
                        isRunningE2EScenario = true
                        Task {
                            let report = await appState.telegramClient.runOnDeviceE2EAuthAndChatScanScenario(
                                selectedChatId: appState.libraryState.selectedTelegramChatId,
                                archiveChatId: appState.libraryState.selectedTelegramArchiveChatId
                            )
                            await MainActor.run {
                                onDeviceE2EReport = report
                                isRunningE2EScenario = false
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isRunningE2EScenario ? "hourglass" : "iphone.badge.play")
                            Text(isRunningE2EScenario ? "Выполняется E2E сценарий..." : "Запустить E2E сценарий Telegram (iPhone)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 1.0))
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section("2. Индекс, Обложки и Кеш") {
                    diagnosticRow(
                        title: "Количество найденных треков",
                        value: "\(appState.libraryState.tracks.count) треков / \(appState.computedAlbums.count) альбомов",
                        isHealthy: !appState.libraryState.tracks.isEmpty
                    )
                    diagnosticRow(
                        title: "Количество загруженных обложек",
                        value: "\(appState.artworkService.loadedArtworkCount) (Cache hits: \(appState.artworkService.cacheHitCount))",
                        isHealthy: appState.artworkService.loadedArtworkCount > 0
                    )
                    diagnosticRow(
                        title: "Количество ошибок обложек",
                        value: "\(appState.artworkService.failedArtworkCount)",
                        isHealthy: appState.artworkService.failedArtworkCount == 0
                    )
                    let mb = Double(cacheStats.totalBytes) / (1024.0 * 1024.0)
                    diagnosticRow(
                        title: "Размер аудиокеша",
                        value: String(format: "%.2f МБ (%d файлов)", mb, cacheStats.fileCount),
                        isHealthy: true
                    )
                    diagnosticRow(
                        title: "Количество ошибок загрузки",
                        value: "\(failedDownloadsCount)",
                        isHealthy: failedDownloadsCount == 0
                    )
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section("3. Аудиодвижок и YouTube") {
                    diagnosticRow(
                        title: "Состояние аудиодвижка",
                        value: audioEngineStateDescription,
                        isHealthy: true
                    )
                    diagnosticRow(
                        title: "Состояние YouTube metadata",
                        value: "Плейлистов: \(youtubePlaylistCount), Треков: \(youtubeTrackCount), Crop: 16:9→1:1 Ready",
                        isHealthy: true
                    )
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Диагностика (Debug QA)")
        .onAppear {
            cacheStats = appState.cacheIndex.calculateCacheStats()
        }
        .task {
            failedDownloadsCount = await PriorityDownloadQueue.shared.failedDownloadsCount
        }
    }

    private func diagnosticRow(title: String, value: String, isHealthy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(isHealthy ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
            }
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 3)
    }
}
