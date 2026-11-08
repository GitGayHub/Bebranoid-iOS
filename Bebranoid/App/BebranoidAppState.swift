import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class BebranoidAppState: ObservableObject {
    // MARK: - Published Playback & Queue State
    @Published public var currentTrack: Track?
    @Published public var queue: [Track] = []
    @Published public var originalQueueSource: [Track] = []
    @Published public var currentIndex: Int = 0
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: Double = 0.0
    @Published public var duration: Double = 0.0
    @Published public var isShuffleEnabled: Bool = false
    @Published public var repeatMode: RepeatMode = .none

    // MARK: - Audio DSP & Settings State
    @Published public var uiVolume: Double = 0.85 {
        didSet {
            audioEngine.uiVolume = uiVolume
            persistPlaybackSession()
        }
    }
    @Published public var playbackSpeed: Float = 1.0 {
        didSet {
            audioEngine.playbackSpeed = playbackSpeed
            syncNowPlayingInfo()
            persistPlaybackSession()
        }
    }
    @Published public var audioFXMode: AudioFXMode = .normal {
        didSet {
            audioEngine.audioFXMode = audioFXMode
            syncNowPlayingInfo()
            persistPlaybackSession()
        }
    }
    @Published public var bassBoostEnabled: Bool = false {
        didSet {
            audioEngine.bassBoostEnabled = bassBoostEnabled
            persistPlaybackSession()
        }
    }
    @Published public var crossfadeEnabled: Bool = true {
        didSet {
            audioEngine.crossfadeEnabled = crossfadeEnabled
            persistPlaybackSession()
        }
    }
    @Published public var crossfadeDuration: Double = AppConfig.defaultCrossfadeDuration {
        didSet {
            audioEngine.crossfadeDuration = crossfadeDuration
            persistPlaybackSession()
        }
    }

    // MARK: - Harmonoid Mesh Background State
    @Published public var currentPalette: [MeshRGB] = HarmonoidMeshEngine.defaultPalette
    @Published public var nextTrackPalette: [MeshRGB]? = nil
    @Published public var nextTrackAccent: MeshRGB? = nil
    private var preparedNextTrackId: String? = nil
    private var analyzedPaletteCache: [String: (palette: [MeshRGB], meshColors: [MeshRGB], uiAccent: MeshRGB)] = [:]
    private var nowPlayingArtworkDataCache: [String: Data] = [:]
    @Published public var accentRGB: MeshRGB = HarmonoidMeshEngine.defaultAccent
    @Published public var crossfadeProgress: Double = 0.0
    @Published public var isReducedMotionEnabled: Bool = false
    @Published public var isGyroscope3DCoverEnabled: Bool = true {
        didSet {
            if libraryState.isGyroscope3DCoverEnabled != isGyroscope3DCoverEnabled {
                libraryState.isGyroscope3DCoverEnabled = isGyroscope3DCoverEnabled
                saveLibraryState()
            }
        }
    }

    // MARK: - Lyrics & Translation State
    @Published public var lyricsEngine: LyricsEngineKind = .beautiful {
        didSet { persistPlaybackSession() }
    }
    @Published public var lyricsFontSize: LyricsFontSizePreset = .medium {
        didSet { persistPlaybackSession() }
    }
    @Published public var showLyricsTranslation: Bool = false {
        didSet {
            persistPlaybackSession()
            if showLyricsTranslation {
                Task { await ensureCurrentLyricsTranslated() }
            }
        }
    }
    @Published public var currentLyricsDocument: ParsedLyricsDocument = ParsedLyricsDocument(kind: .plain, lines: [])
    @Published public var currentBeautifulNodes: [BeautifulTimelineNode] = []
    @Published public var isLoadingLyrics: Bool = false
    @Published public var isTranslatingLyrics: Bool = false

    // MARK: - Library & Collections State
    @Published public var libraryState: UserLibraryPersistentState {
        didSet { invalidateLibraryCaches() }
    }
    @Published public var trackSortField: TrackSortField = .recent {
        didSet { _cachedFilteredTracks = nil }
    }
    @Published public var trackSortAscending: Bool = false {
        didSet { _cachedFilteredTracks = nil }
    }
    @Published public var showOnlyCachedTracks: Bool = false {
        didSet { _cachedFilteredTracks = nil }
    }
    @Published public var showHiddenAlbums: Bool = false {
        didSet { _cachedAlbums = nil }
    }
    @Published public var searchQuery: String = "" {
        didSet { _cachedFilteredTracks = nil }
    }
    @Published public var trackDownloadProgress: [String: Int] = [:]
    @Published public var pendingDownloadTrack: Track? = nil
    @Published public var pendingDownloadAccentRGB: MeshRGB? = nil
    @Published public var trackDownloadAccents: [String: MeshRGB] = [:]
    @Published public private(set) var isPlaybackIntendedByUser: Bool = false
    private var playbackRequestGeneration: UInt64 = 0
    private var pendingPlaybackTask: Task<Void, Never>? = nil
    private var activeTrackStartTask: Task<Void, Never>? = nil
    @Published public var isBatchDownloadingSelected: Bool = false
    @Published public var batchDownloadDoneCount: Int = 0
    @Published public var batchDownloadTotalCount: Int = 0
    private var batchDownloadTask: Task<Void, Never>? = nil

    private var _cachedFilteredTracks: [Track]?
    private var _cachedAlbums: [Album]?
    private var isHandlingTelegramAuthorized: Bool = false
    private var _cachedArtists: [ArtistSummary]?
    private var _cachedPlaylists: [Playlist]?

    public func invalidateLibraryCaches() {
        _cachedFilteredTracks = nil
        _cachedAlbums = nil
        _cachedArtists = nil
        _cachedPlaylists = nil
    }

    public func downloadProgress(for track: Track?) -> Int? {
        guard let track else { return nil }
        return trackDownloadProgress[track.cacheKey] ?? trackDownloadProgress[track.id]
    }

    // MARK: - Navigation & Modal Presentation State
    @Published public var selectedTab: Int = 0
    @Published public var isFullScreenPlayerPresented: Bool = false
    @Published public var isLyricsScreenPresented: Bool = false
    @Published public var isQueueSheetPresented: Bool = false
    @Published public var isAudioFXSheetPresented: Bool = false
    @Published public var isTelegramAuthPresented: Bool = false
    @Published public var inspectedTrackForInfo: Track? = nil
    @Published public var statusBannerMessage: String? = nil
    @Published public var availableTelegramChats: [TelegramChatSummary] = []
    @Published public var isSyncingTelegramLibrary: Bool = false
    @Published public var telegramScanProgressText: String = ""
    @Published public var isSyncingYouTubePlaylists: Bool = false
    @Published public var youtubeSyncProgressText: String = ""
    @Published public var isVerifyingTelegramAccess: Bool = false
    @Published public var lastTelegramAccessReport: TelegramLiveAccessReport? = nil
    #if DEBUG
    @Published public var demoDirectScreenOverride: String? = nil
    @Published public var demoFixedMeshTime: Double? = nil
    #endif

    // MARK: - Services
    public let audioEngine = DualStreamAudioEngine()
    public let storage = StorageManager.shared
    public let cacheIndex = CacheIndexManager.shared
    public let sessionStore = PlaybackSessionStore.shared
    public let lyricsService = LyricsService.shared
    public let translationService = LyricsTranslationService.shared
    public let telegramClient = TelegramClientService.shared
    public let youtubeService = YouTubeService.shared
    public let artworkService = ArtworkService.shared
    public let nowPlaying = NowPlayingSessionManager.shared
    public let haptics = HapticsManager.shared

    private var cancellables = Set<AnyCancellable>()

    public init() {
        let initialLibrary = PlaybackSessionStore.shared.loadLibraryState()
        self.libraryState = initialLibrary
        self.isGyroscope3DCoverEnabled = initialLibrary.isGyroscope3DCoverEnabled
        bindAudioEngine()
        bindRemoteCommands()
        bindArtworkAndTelegramNotifications()
        #if DEBUG
        if UITestingDemoSeeder.isDemoModeActive {
            UITestingDemoSeeder.applyIfNeeded(to: self)
            return
        }
        #endif
        ensureDefaultYouTubePlaylistRegistered()
        restorePreviousSession()
        if !availableLibraryTracks.isEmpty {
            artworkService.prefetchArtistCovers(artists: computedArtists)
            artworkService.prewarmLibraryListThumbnails(
                tracks: availableLibraryTracks,
                customAlbumCovers: libraryState.customAlbumCovers
            )
        }
        guard !TelegramClientService.isRunningUnderXCTest else { return }
        Task { [weak self] in
            await self?.refreshAllYouTubePlaylists(allowFastIncrementalStop: true)
        }
        Task { [weak self] in
            guard let self else { return }
            await self.telegramClient.initializeAndRestoreSession()
            let latestSaved = PlaybackSessionStore.shared.loadLibraryState()
            if self.libraryState.selectedTelegramChatId.isEmpty {
                self.libraryState.selectedTelegramChatId = latestSaved.selectedTelegramChatId.isEmpty
                    ? AppConfig.defaultPersonalMainChatId
                    : latestSaved.selectedTelegramChatId
                self.libraryState.selectedTelegramChatTitle = latestSaved.selectedTelegramChatTitle.isEmpty
                    ? AppConfig.defaultPersonalMainChatTitle
                    : latestSaved.selectedTelegramChatTitle
            }
            if self.libraryState.selectedTelegramArchiveChatId.isEmpty {
                self.libraryState.selectedTelegramArchiveChatId = latestSaved.selectedTelegramArchiveChatId.isEmpty
                    ? AppConfig.defaultPersonalArchiveChatId
                    : latestSaved.selectedTelegramArchiveChatId
                self.libraryState.selectedTelegramArchiveChatTitle = latestSaved.selectedTelegramArchiveChatTitle.isEmpty
                    ? AppConfig.defaultPersonalArchiveChatTitle
                    : latestSaved.selectedTelegramArchiveChatTitle
            }
            if self.telegramClient.isAuthorized {
                await self.handleTelegramAuthorized()
            }
        }
    }

    public func ensureDefaultYouTubePlaylistRegistered() {
        let defaultId = AppConfig.defaultPersonalYouTubePlaylistId
        let defaultURL = AppConfig.defaultPersonalYouTubePlaylistURL
        let defaultTitle = AppConfig.defaultPersonalYouTubePlaylistTitle
        var didMutate = false

        for idx in libraryState.playlists.indices {
            let pl = libraryState.playlists[idx]
            let parsedSourceId = pl.sourceUrl.flatMap { YouTubeLinkParser.parseInput($0).playlistId }
            let matchesDefault = pl.youtubePlaylistId == defaultId
                || parsedSourceId == defaultId
                || pl.id == "yt_\(defaultId)"
                || pl.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == defaultTitle.lowercased()
            if matchesDefault {
                if libraryState.playlists[idx].kind != .youtube {
                    libraryState.playlists[idx].kind = .youtube
                    didMutate = true
                }
                if libraryState.playlists[idx].youtubePlaylistId != defaultId {
                    libraryState.playlists[idx].youtubePlaylistId = defaultId
                    didMutate = true
                }
                if libraryState.playlists[idx].sourceUrl == nil || libraryState.playlists[idx].sourceUrl?.isEmpty == true {
                    libraryState.playlists[idx].sourceUrl = defaultURL
                    didMutate = true
                }
            }
        }

        if !libraryState.playlists.contains(where: { $0.isYouTubePlaylist }) && !TelegramClientService.isRunningUnderXCTest {
            let newPl = Playlist(
                id: "yt_\(defaultId)",
                name: defaultTitle,
                kind: .youtube,
                sourceUrl: defaultURL,
                youtubePlaylistId: defaultId
            )
            libraryState.playlists.append(newPl)
            libraryState.playlistShufflePreferences[newPl.id] = PlaylistShufflePreference()
            didMutate = true
        }

        if didMutate {
            invalidateLibraryCaches()
            saveLibraryState()
        }
    }

    private func bindArtworkAndTelegramNotifications() {
        NotificationCenter.default.publisher(for: .artworkDidResolve)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self else { return }
                let resolvedTrackId = note.userInfo?["trackId"] as? String
                if let pending = self.pendingDownloadTrack, resolvedTrackId == pending.id {
                    self.resolveDownloadAccent(for: pending)
                }
                if let current = self.currentTrack, resolvedTrackId == current.id {
                    if self.pendingDownloadTrack?.id != current.id {
                        self.updatePalette(for: current)
                    }
                    self.syncNowPlayingInfo()
                }
                if let nextIdx = self.peekNextTrackIndex(),
                   nextIdx < self.queue.count,
                   resolvedTrackId == self.queue[nextIdx].id {
                    self.prepareNextTrackPalette(for: self.queue[nextIdx])
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .telegramAuthStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self else { return }
                self.invalidateLibraryCaches()
                if !self.telegramClient.isAuthorized {
                    self.queue = self.queue.filter { $0.sourceKind != .telegram || self.cacheIndex.isCached($0) }
                    if let cur = self.currentTrack, cur.sourceKind == .telegram && !self.cacheIndex.isCached(cur) {
                        self.audioEngine.pause()
                        self.currentTrack = self.queue.first
                        self.currentIndex = 0
                    }
                }
                self.objectWillChange.send()
                if let step = note.object as? TelegramAuthStepState, step == .authorized {
                    Task { await self.handleTelegramAuthorized() }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .trackDownloadProgressDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self,
                      let cacheKey = note.userInfo?["cacheKey"] as? String else { return }
                if let pct = note.userInfo?["percent"] as? Int {
                    if self.trackDownloadProgress[cacheKey] != pct {
                        self.trackDownloadProgress[cacheKey] = pct
                    }
                    if self.trackDownloadAccents[cacheKey] == nil,
                       let matched = self.queue.first(where: { $0.cacheKey == cacheKey || $0.id == cacheKey })
                            ?? self.libraryState.tracks.first(where: { $0.cacheKey == cacheKey || $0.id == cacheKey }) {
                        self.resolveDownloadAccent(for: matched)
                    }
                } else {
                    self.trackDownloadProgress.removeValue(forKey: cacheKey)
                    self.invalidateLibraryCaches()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .telegramScanProgressDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self,
                      let text = note.userInfo?["text"] as? String else { return }
                self.telegramScanProgressText = text
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .telegramNewMessageReceived)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self,
                      let rawMsg = note.userInfo?["rawMessage"] as? RawTelegramAudioMessage,
                      let chatId = note.userInfo?["chatId"] as? String else { return }
                let normIncoming = AppConfig.normalizeTelegramChatId(chatId)
                let normMain = AppConfig.normalizeTelegramChatId(self.libraryState.selectedTelegramChatId)
                let normArchive = AppConfig.normalizeTelegramChatId(self.libraryState.selectedTelegramArchiveChatId)
                guard !normIncoming.isEmpty,
                      (normIncoming == normMain || normIncoming == normArchive) else { return }
                let isArchive = (!normArchive.isEmpty && normIncoming == normArchive && normIncoming != normMain)
                var newTrack = TelegramScanner.buildTrack(from: rawMsg, isFromArchive: isArchive)
                if newTrack.chatId == nil || newTrack.chatId?.isEmpty == true {
                    newTrack.chatId = isArchive ? self.libraryState.selectedTelegramArchiveChatId : self.libraryState.selectedTelegramChatId
                }
                self.mergeIncomingTelegramTracksIntoLibrary([newTrack])
            }
            .store(in: &cancellables)
    }

    public func effectiveAccentRGB(extraProgress: Double = 0.0) -> MeshRGB {
        let blend = max(crossfadeProgress, extraProgress)
        if blend > 0.001, let nextAcc = nextTrackAccent {
            let e = HarmonoidMeshEngine.smoothstep(0.0, 1.0, blend)
            return HarmonoidMeshEngine.lerpColor(accentRGB, nextAcc, t: e)
        }
        return accentRGB
    }

    public var accentSwiftUIColor: Color {
        let norm = effectiveAccentRGB().normalizedDouble
        return Color(red: norm.r, green: norm.g, blue: norm.b)
    }

    /// Акцентный цвет скачивающегося трека (по его собственной обложке, например розовый),
    /// в то время как весь остальной интерфейс остаётся в цвете текущего играющего трека (например зелёного) до окончания загрузки.
    public func downloadAccentColor(for track: Track? = nil) -> Color {
        if let track {
            if let rgb = trackDownloadAccents[track.id] ?? trackDownloadAccents[track.cacheKey] {
                let norm = rgb.normalizedDouble
                return Color(red: norm.r, green: norm.g, blue: norm.b)
            }
        }
        if let pending = pendingDownloadTrack,
           let rgb = trackDownloadAccents[pending.id] ?? trackDownloadAccents[pending.cacheKey] {
            let norm = rgb.normalizedDouble
            return Color(red: norm.r, green: norm.g, blue: norm.b)
        }
        if let pendingRGB = pendingDownloadAccentRGB {
            let norm = pendingRGB.normalizedDouble
            return Color(red: norm.r, green: norm.g, blue: norm.b)
        }
        return accentSwiftUIColor
    }

    public var isCurrentLyricsCyrillic: Bool {
        guard !currentLyricsDocument.lines.isEmpty else { return false }
        return LyricsTranslationService.isPredominantlyCyrillic(currentLyricsDocument.lines.map(\.text))
    }

    public var currentQualityBadge: QualityBadgeInfo {
        let format = audioEngine.currentFormatInfo
            ?? currentTrack?.formatInfo
            ?? AudioFormatInfo.fallbackFromFilename(currentTrack?.filename ?? "track.flac", fileSize: currentTrack?.fileSize, duration: duration)
        return format.computeQualityBadge()
    }

    // MARK: - Engine & System Bindings

    private func bindAudioEngine() {
        audioEngine.$isPlaying
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                self?.isPlaying = playing
                self?.syncNowPlayingInfo()
            }
            .store(in: &cancellables)

        audioEngine.$currentTime
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                guard let self else { return }
                // Все анимированные индикаторы (лирика, слайдер плеера, мини-плеер) читают `audioEngine.livePlaybackTime` локально,
                // поэтому глобальный `@Published currentTime` обновляется редко (0.5–1.0 с), исключая перегрев CPU от перерисовки всего дерева View!
                let minDelta: Double = (self.isFullScreenPlayerPresented || self.isLyricsScreenPresented) ? 0.50 : 1.0
                if abs(time - self.currentTime) >= minDelta || time < 0.05 {
                    self.currentTime = time
                }
            }
            .store(in: &cancellables)

        audioEngine.$duration
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] dur in
                self?.duration = dur
            }
            .store(in: &cancellables)

        audioEngine.$crossfadeProgress
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] prog in
                self?.crossfadeProgress = prog
            }
            .store(in: &cancellables)

        audioEngine.onRequestNextTrackForCrossfade = { [weak self] in
            guard let self, let nextIdx = self.peekNextTrackIndex(), nextIdx < self.queue.count else {
                return nil
            }
            let nextTrack = self.queue[nextIdx]
            guard self.cacheIndex.isCached(nextTrack) else { return nil }
            let url = self.storage.cachedAudioFileURL(for: nextTrack)
            Task { @MainActor [weak self] in
                self?.prepareNextTrackPalette(for: nextTrack)
            }
            return (nextTrack, url)
        }

        audioEngine.onCrossfadeCompleted = { [weak self] promotedTrack in
            guard let self else { return }
            if let nextIdx = self.peekNextTrackIndex() {
                self.currentIndex = nextIdx
            }
            self.currentTrack = promotedTrack
            if let nextPal = self.nextTrackPalette {
                self.currentPalette = nextPal
                self.accentRGB = self.nextTrackAccent ?? HarmonoidMeshEngine.defaultAccent
                self.nextTrackPalette = nil
                self.nextTrackAccent = nil
            } else {
                self.updatePalette(for: promotedTrack)
            }
            self.loadLyricsForCurrentTrack()
            self.prefetchUpcomingTrack()
            self.syncNowPlayingInfo()
            self.persistPlaybackSession()
        }

        audioEngine.onTrackNaturallyEnded = { [weak self] in
            guard let self, self.isPlaybackIntendedByUser else { return }
            if self.repeatMode == .one {
                self.seek(to: 0)
                self.audioEngine.play()
            } else {
                self.skipToNext(isManualUserAction: false)
            }
        }

        audioEngine.onPlayCountThresholdReached = { [weak self] track in
            self?.incrementPlayCount(for: track)
        }
    }

    private func bindRemoteCommands() {
        nowPlaying.configureRemoteCommandsIfNeeded()
        nowPlaying.onPlayCommand = { [weak self] in
            guard let self else { return }
            self.isPlaybackIntendedByUser = true
            if let cur = self.currentTrack, !self.cacheIndex.isCached(cur) {
                self.startPlayingCurrentIndex(autoPlay: true, initialSeek: self.currentTime)
            } else {
                self.audioEngine.play()
            }
        }
        nowPlaying.onPauseCommand = { [weak self] in
            guard let self else { return }
            self.cancelAllPendingPlaybackStarts(clearIntendedPlayback: true)
            self.audioEngine.pause()
        }
        nowPlaying.onTogglePlayPauseCommand = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNextTrackCommand = { [weak self] in self?.skipToNext(isManualUserAction: true) }
        nowPlaying.onPreviousTrackCommand = { [weak self] in self?.skipToPrevious() }
        nowPlaying.onSeekCommand = { [weak self] target in self?.seek(to: target) }
        nowPlaying.onToggleLikeCommand = { [weak self] in
            if let track = self?.currentTrack {
                self?.toggleFavorite(track: track)
            }
        }
    }

    // MARK: - Playback Actions

    public func cancelAllPendingPlaybackStarts(clearIntendedPlayback: Bool = true) {
        if clearIntendedPlayback {
            isPlaybackIntendedByUser = false
        }
        playbackRequestGeneration &+= 1
        pendingPlaybackTask?.cancel()
        pendingPlaybackTask = nil
        activeTrackStartTask?.cancel()
        activeTrackStartTask = nil
        if let pending = pendingDownloadTrack {
            trackDownloadProgress.removeValue(forKey: pending.cacheKey)
        }
        pendingDownloadTrack = nil
        pendingDownloadAccentRGB = nil
    }

    public func cancelPendingTrackDownload() {
        cancelAllPendingPlaybackStarts(clearIntendedPlayback: false)
    }

    public func playTrack(_ track: Track, in contextQueue: [Track]? = nil) {
        haptics.lightTap()
        isPlaybackIntendedByUser = true
        let baseQueue = (contextQueue?.isEmpty == false) ? contextQueue! : (queue.isEmpty ? availableLibraryTracks : queue)
        let targetOriginalSource = baseQueue
        var targetQueue: [Track]
        var targetIndex: Int

        if let foundIndex = baseQueue.firstIndex(where: { $0.id == track.id }) {
            targetQueue = baseQueue
            targetIndex = foundIndex
        } else {
            targetQueue = [track] + baseQueue
            targetIndex = 0
        }

        if isShuffleEnabled {
            targetQueue = QueueOrder.reshuffleUpcoming(
                queue: targetQueue,
                currentIndex: targetIndex,
                sourceTracks: targetOriginalSource
            )
        }

        // Если другой трек сейчас уже открыт/играет, а выбранный трек ещё не скачан —
        // НЕ перехватываем плеер! Оставляем текущий трек играть и доступным в плеере,
        // вычисляем собственный акцентный цвет скачивающегося трека для обводки загрузки
        // и переключаем всё приложение на новый трек и его палитру сразу после скачивания.
        if !cacheIndex.isCached(track), let activeCurrent = currentTrack, activeCurrent.id != track.id {
            pendingPlaybackTask?.cancel()
            activeTrackStartTask?.cancel()
            activeTrackStartTask = nil
            playbackRequestGeneration &+= 1
            let requestGen = playbackRequestGeneration
            pendingDownloadTrack = track
            resolveDownloadAccent(for: track)

            pendingPlaybackTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let fileURL = try await self.telegramClient.ensureTrackDownloaded(
                        track: track,
                        priority: .activePlayback
                    )
                    guard !Task.isCancelled,
                          self.playbackRequestGeneration == requestGen,
                          self.isPlaybackIntendedByUser,
                          self.pendingDownloadTrack?.id == track.id else { return }
                    self.pendingDownloadTrack = nil
                    self.pendingDownloadAccentRGB = nil
                    self.pendingPlaybackTask = nil
                    self.audioEngine.stopImmediatelyForTrackSwitch()
                    self.originalQueueSource = targetOriginalSource
                    self.queue = targetQueue
                    self.currentIndex = targetIndex
                    self.currentTrack = track
                    self.currentTime = 0.0
                    self.duration = track.duration
                    self.artworkService.invalidateCachedSyncPath(forTrackId: track.id, cacheKey: track.cacheKey)
                    self.updatePalette(for: track)
                    self.loadLyricsForCurrentTrack()
                    self.persistPlaybackSession()
                    let shouldAutoPlayNow = self.isPlaybackIntendedByUser
                    _ = await self.audioEngine.loadAndPlay(track: track, fileURL: fileURL, startAt: 0, autoPlay: shouldAutoPlayNow)
                    self.updatePalette(for: track)
                    self.syncNowPlayingInfo()
                    self.prefetchUpcomingTrack()
                } catch {
                    if !Task.isCancelled, self.pendingDownloadTrack?.id == track.id {
                        self.pendingDownloadTrack = nil
                        self.pendingDownloadAccentRGB = nil
                        self.pendingPlaybackTask = nil
                        self.statusBannerMessage = error.localizedDescription
                    }
                }
            }
            return
        }

        cancelPendingTrackDownload()
        originalQueueSource = targetOriginalSource
        queue = targetQueue
        currentIndex = targetIndex
        startPlayingCurrentIndex(autoPlay: true)
    }

    public func togglePlayPause() {
        haptics.lightTap()
        if isPlaying || pendingPlaybackTask != nil || (activeTrackStartTask != nil && isPlaybackIntendedByUser) {
            cancelAllPendingPlaybackStarts(clearIntendedPlayback: true)
            audioEngine.pause()
            syncNowPlayingInfo()
            return
        }
        if currentTrack == nil, let first = queue.first ?? availableLibraryTracks.first {
            playTrack(first)
            return
        }
        isPlaybackIntendedByUser = true
        if let cur = currentTrack, !cacheIndex.isCached(cur) {
            startPlayingCurrentIndex(autoPlay: true, initialSeek: currentTime)
            return
        }
        audioEngine.play()
        syncNowPlayingInfo()
    }

    public func seek(to timeSeconds: Double) {
        let clamped = max(0.0, timeSeconds)
        currentTime = clamped
        audioEngine.seek(to: clamped)
        syncNowPlayingInfo()
        persistPlaybackSession()
    }

    public func skipToNext(isManualUserAction: Bool = true) {
        if isManualUserAction {
            haptics.lightTap()
            audioEngine.cancelActiveCrossfade()
        }
        cancelPendingTrackDownload()
        guard !queue.isEmpty else { return }

        if currentIndex + 1 < queue.count {
            currentIndex += 1
            startPlayingCurrentIndex(autoPlay: true)
        } else if repeatMode == .all {
            currentIndex = 0
            startPlayingCurrentIndex(autoPlay: true)
        } else {
            cancelAllPendingPlaybackStarts(clearIntendedPlayback: true)
            audioEngine.pause()
            seek(to: 0)
        }
    }

    public func skipToPrevious() {
        haptics.lightTap()
        audioEngine.cancelActiveCrossfade()
        cancelPendingTrackDownload()
        if currentTime > 3.5 {
            seek(to: 0)
            return
        }
        skipToPreviousTrackForced()
    }

    /// Переключение строго на предыдущий трек (используется при свайпе диска вправо в полноэкранном плеере)
    public func skipToPreviousTrackForced() {
        haptics.lightTap()
        audioEngine.cancelActiveCrossfade()
        cancelPendingTrackDownload()
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
            startPlayingCurrentIndex(autoPlay: true)
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
            startPlayingCurrentIndex(autoPlay: true)
        } else {
            seek(to: 0)
        }
    }

    public func toggleShuffle() {
        haptics.softSelection()
        isShuffleEnabled.toggle()
        if isShuffleEnabled {
            queue = QueueOrder.reshuffleUpcoming(
                queue: queue,
                currentIndex: currentIndex,
                sourceTracks: originalQueueSource.isEmpty ? queue : originalQueueSource
            )
        } else if !originalQueueSource.isEmpty, let current = currentTrack {
            queue = originalQueueSource
            currentIndex = queue.firstIndex(where: { $0.id == current.id }) ?? 0
        }
        prefetchUpcomingTrack()
        persistPlaybackSession()
    }

    public func cycleRepeatMode() {
        haptics.softSelection()
        switch repeatMode {
        case .none: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .none
        }
        prefetchUpcomingTrack()
        persistPlaybackSession()
    }

    /// Шаффл всей медиатеки с учётом исключённых альбомов (`excludedShuffleAlbums`), скрытых альбомов и лимитов YouTube-плейлистов (`playlistPreferences`)
    public func shuffleAllEligibleLibrary() {
        haptics.mediumImpact()
        cancelPendingTrackDownload()
        var pool: [Track] = []
        var seenKeys = Set<String>()

        for track in availableLibraryTracks {
            if libraryState.hiddenAlbums.contains(track.album) || libraryState.excludedShuffleAlbums.contains(track.album) {
                continue
            }
            let key = QueueOrder.trackKey(track)
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                pool.append(track)
            }
        }

        for playlist in libraryState.playlists where playlist.isYouTubePlaylist {
            let pref = libraryState.playlistShufflePreferences[playlist.id]
            let eligible = PlaylistPreferencesEngine.eligiblePlaylistTracks(tracks: playlist.tracksSnapshot, preference: pref)
            for track in eligible {
                let key = QueueOrder.trackKey(track)
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    pool.append(track)
                }
            }
        }

        guard !pool.isEmpty else { return }
        let randomStartIdx = Int.random(in: 0..<pool.count)
        let starter = pool[randomStartIdx]
        isShuffleEnabled = true
        originalQueueSource = pool
        queue = [starter] + pool.enumerated().compactMap { $0.offset == randomStartIdx ? nil : $0.element }
        currentIndex = 0
        queue = QueueOrder.reshuffleUpcoming(queue: queue, currentIndex: 0, sourceTracks: pool)
        startPlayingCurrentIndex(autoPlay: true)
    }

    private func peekNextTrackIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if currentIndex + 1 < queue.count {
            return currentIndex + 1
        }
        if repeatMode == .all {
            return 0
        }
        return nil
    }

    private func peekPreviousTrackIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if currentIndex > 0 {
            return currentIndex - 1
        }
        if repeatMode == .all {
            return queue.count - 1
        }
        return nil
    }

    public var upcomingNextTrack: Track? {
        guard let idx = peekNextTrackIndex(), idx >= 0, idx < queue.count else { return nil }
        return queue[idx]
    }

    public var adjacentPreviousTrack: Track? {
        guard let idx = peekPreviousTrackIndex(), idx >= 0, idx < queue.count else { return nil }
        return queue[idx]
    }

    private func startPlayingCurrentIndex(autoPlay: Bool, initialSeek: Double = 0) {
        guard currentIndex >= 0, currentIndex < queue.count else { return }
        let track = queue[currentIndex]

        pendingPlaybackTask?.cancel()
        pendingPlaybackTask = nil
        activeTrackStartTask?.cancel()
        activeTrackStartTask = nil
        playbackRequestGeneration &+= 1
        let requestGen = playbackRequestGeneration

        if autoPlay {
            isPlaybackIntendedByUser = true
            audioEngine.stopImmediatelyForTrackSwitch()
        }

        let needsDownload = !cacheIndex.isCached(track)
        let hadPreviousTrack = (currentTrack != nil)

        currentTrack = track
        currentTime = max(0.0, initialSeek)
        duration = track.duration

        if needsDownload && autoPlay {
            pendingDownloadTrack = track
            resolveDownloadAccent(for: track)
            if !hadPreviousTrack {
                updatePalette(for: track)
            }
        } else if preparedNextTrackId == track.id,
                  let preloadedPal = nextTrackPalette,
                  let preloadedAcc = nextTrackAccent {
            currentPalette = preloadedPal
            accentRGB = preloadedAcc
            nextTrackPalette = nil
            nextTrackAccent = nil
            preparedNextTrackId = nil
        } else {
            updatePalette(for: track)
        }
        loadLyricsForCurrentTrack()
        persistPlaybackSession()

        activeTrackStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var fileURL: URL
                let wasAlreadyCached = self.cacheIndex.isCached(track)
                if wasAlreadyCached {
                    fileURL = self.storage.cachedAudioFileURL(for: track)
                } else {
                    guard autoPlay, self.isPlaybackIntendedByUser else { return }
                    fileURL = try await self.telegramClient.ensureTrackDownloaded(track: track, priority: .activePlayback)
                }
                guard !Task.isCancelled,
                      self.playbackRequestGeneration == requestGen,
                      self.currentTrack?.id == track.id,
                      (!autoPlay || self.isPlaybackIntendedByUser) else { return }
                if self.pendingDownloadTrack?.id == track.id {
                    self.pendingDownloadTrack = nil
                    self.pendingDownloadAccentRGB = nil
                }
                self.artworkService.invalidateCachedSyncPath(forTrackId: track.id, cacheKey: track.cacheKey)
                self.updatePalette(for: track)
                let shouldAutoPlayNow = autoPlay && self.isPlaybackIntendedByUser
                var played = await self.audioEngine.loadAndPlay(track: track, fileURL: fileURL, startAt: initialSeek, autoPlay: shouldAutoPlayNow)
                if !played && wasAlreadyCached && !Task.isCancelled && self.playbackRequestGeneration == requestGen && self.currentTrack?.id == track.id && shouldAutoPlayNow {
                    try? FileManager.default.removeItem(at: fileURL)
                    self.cacheIndex.rebuildIndex()
                    self.pendingDownloadTrack = track
                    self.resolveDownloadAccent(for: track)
                    fileURL = try await self.telegramClient.ensureTrackDownloaded(track: track, priority: .activePlayback)
                    guard !Task.isCancelled,
                          self.playbackRequestGeneration == requestGen,
                          self.currentTrack?.id == track.id,
                          self.isPlaybackIntendedByUser else { return }
                    if self.pendingDownloadTrack?.id == track.id {
                        self.pendingDownloadTrack = nil
                        self.pendingDownloadAccentRGB = nil
                    }
                    played = await self.audioEngine.loadAndPlay(track: track, fileURL: fileURL, startAt: initialSeek, autoPlay: self.isPlaybackIntendedByUser)
                }
                self.updatePalette(for: track)
                self.syncNowPlayingInfo()
                self.prefetchUpcomingTrack()
            } catch {
                if self.pendingDownloadTrack?.id == track.id {
                    self.pendingDownloadTrack = nil
                    self.pendingDownloadAccentRGB = nil
                }
                if !Task.isCancelled, self.playbackRequestGeneration == requestGen, self.currentTrack?.id == track.id {
                    self.statusBannerMessage = error.localizedDescription
                }
            }
        }
    }

    public func openTelegramAuthSheet() {
        haptics.softSelection()
        if isFullScreenPlayerPresented {
            isFullScreenPlayerPresented = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                isTelegramAuthPresented = false
                try? await Task.sleep(nanoseconds: 40_000_000)
                isTelegramAuthPresented = true
            }
        } else {
            isTelegramAuthPresented = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 25_000_000)
                isTelegramAuthPresented = true
            }
        }
    }

    private func prefetchUpcomingTrack() {
        guard let nextIdx = peekNextTrackIndex(), nextIdx < queue.count else {
            nextTrackPalette = nil
            nextTrackAccent = nil
            return
        }
        let nextTrack = queue[nextIdx]
        prepareNextTrackPalette(for: nextTrack)
        // Заранее определяем наличие/отсутствие текста у следующего трека, чтобы кнопка «Текст» появлялась или скрывалась мгновенно
        let nextDisabled = isLyricsDisabled(for: nextTrack)
        if !nextDisabled, lyricsService.loadCachedLyrics(for: nextTrack) == nil {
            let nextLocalURL = cacheIndex.isCached(nextTrack) ? storage.cachedAudioFileURL(for: nextTrack) : nil
            Task.detached(priority: .utility) { [lyricsService] in
                _ = await lyricsService.resolveLyrics(
                    for: nextTrack,
                    localFileURL: nextLocalURL,
                    isDisabledForTrack: false
                )
            }
        }
        guard (isPlaying || isPlaybackIntendedByUser), !cacheIndex.isCached(nextTrack) else { return }

        Task.detached { [weak self, telegramClient] in
            if (try? await telegramClient.ensureTrackDownloaded(track: nextTrack, priority: .nextTrackPrefetch)) != nil {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.artworkService.invalidateCachedSyncPath(forTrackId: nextTrack.id, cacheKey: nextTrack.cacheKey)
                    if let currentNextIdx = self.peekNextTrackIndex(),
                       currentNextIdx < self.queue.count,
                       self.queue[currentNextIdx].id == nextTrack.id {
                        self.prepareNextTrackPalette(for: nextTrack)
                    }
                }
            }
        }
    }

    // MARK: - Harmonoid Mesh Palette Resolution

    nonisolated private static func analyzeLocalArtworkURLOffMain(_ localURL: URL) -> (palette: [MeshRGB], meshColors: [MeshRGB], uiAccent: MeshRGB)? {
        if let cgImage = ArtworkService.shared.loadCGImage(from: localURL, tier: .meshAnalysis) {
            return HarmonoidMeshEngine.analyzeCoverImage(cgImage)
        }
        #if canImport(UIKit)
        if let uiImage = UIImage(contentsOfFile: localURL.path),
           let cgImage = uiImage.cgImage {
            return HarmonoidMeshEngine.analyzeCoverImage(cgImage)
        }
        #endif
        return nil
    }

    /// Асинхронно вычисляет акцентный цвет обложки скачивающегося трека (например розовый),
    /// не меняя `currentPalette` и `accentRGB` текущего играющего трека (например зелёного) до завершения скачивания.
    public func resolveDownloadAccent(for track: Track) {
        if let existing = trackDownloadAccents[track.id] ?? trackDownloadAccents[track.cacheKey] {
            if pendingDownloadTrack?.id == track.id {
                pendingDownloadAccentRGB = existing
            }
            return
        }

        if let resolvedHit = artworkService.resolveLocalCoverURLSync(
            for: track,
            customAlbumCovers: libraryState.customAlbumCovers,
            siblingTracks: libraryState.tracks
        ) {
            let hitPath = resolvedHit.url.path
            if let cached = analyzedPaletteCache[hitPath] {
                trackDownloadAccents[track.id] = cached.uiAccent
                trackDownloadAccents[track.cacheKey] = cached.uiAccent
                if pendingDownloadTrack?.id == track.id {
                    pendingDownloadAccentRGB = cached.uiAccent
                }
                return
            }
            let hitURL = resolvedHit.url
            let targetId = track.id
            let targetKey = track.cacheKey
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let analyzed = Self.analyzeLocalArtworkURLOffMain(hitURL) else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.analyzedPaletteCache[hitPath] = analyzed
                    self.trackDownloadAccents[targetId] = analyzed.uiAccent
                    self.trackDownloadAccents[targetKey] = analyzed.uiAccent
                    if self.pendingDownloadTrack?.id == targetId {
                        self.pendingDownloadAccentRGB = analyzed.uiAccent
                    }
                }
            }
            return
        }

        let customCovers = libraryState.customAlbumCovers
        let siblings = libraryState.tracks
        let targetId = track.id
        let targetKey = track.cacheKey
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let resolved = await ArtworkService.shared.resolveArtwork(
                for: track,
                customAlbumCovers: customCovers,
                siblingTracks: siblings
            ), let fileURL = resolved.fileURL else { return }
            let filePath = fileURL.path
            guard let analyzed = Self.analyzeLocalArtworkURLOffMain(fileURL) else { return }
            await MainActor.run {
                guard let self else { return }
                self.analyzedPaletteCache[filePath] = analyzed
                self.trackDownloadAccents[targetId] = analyzed.uiAccent
                self.trackDownloadAccents[targetKey] = analyzed.uiAccent
                if self.pendingDownloadTrack?.id == targetId {
                    self.pendingDownloadAccentRGB = analyzed.uiAccent
                }
            }
        }
    }

    public func updatePalette(for track: Track?) {
        guard let track else {
            currentPalette = HarmonoidMeshEngine.defaultPalette
            accentRGB = HarmonoidMeshEngine.defaultAccent
            return
        }

        if let resolvedHit = artworkService.resolveLocalCoverURLSync(
            for: track,
            customAlbumCovers: libraryState.customAlbumCovers,
            siblingTracks: libraryState.tracks
        ) {
            let hitPath = resolvedHit.url.path
            if let cached = analyzedPaletteCache[hitPath] {
                currentPalette = cached.meshColors
                accentRGB = cached.uiAccent
                return
            }
            let hitURL = resolvedHit.url
            let targetTrackId = track.id
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let analyzed = Self.analyzeLocalArtworkURLOffMain(hitURL) else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.analyzedPaletteCache[hitPath] = analyzed
                    if self.currentTrack?.id == targetTrackId {
                        self.currentPalette = analyzed.meshColors
                        self.accentRGB = analyzed.uiAccent
                    }
                }
            }
            return
        }

        // Спокойная нейтральная графитово-серебристая база до завершения декодирования реальной обложки (без случайного жёлтого/фиолетового!)
        currentPalette = HarmonoidMeshEngine.monochromePalette
        accentRGB = HarmonoidMeshEngine.monochromeAccent

        // Запускаем асинхронное разрешение реальной обложки (embedded / Telegram / YouTube) вне главного потока
        let customCovers = libraryState.customAlbumCovers
        let siblings = libraryState.tracks
        let targetTrackId = track.id
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let resolved = await ArtworkService.shared.resolveArtwork(
                for: track,
                customAlbumCovers: customCovers,
                siblingTracks: siblings
            ), let fileURL = resolved.fileURL else { return }
            let filePath = fileURL.path
            let analyzed = Self.analyzeLocalArtworkURLOffMain(fileURL)
            guard let analyzed else { return }
            await MainActor.run {
                guard let self else { return }
                self.analyzedPaletteCache[filePath] = analyzed
                if self.currentTrack?.id == targetTrackId {
                    self.currentPalette = analyzed.meshColors
                    self.accentRGB = analyzed.uiAccent
                }
            }
        }
    }

    private func prepareNextTrackPalette(for nextTrack: Track) {
        if let resolvedHit = artworkService.resolveLocalCoverURLSync(
            for: nextTrack,
            customAlbumCovers: libraryState.customAlbumCovers,
            siblingTracks: libraryState.tracks
        ) {
            let hitPath = resolvedHit.url.path
            if let cached = analyzedPaletteCache[hitPath] {
                preparedNextTrackId = nextTrack.id
                nextTrackPalette = cached.meshColors
                nextTrackAccent = cached.uiAccent
                return
            }
            let hitURL = resolvedHit.url
            let nextTrackId = nextTrack.id
            Task.detached(priority: .utility) { [weak self] in
                guard let analyzed = Self.analyzeLocalArtworkURLOffMain(hitURL) else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.analyzedPaletteCache[hitPath] = analyzed
                    if let currentNextIdx = self.peekNextTrackIndex(),
                       currentNextIdx < self.queue.count,
                       self.queue[currentNextIdx].id == nextTrackId {
                        self.preparedNextTrackId = nextTrackId
                        self.nextTrackPalette = analyzed.meshColors
                        self.nextTrackAccent = analyzed.uiAccent
                    }
                }
            }
            return
        }

        let customCovers = libraryState.customAlbumCovers
        let siblings = libraryState.tracks
        let nextTrackId = nextTrack.id
        Task.detached(priority: .utility) { [weak self] in
            guard let resolved = await ArtworkService.shared.resolveArtwork(
                for: nextTrack,
                customAlbumCovers: customCovers,
                siblingTracks: siblings
            ), let fileURL = resolved.fileURL else { return }
            let filePath = fileURL.path
            guard let analyzed = Self.analyzeLocalArtworkURLOffMain(fileURL) else { return }
            await MainActor.run {
                guard let self else { return }
                self.analyzedPaletteCache[filePath] = analyzed
                if let currentNextIdx = self.peekNextTrackIndex(),
                   currentNextIdx < self.queue.count,
                   self.queue[currentNextIdx].id == nextTrackId {
                    self.preparedNextTrackId = nextTrackId
                    self.nextTrackPalette = analyzed.meshColors
                    self.nextTrackAccent = analyzed.uiAccent
                }
            }
        }
    }

    nonisolated public static func deterministicSeedPalette(for key: String) -> [MeshRGB] {
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let baseHueDeg = Double(hash % 360)
        return [
            HarmonoidMeshEngine.hsvToRgb(baseHueDeg, 0.72, 0.58, score: 40.0),
            HarmonoidMeshEngine.hsvToRgb((baseHueDeg + 28.0).truncatingRemainder(dividingBy: 360.0), 0.78, 0.64, score: 32.0),
            HarmonoidMeshEngine.hsvToRgb((baseHueDeg + 316.0).truncatingRemainder(dividingBy: 360.0), 0.70, 0.54, score: 24.0),
            HarmonoidMeshEngine.hsvToRgb((baseHueDeg + 58.0).truncatingRemainder(dividingBy: 360.0), 0.62, 0.68, score: 18.0)
        ]
    }

    // MARK: - Lyrics & Translation Loading

    public func isLyricsDisabled(for track: Track) -> Bool {
        libraryState.disabledLyricsTrackIds.contains(track.id)
    }

    public func toggleLyricsDisabled(for track: Track) {
        haptics.softSelection()
        if libraryState.disabledLyricsTrackIds.contains(track.id) {
            libraryState.disabledLyricsTrackIds.remove(track.id)
        } else {
            libraryState.disabledLyricsTrackIds.insert(track.id)
        }
        saveLibraryState()
        if currentTrack?.id == track.id {
            loadLyricsForCurrentTrack()
        }
    }

    public func loadLyricsForCurrentTrack() {
        guard let track = currentTrack else {
            currentLyricsDocument = ParsedLyricsDocument(kind: .plain, lines: [])
            currentBeautifulNodes = []
            return
        }

        let disabled = isLyricsDisabled(for: track)
        if disabled {
            currentLyricsDocument = ParsedLyricsDocument(kind: .plain, lines: [])
            currentBeautifulNodes = []
            isLoadingLyrics = false
            if isLyricsScreenPresented {
                isLyricsScreenPresented = false
            }
            return
        }

        // Синхронная мгновенная проверка кеша (0 мс): если известно, что у трека нет текста (`source == "none"`),
        // или текст уже в кеше, сразу выставляем состояние без малейшей задержки и без спиннера!
        if let syncCached = lyricsService.loadCachedLyrics(for: track) {
            if syncCached.source == "none" {
                currentLyricsDocument = ParsedLyricsDocument(kind: .plain, lines: [])
                currentBeautifulNodes = []
                isLoadingLyrics = false
                if isLyricsScreenPresented {
                    isLyricsScreenPresented = false
                }
                return
            }
            let raw = syncCached.syncedLyrics ?? syncCached.plainLyrics
            var doc = LRCParser.parseLRC(raw)
            if let translations = syncCached.translatedLines {
                doc = LyricsService.attachTranslations(translations, to: doc)
            }
            if !doc.lines.isEmpty {
                currentLyricsDocument = doc
                currentBeautifulNodes = BeautifulLyricsTransform.transform(document: doc)
                isLoadingLyrics = false
                if showLyricsTranslation {
                    Task { await ensureCurrentLyricsTranslated() }
                }
                return
            }
        }

        // Сбрасываем текст предыдущего трека сразу, чтобы кнопка «Текст» не светилась на песнях без лирики
        currentLyricsDocument = ParsedLyricsDocument(kind: .plain, lines: [])
        currentBeautifulNodes = []
        isLoadingLyrics = true
        let localURL = cacheIndex.isCached(track) ? storage.cachedAudioFileURL(for: track) : nil

        Task {
            let resolved = await lyricsService.resolveLyrics(
                for: track,
                localFileURL: localURL,
                isDisabledForTrack: false
            )
            guard currentTrack?.id == track.id else { return }
            currentLyricsDocument = resolved.document
            currentBeautifulNodes = BeautifulLyricsTransform.transform(document: resolved.document)
            isLoadingLyrics = false
            if resolved.document.lines.isEmpty && isLyricsScreenPresented {
                isLyricsScreenPresented = false
            }

            if showLyricsTranslation {
                await ensureCurrentLyricsTranslated()
            }
        }
    }

    public func ensureCurrentLyricsTranslated() async {
        guard let track = currentTrack,
              !currentLyricsDocument.lines.isEmpty,
              !isCurrentLyricsCyrillic,
              !currentLyricsDocument.lines.contains(where: { $0.translation != nil }) else {
            return
        }

        isTranslatingLyrics = true
        let result = await translationService.translateDocumentToRussian(currentLyricsDocument)
        guard currentTrack?.id == track.id else {
            isTranslatingLyrics = false
            return
        }
        currentLyricsDocument = result.document
        currentBeautifulNodes = BeautifulLyricsTransform.transform(document: result.document)
        isTranslatingLyrics = false

        if var cached = lyricsService.loadCachedLyrics(for: track), !result.translatedLines.isEmpty {
            cached.translatedLines = result.translatedLines
            lyricsService.saveCachedLyrics(cached)
        }
    }

    // MARK: - Library Queries & Mutations

    public func isFavorite(_ track: Track) -> Bool {
        libraryState.favoriteTrackFilenames.contains(track.cacheKey) || libraryState.favoriteTrackFilenames.contains(track.filename)
    }

    public func toggleFavorite(track: Track) {
        haptics.mediumImpact()
        let key = track.cacheKey
        if libraryState.favoriteTrackFilenames.contains(key) {
            libraryState.favoriteTrackFilenames.remove(key)
        } else {
            libraryState.favoriteTrackFilenames.insert(key)
        }
        saveLibraryState()
    }

    public func incrementPlayCount(for track: Track) {
        let key = track.cacheKey
        libraryState.playCounts[key, default: 0] += 1
        saveLibraryState()
    }

    public func playCount(for track: Track) -> Int {
        libraryState.playCounts[track.cacheKey] ?? 0
    }

    /// Треки, доступные для воспроизведения прямо сейчас:
    /// до входа в Telegram скрывает облачные незакешированные треки, чтобы не показывать невоспроизводимую «фейковую» медиатеку.
    public var availableLibraryTracks: [Track] {
        #if DEBUG
        if UITestingDemoSeeder.isDemoModeActive {
            return libraryState.tracks
        }
        #endif
        if telegramClient.isAuthorized {
            return libraryState.tracks
        }
        return libraryState.tracks.filter { $0.sourceKind != .telegram || cacheIndex.isCached($0) }
    }

    public var hiddenCloudTracksCount: Int {
        max(0, libraryState.tracks.count - availableLibraryTracks.count)
    }

    /// Пакетное скачивание выбранных пользователем треков в локальный офлайн-кэш
    public func downloadTracksToCache(_ tracks: [Track]) {
        let missing = tracks.filter { !cacheIndex.isCached($0) }
        guard !missing.isEmpty else {
            haptics.softSelection()
            return
        }
        haptics.mediumImpact()
        batchDownloadTask?.cancel()
        isBatchDownloadingSelected = true
        batchDownloadDoneCount = 0
        batchDownloadTotalCount = missing.count

        batchDownloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for track in missing {
                if Task.isCancelled { break }
                if !self.cacheIndex.isCached(track) {
                    self.resolveDownloadAccent(for: track)
                    _ = try? await self.telegramClient.ensureTrackDownloaded(
                        track: track,
                        priority: .nextTrackPrefetch
                    )
                }
                if Task.isCancelled { break }
                self.batchDownloadDoneCount += 1
                self.invalidateLibraryCaches()
            }
            self.isBatchDownloadingSelected = false
            self.invalidateLibraryCaches()
        }
    }

    public func cancelBatchDownload() {
        batchDownloadTask?.cancel()
        batchDownloadTask = nil
        isBatchDownloadingSelected = false
    }

    public var filteredAndSortedTracks: [Track] {
        if let cached = _cachedFilteredTracks {
            return cached
        }
        var result = availableLibraryTracks

        if showOnlyCachedTracks {
            result = result.filter { cacheIndex.isCached($0) }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                $0.album.lowercased().contains(query) ||
                $0.filename.lowercased().contains(query)
            }
        }

        result.sort { a, b in
            let comparison: Bool
            switch trackSortField {
            case .recent:
                if a.dateAdded != b.dateAdded {
                    comparison = a.dateAdded > b.dateAdded
                } else {
                    comparison = (a.messageId ?? 0) > (b.messageId ?? 0)
                }
            case .title:
                comparison = a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .artist:
                comparison = a.artist.localizedCaseInsensitiveCompare(b.artist) == .orderedAscending
            case .album:
                comparison = a.album.localizedCaseInsensitiveCompare(b.album) == .orderedAscending
            case .year:
                comparison = (a.year ?? 0) > (b.year ?? 0)
            case .plays:
                comparison = playCount(for: a) > playCount(for: b)
            }
            return trackSortAscending ? !comparison : comparison
        }

        _cachedFilteredTracks = result
        return result
    }

    public var computedAlbums: [Album] {
        if let cached = _cachedAlbums {
            return cached
        }
        var albums: [Album] = []
        let sourceTracks = availableLibraryTracks

        // 1. Виртуальный альбом «Любимые» ВСЕГДА на первом месте (`src/views/Albums.jsx` lines 366-385),
        // собирая лайкнутые треки из медиатеки и всех плейлистов YouTube без дубликатов
        var favSeen = Set<String>()
        var favTracks: [Track] = []
        for track in sourceTracks where isFavorite(track) {
            if favSeen.insert(track.cacheKey).inserted {
                favTracks.append(track)
            }
        }
        for playlist in libraryState.playlists {
            for track in playlist.tracksSnapshot where isFavorite(track) {
                if favSeen.insert(track.cacheKey).inserted {
                    favTracks.append(track)
                }
            }
        }
        favTracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        albums.append(
            Album(
                name: AppConfig.favoritesAlbumName,
                artist: "Ваши избранные треки",
                tracks: favTracks,
                customCoverPath: libraryState.customAlbumCovers[AppConfig.favoritesAlbumName],
                isFavoriteVirtualAlbum: true,
                isLikedFavorite: true,
                isHidden: false,
                isExcludedFromShuffle: false
            )
        )

        // 2. Лайкнутые плейлисты закрепляются сразу на первых местах в разделе «Альбомы»
        let likedPlaylists = libraryState.playlists.filter { libraryState.favoritePlaylistIds.contains($0.id) }
        for pl in likedPlaylists {
            albums.append(
                Album(
                    name: pl.name,
                    artist: pl.isYouTubePlaylist ? "YouTube плейлист • Избранное" : "Плейлист • Избранное",
                    tracks: pl.tracksSnapshot,
                    customCoverPath: pl.customCoverPath,
                    explicitRemoteArtworkURL: pl.remoteArtworkURL,
                    isFavoriteVirtualAlbum: false,
                    isLikedFavorite: true,
                    linkedPlaylistId: pl.id,
                    isHidden: false,
                    isExcludedFromShuffle: false
                )
            )
        }

        // 3. Реальные альбомы из треков (лайкнутые альбомы наверху, затем строгий алфавитный порядок A–Z как в Desktop)
        var grouped: [String: [Track]] = [:]
        for track in sourceTracks {
            var name = track.album.isEmpty ? "Без альбома" : track.album
            if name == AppConfig.favoritesAlbumName {
                name = "\(AppConfig.favoritesAlbumName) (библиотека)"
            }
            grouped[name, default: []].append(track)
        }

        var pinnedRegularAlbums: [Album] = []
        var standardAlbums: [Album] = []

        for (albumName, rawTracks) in grouped {
            let isHidden = libraryState.hiddenAlbums.contains(albumName)
            if isHidden && !showHiddenAlbums {
                continue
            }

            var orderedTracks = rawTracks
            if let savedOrder = libraryState.albumTrackOrders[albumName], !savedOrder.isEmpty {
                let orderMap = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($1, $0) })
                orderedTracks.sort { a, b in
                    let idxA = orderMap[a.cacheKey] ?? Int.max
                    let idxB = orderMap[b.cacheKey] ?? Int.max
                    if idxA != idxB { return idxA < idxB }
                    return a.title.localizedStandardCompare(b.title) == .orderedAscending
                }
            } else {
                orderedTracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }

            let dominantArtist = orderedTracks.first?.artist ?? "Разные исполнители"
            let isLiked = libraryState.favoriteAlbumNames.contains(albumName)
            let built = Album(
                name: albumName,
                artist: dominantArtist,
                tracks: orderedTracks,
                customCoverPath: libraryState.customAlbumCovers[albumName],
                isFavoriteVirtualAlbum: false,
                isLikedFavorite: isLiked,
                isHidden: isHidden,
                isExcludedFromShuffle: libraryState.excludedShuffleAlbums.contains(albumName)
            )
            if isLiked {
                pinnedRegularAlbums.append(built)
            } else {
                standardAlbums.append(built)
            }
        }

        pinnedRegularAlbums.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        standardAlbums.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        albums.append(contentsOf: pinnedRegularAlbums)
        albums.append(contentsOf: standardAlbums)

        _cachedAlbums = albums
        return albums
    }

    public var computedArtists: [ArtistSummary] {
        if let cached = _cachedArtists {
            return cached
        }
        let result = ArtistSplitter.buildArtistSummaries(
            tracks: availableLibraryTracks,
            favoriteArtistKeys: libraryState.favoriteArtistKeys
        )
        _cachedArtists = result
        return result
    }

    public var allPlaylistsWithRecent30: [Playlist] {
        if let cached = _cachedPlaylists {
            return cached
        }
        let recentTracks = Array(
            availableLibraryTracks
                .sorted { ($0.messageId ?? 0) > ($1.messageId ?? 0) }
                .prefix(30)
        )
        let recentAuto = Playlist(
            id: AppConfig.recent30PlaylistId,
            name: AppConfig.recent30PlaylistName,
            kind: .recentAuto,
            trackFilenames: recentTracks.map { $0.cacheKey },
            tracksSnapshot: recentTracks,
            customCoverPath: recentTracks.first?.coverPath
        )
        let liked = libraryState.playlists.filter { libraryState.favoritePlaylistIds.contains($0.id) }
        let unliked = libraryState.playlists.filter { !libraryState.favoritePlaylistIds.contains($0.id) }
        let result = liked + [recentAuto] + unliked
        _cachedPlaylists = result
        return result
    }

    public func isFavoriteAlbum(_ albumName: String) -> Bool {
        if albumName == AppConfig.favoritesAlbumName { return true }
        return libraryState.favoriteAlbumNames.contains(albumName)
    }

    public func toggleFavoriteAlbum(_ albumName: String) {
        guard albumName != AppConfig.favoritesAlbumName else { return }
        haptics.mediumImpact()
        if libraryState.favoriteAlbumNames.contains(albumName) {
            libraryState.favoriteAlbumNames.remove(albumName)
        } else {
            libraryState.favoriteAlbumNames.insert(albumName)
        }
        saveLibraryState()
    }

    public func isFavoritePlaylist(_ playlistId: String) -> Bool {
        libraryState.favoritePlaylistIds.contains(playlistId)
    }

    public func toggleFavoritePlaylist(_ playlistId: String) {
        guard playlistId != AppConfig.recent30PlaylistId else { return }
        haptics.mediumImpact()
        if libraryState.favoritePlaylistIds.contains(playlistId) {
            libraryState.favoritePlaylistIds.remove(playlistId)
        } else {
            libraryState.favoritePlaylistIds.insert(playlistId)
        }
        saveLibraryState()
    }

    /// Обновление конкретного плейлиста (pull-to-refresh внутри YouTube-плейлиста или «Последние 30»):
    /// начинает с самых последних добавленных треков (1-я страница мгновенно), а при неполном плейлисте догружает все 2500+ треков целиком.
    public func refreshPlaylist(_ playlist: Playlist) async {
        if playlist.isYouTubePlaylist {
            let source = playlist.sourceUrl ?? (playlist.youtubePlaylistId.map { "https://www.youtube.com/playlist?list=\($0)" } ?? "")
            guard !source.isEmpty else { return }
            isSyncingYouTubePlaylists = true
            youtubeSyncProgressText = "Обновление \(playlist.name)..."
            defer {
                isSyncingYouTubePlaylists = false
                youtubeSyncProgressText = ""
            }
            do {
                try await importYouTubeURL(source, customTitle: playlist.name, allowFastIncrementalStop: true)
            } catch {
                statusBannerMessage = error.localizedDescription
            }
        } else if telegramClient.isAuthorized {
            await syncTelegramLibrary()
        }
    }

    public func refreshAllYouTubePlaylists(allowFastIncrementalStop: Bool = true) async {
        ensureDefaultYouTubePlaylistRegistered()
        let ytPlaylists = libraryState.playlists.filter { $0.isYouTubePlaylist }
        guard !ytPlaylists.isEmpty else { return }
        isSyncingYouTubePlaylists = true
        youtubeSyncProgressText = "Синхронизация YouTube..."
        defer {
            isSyncingYouTubePlaylists = false
            youtubeSyncProgressText = ""
        }
        for pl in ytPlaylists {
            let source = pl.sourceUrl ?? (pl.youtubePlaylistId.map { "https://www.youtube.com/playlist?list=\($0)" } ?? "")
            guard !source.isEmpty else { continue }
            do {
                try await importYouTubeURL(
                    source,
                    customTitle: pl.name,
                    allowFastIncrementalStop: allowFastIncrementalStop
                )
            } catch {
                statusBannerMessage = error.localizedDescription
            }
        }
    }

    /// Полное обновление медиатеки и всех подключённых YouTube-плейлистов параллельно (pull-to-refresh или кнопка обновления)
    public func refreshFullLibraryAndYouTubePlaylists() async {
        haptics.softSelection()
        async let ytTask: Void = refreshAllYouTubePlaylists(allowFastIncrementalStop: true)
        if telegramClient.isAuthorized {
            await syncTelegramLibrary()
        }
        await ytTask
        invalidateLibraryCaches()
        artworkService.prefetchArtistCovers(artists: computedArtists)
    }

    public func toggleAlbumHidden(_ albumName: String) {
        haptics.softSelection()
        if libraryState.hiddenAlbums.contains(albumName) {
            libraryState.hiddenAlbums.remove(albumName)
        } else {
            libraryState.hiddenAlbums.insert(albumName)
        }
        saveLibraryState()
    }

    public func toggleAlbumExcludedFromShuffle(_ albumName: String) {
        haptics.softSelection()
        if libraryState.excludedShuffleAlbums.contains(albumName) {
            libraryState.excludedShuffleAlbums.remove(albumName)
        } else {
            libraryState.excludedShuffleAlbums.insert(albumName)
        }
        saveLibraryState()
    }

    public func toggleFavoriteArtist(_ normalizedKey: String) {
        haptics.softSelection()
        if libraryState.favoriteArtistKeys.contains(normalizedKey) {
            libraryState.favoriteArtistKeys.remove(normalizedKey)
        } else {
            libraryState.favoriteArtistKeys.insert(normalizedKey)
        }
        saveLibraryState()
    }

    public func createCustomPlaylist(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let playlist = Playlist(name: trimmed, kind: .userCustom)
        libraryState.playlists.append(playlist)
        saveLibraryState()
    }

    public func deletePlaylist(id: String) {
        guard id != AppConfig.recent30PlaylistId else { return }
        libraryState.playlists.removeAll { $0.id == id }
        libraryState.playlistShufflePreferences.removeValue(forKey: id)
        saveLibraryState()
    }

    public func addTrack(_ track: Track, toPlaylistId playlistId: String) {
        guard let idx = libraryState.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if !libraryState.playlists[idx].trackFilenames.contains(track.cacheKey) {
            libraryState.playlists[idx].trackFilenames.append(track.cacheKey)
            libraryState.playlists[idx].tracksSnapshot.append(track)
            saveLibraryState()
        }
    }

    private func findMatchingYouTubePlaylistIndex(for playlistId: String) -> Int? {
        guard !playlistId.isEmpty else { return nil }
        return libraryState.playlists.firstIndex(where: { pl in
            if pl.youtubePlaylistId == playlistId || pl.id == "yt_\(playlistId)" {
                return true
            }
            if let src = pl.sourceUrl, YouTubeLinkParser.parseInput(src).playlistId == playlistId {
                return true
            }
            return false
        })
    }

    public func importYouTubeURL(
        _ input: String,
        customTitle: String = "",
        allowFastIncrementalStop: Bool = false
    ) async throws {
        let parsedInput = YouTubeLinkParser.parseInput(input)
        let targetPlaylistId = parsedInput.playlistId
        let existingKnownVideoIds: Set<String> = {
            guard let pid = targetPlaylistId,
                  let idx = findMatchingYouTubePlaylistIndex(for: pid) else {
                return []
            }
            return Set(libraryState.playlists[idx].tracksSnapshot.compactMap { $0.youtubeVideoId })
        }()

        let result = try await youtubeService.fetchYouTubeImport(
            input: input,
            existingKnownVideoIds: existingKnownVideoIds,
            allowFastIncrementalStop: allowFastIncrementalStop,
            onPartialSnapshot: { [weak self] partial in
                await MainActor.run {
                    guard let self else { return }
                    self.youtubeSyncProgressText = "YouTube: \(partial.tracks.count) треков..."
                    let resolvedTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? partial.title : customTitle
                    if let idx = self.findMatchingYouTubePlaylistIndex(for: partial.playlistId) {
                        let merged = PlaylistPreferencesEngine.mergeProgressivePlaylistPrefix(
                            existingTracks: self.libraryState.playlists[idx].tracksSnapshot,
                            prefixSnapshots: partial.tracks
                        )
                        let currentKeys = self.libraryState.playlists[idx].tracksSnapshot.map(\.cacheKey)
                        let mergedKeys = merged.tracks.map(\.cacheKey)
                        if merged.newlyAddedCount > 0 || mergedKeys != currentKeys {
                            self.libraryState.playlists[idx].kind = .youtube
                            self.libraryState.playlists[idx].youtubePlaylistId = partial.playlistId
                            self.libraryState.playlists[idx].sourceUrl = partial.canonicalURL
                            self.libraryState.playlists[idx].tracksSnapshot = merged.tracks
                            self.libraryState.playlists[idx].trackFilenames = mergedKeys
                            self.libraryState.playlists[idx].lastSyncedAt = Date()
                            self.invalidateLibraryCaches()
                            self.saveLibraryState()
                            self.artworkService.prewarmLibraryListThumbnails(
                                tracks: Array(partial.tracks.prefix(24)),
                                customAlbumCovers: self.libraryState.customAlbumCovers
                            )
                        }
                    } else if !partial.tracks.isEmpty {
                        let newPlaylist = Playlist(
                            id: "yt_\(partial.playlistId)",
                            name: resolvedTitle,
                            kind: .youtube,
                            trackFilenames: partial.tracks.map { $0.cacheKey },
                            tracksSnapshot: partial.tracks,
                            sourceUrl: partial.canonicalURL,
                            youtubePlaylistId: partial.playlistId,
                            remoteArtworkURL: partial.thumbnailURL,
                            lastSyncedAt: Date()
                        )
                        self.libraryState.playlists.append(newPlaylist)
                        self.libraryState.playlistShufflePreferences[newPlaylist.id] = PlaylistShufflePreference()
                        self.invalidateLibraryCaches()
                        self.saveLibraryState()
                    }
                }
            }
        )
        let title = customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result.title : customTitle

        if let existingIdx = findMatchingYouTubePlaylistIndex(for: result.playlistId) {
            // Полный `reconcilePlaylist` выполняем ТОЛЬКО если догружены все страницы до конца (`isCompleteSnapshot == true`),
            // иначе используем `mergeProgressivePlaylistPrefix`, чтобы никогда не обрезать плейлист на 300 или 500 треках при сбое сети!
            let updatedTracks: [Track]
            if result.isCompleteSnapshot {
                updatedTracks = PlaylistPreferencesEngine.reconcilePlaylist(
                    existingTracks: libraryState.playlists[existingIdx].tracksSnapshot,
                    remoteSnapshots: result.tracks
                )
            } else {
                updatedTracks = PlaylistPreferencesEngine.mergeProgressivePlaylistPrefix(
                    existingTracks: libraryState.playlists[existingIdx].tracksSnapshot,
                    prefixSnapshots: result.tracks
                ).tracks
            }
            libraryState.playlists[existingIdx].kind = .youtube
            libraryState.playlists[existingIdx].youtubePlaylistId = result.playlistId
            libraryState.playlists[existingIdx].sourceUrl = result.canonicalURL
            libraryState.playlists[existingIdx].tracksSnapshot = updatedTracks
            libraryState.playlists[existingIdx].trackFilenames = updatedTracks.map { $0.cacheKey }
            libraryState.playlists[existingIdx].lastSyncedAt = Date()
        } else {
            let newPlaylist = Playlist(
                id: "yt_\(result.playlistId)",
                name: title,
                kind: .youtube,
                trackFilenames: result.tracks.map { $0.cacheKey },
                tracksSnapshot: result.tracks,
                sourceUrl: result.canonicalURL,
                youtubePlaylistId: result.playlistId,
                remoteArtworkURL: result.thumbnailURL,
                lastSyncedAt: Date()
            )
            libraryState.playlists.append(newPlaylist)
            libraryState.playlistShufflePreferences[newPlaylist.id] = PlaylistShufflePreference()
        }
        invalidateLibraryCaches()
        saveLibraryState()
        artworkService.prewarmLibraryListThumbnails(
            tracks: Array(result.tracks.prefix(60)),
            customAlbumCovers: libraryState.customAlbumCovers
        )
    }

    // MARK: - Persistence & Restoration

    public func handleTelegramAuthorized() async {
        guard !isHandlingTelegramAuthorized else { return }
        isHandlingTelegramAuthorized = true
        defer { isHandlingTelegramAuthorized = false }

        statusBannerMessage = nil
        isTelegramAuthPresented = false

        // Всегда гарантируем автовыбор персональных чатов владельца (AndroSend Облако + AndroSend Архив)
        var didPopulateDefaultChats = false
        if libraryState.selectedTelegramChatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            libraryState.selectedTelegramChatId = AppConfig.defaultPersonalMainChatId
            libraryState.selectedTelegramChatTitle = AppConfig.defaultPersonalMainChatTitle
            didPopulateDefaultChats = true
        }
        if libraryState.selectedTelegramArchiveChatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (libraryState.selectedTelegramArchiveChatTitle.isEmpty
                || libraryState.selectedTelegramArchiveChatTitle == AppConfig.defaultArchiveChatPlaceholderTitle) {
            libraryState.selectedTelegramArchiveChatId = AppConfig.defaultPersonalArchiveChatId
            libraryState.selectedTelegramArchiveChatTitle = AppConfig.defaultPersonalArchiveChatTitle
            didPopulateDefaultChats = true
        }
        if didPopulateDefaultChats {
            saveLibraryState()
        }

        invalidateLibraryCaches()
        if currentTrack == nil {
            restorePreviousSession()
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        await telegramClient.refreshAuthorizedUserProfile()

        // Всегда синхронизируем Telegram при запуске/авторизации, чтобы мгновенно видеть все новые песни!
        await refreshTelegramChats(autoSyncIfNeeded: true)

        // Если сразу после входа TDLib ещё подгружал диалоги с сервера и треков пока 0 — автоматически повторяем синхронизацию до 2 раз
        for _ in 0..<2 {
            if !telegramClient.isAuthorized { break }
            if libraryState.tracks.contains(where: { $0.sourceKind == .telegram }) {
                statusBannerMessage = nil
                break
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await syncTelegramLibrary()
        }

        await verifyTelegramAccessLive(autoTriggerSyncIfEmpty: true)

        invalidateLibraryCaches()
    }

    /// Интерактивная проверка реального доступа к Telegram на сервере и подсчёт песен в основном чате («галочка»)
    public func verifyTelegramAccessLive(autoTriggerSyncIfEmpty: Bool = true) async {
        guard !isVerifyingTelegramAccess else { return }
        isVerifyingTelegramAccess = true
        defer { isVerifyingTelegramAccess = false }

        let cachedCount = libraryState.tracks.filter { cacheIndex.isCached($0) }.count
        var report = await telegramClient.verifyLiveAccessAndChatTrackCounts(
            mainChatId: libraryState.selectedTelegramChatId,
            mainChatTitle: libraryState.selectedTelegramChatTitle,
            archiveChatId: libraryState.selectedTelegramArchiveChatId,
            syncedTracks: libraryState.tracks,
            cachedCount: cachedCount
        )
        lastTelegramAccessReport = report

        if report.hasMainChatAccess && !report.resolvedMainChatId.isEmpty {
            var didMutate = false
            if libraryState.selectedTelegramChatId != report.resolvedMainChatId {
                libraryState.selectedTelegramChatId = report.resolvedMainChatId
                didMutate = true
            }
            if !report.resolvedMainChatTitle.isEmpty && libraryState.selectedTelegramChatTitle != report.resolvedMainChatTitle {
                libraryState.selectedTelegramChatTitle = report.resolvedMainChatTitle
                didMutate = true
            }
            if didMutate {
                saveLibraryState()
            }
            if availableTelegramChats.isEmpty {
                if let chats = try? await telegramClient.fetchAvailableAudioChats(
                    configuredArchiveChatId: libraryState.selectedTelegramArchiveChatId
                ) {
                    availableTelegramChats = chats
                }
            }
        }

        // Если на сервере в основном чате есть песни, а локально синхронизировано 0 — сразу запускаем синхронизацию!
        if autoTriggerSyncIfEmpty
            && report.hasMainChatAccess
            && (report.serverMainAudioCount > 0 || report.serverMainDocumentCount > 0)
            && report.syncedMainTracksCount == 0
            && !isSyncingTelegramLibrary {
            await syncTelegramLibrary()
            let updatedCachedCount = libraryState.tracks.filter { cacheIndex.isCached($0) }.count
            report = await telegramClient.verifyLiveAccessAndChatTrackCounts(
                mainChatId: libraryState.selectedTelegramChatId,
                mainChatTitle: libraryState.selectedTelegramChatTitle,
                archiveChatId: libraryState.selectedTelegramArchiveChatId,
                syncedTracks: libraryState.tracks,
                cachedCount: updatedCachedCount
            )
            lastTelegramAccessReport = report
        }
    }

    public func refreshTelegramChats(autoSyncIfNeeded: Bool = false) async {
        do {
            let chats = try await telegramClient.fetchAvailableAudioChats(
                configuredArchiveChatId: libraryState.selectedTelegramArchiveChatId
            )
            availableTelegramChats = chats

            var didMutateSelection = false

            // Автоматический выбор основного чата AndroSend по названию или типу форума
            let normCurrentMain = AppConfig.normalizeTelegramChatId(libraryState.selectedTelegramChatId)
            if normCurrentMain.isEmpty {
                if let matched = chats.first(where: {
                        let lower = $0.title.lowercased()
                        return lower.contains("androsend") && !lower.contains("архив") && !lower.contains("📦")
                    })
                    ?? chats.first(where: { $0.isForum }) {
                    libraryState.selectedTelegramChatId = matched.id
                    libraryState.selectedTelegramChatTitle = matched.title
                    didMutateSelection = true
                }
            } else if let existingMain = chats.first(where: { AppConfig.normalizeTelegramChatId($0.id) == normCurrentMain }) {
                if libraryState.selectedTelegramChatTitle != existingMain.title {
                    libraryState.selectedTelegramChatTitle = existingMain.title
                    didMutateSelection = true
                }
            } else if !chats.isEmpty,
                      let canonicalMain = chats.first(where: {
                          let lower = $0.title.lowercased()
                          return lower.contains("androsend") && !lower.contains("архив") && !lower.contains("📦")
                      }) {
                libraryState.selectedTelegramChatId = canonicalMain.id
                libraryState.selectedTelegramChatTitle = canonicalMain.title
                didMutateSelection = true
            }

            // Автоматический выбор архивного чата AndroSend по названию
            let normCurrentArchive = AppConfig.normalizeTelegramChatId(libraryState.selectedTelegramArchiveChatId)
            if normCurrentArchive.isEmpty {
                if let matchedArchive = chats.first(where: {
                        let lower = $0.title.lowercased()
                        return lower.contains("androsend") && (lower.contains("архив") || lower.contains("📦"))
                    }) {
                    libraryState.selectedTelegramArchiveChatId = matchedArchive.id
                    libraryState.selectedTelegramArchiveChatTitle = matchedArchive.title
                    didMutateSelection = true
                }
            } else if let existingArchive = chats.first(where: { AppConfig.normalizeTelegramChatId($0.id) == normCurrentArchive }) {
                if libraryState.selectedTelegramArchiveChatTitle != existingArchive.title {
                    libraryState.selectedTelegramArchiveChatTitle = existingArchive.title
                    didMutateSelection = true
                }
            } else if !chats.isEmpty,
                      let canonicalArchive = chats.first(where: {
                          let lower = $0.title.lowercased()
                          return lower.contains("androsend") && (lower.contains("архив") || lower.contains("📦"))
                      }) {
                libraryState.selectedTelegramArchiveChatId = canonicalArchive.id
                libraryState.selectedTelegramArchiveChatTitle = canonicalArchive.title
                didMutateSelection = true
            }

            if didMutateSelection {
                saveLibraryState()
            }

            let hasTelegramTracks = libraryState.tracks.contains(where: { $0.sourceKind == .telegram })
            if (autoSyncIfNeeded || !hasTelegramTracks),
               !libraryState.selectedTelegramChatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await syncTelegramLibrary()
            }
        } catch {
            statusBannerMessage = error.localizedDescription
        }
    }

    public func selectTelegramMainChat(_ chat: TelegramChatSummary) {
        libraryState.selectedTelegramChatId = chat.id
        libraryState.selectedTelegramChatTitle = chat.title
        saveLibraryState()
        if telegramClient.isAuthorized {
            Task { await syncTelegramLibrary() }
        }
    }

    public func selectTelegramArchiveChat(_ chat: TelegramChatSummary?) {
        if let chat {
            libraryState.selectedTelegramArchiveChatId = chat.id
            libraryState.selectedTelegramArchiveChatTitle = chat.title
        } else {
            libraryState.selectedTelegramArchiveChatId = ""
            libraryState.selectedTelegramArchiveChatTitle = AppConfig.defaultArchiveChatPlaceholderTitle
        }
        saveLibraryState()
        if telegramClient.isAuthorized, !libraryState.selectedTelegramChatId.isEmpty {
            Task { await syncTelegramLibrary() }
        }
    }

    public func mergeIncomingTelegramTracksIntoLibrary(_ incoming: [Track]) {
        guard !incoming.isEmpty else { return }
        let existingTelegram = libraryState.tracks.filter { $0.sourceKind == .telegram }
        let localAndYouTube = libraryState.tracks.filter { $0.sourceKind != .telegram }

        var byId: [String: Track] = [:]
        var byCacheKey: [String: String] = [:]
        for track in existingTelegram {
            byId[track.id] = track
            byCacheKey[track.cacheKey] = track.id
        }

        var didChange = false
        for track in incoming {
            let matchingId = byId[track.id] != nil ? track.id : byCacheKey[track.cacheKey]
            if let existingId = matchingId, let old = byId[existingId] {
                if old != track {
                    byId[existingId] = track
                    didChange = true
                }
            } else {
                byId[track.id] = track
                byCacheKey[track.cacheKey] = track.id
                didChange = true
            }
        }

        var mergedTelegram = Array(byId.values)
        mergedTelegram.sort { a, b in
            let dateA = a.addedAt?.timeIntervalSince1970 ?? 0
            let dateB = b.addedAt?.timeIntervalSince1970 ?? 0
            if abs(dateA - dateB) > 0.5 {
                return dateA > dateB
            }
            let msgA = Int64(a.messageId ?? "") ?? 0
            let msgB = Int64(b.messageId ?? "") ?? 0
            if msgA != msgB {
                return msgA > msgB
            }
            return a.id > b.id
        }

        if didChange || mergedTelegram.map(\.id) != existingTelegram.map(\.id) {
            libraryState.tracks = mergedTelegram + localAndYouTube
            invalidateLibraryCaches()
            saveLibraryState()
        }
    }

    public func syncTelegramLibrary() async {
        guard !isSyncingTelegramLibrary else { return }
        isSyncingTelegramLibrary = true
        defer { isSyncingTelegramLibrary = false }

        do {
            let scannedTracks = try await telegramClient.syncMainAndArchiveChats(
                mainChatId: libraryState.selectedTelegramChatId,
                mainChatTitle: libraryState.selectedTelegramChatTitle,
                archiveChatId: libraryState.selectedTelegramArchiveChatId,
                archiveChatTitle: libraryState.selectedTelegramArchiveChatTitle,
                onFirstPageTracks: { [weak self] firstPageTracks in
                    await MainActor.run {
                        self?.mergeIncomingTelegramTracksIntoLibrary(firstPageTracks)
                    }
                }
            )
            let existingTelegram = libraryState.tracks.filter { $0.sourceKind == .telegram }
            if scannedTracks.isEmpty && !existingTelegram.isEmpty {
                return
            }
            if scannedTracks.count >= existingTelegram.count {
                let localAndYouTube = libraryState.tracks.filter { $0.sourceKind != .telegram }
                libraryState.tracks = scannedTracks + localAndYouTube
                invalidateLibraryCaches()
                saveLibraryState()
            } else {
                mergeIncomingTelegramTracksIntoLibrary(scannedTracks)
            }
            statusBannerMessage = nil
            artworkService.prefetchArtistCovers(artists: computedArtists)
            artworkService.prewarmLibraryListThumbnails(
                tracks: availableLibraryTracks,
                customAlbumCovers: libraryState.customAlbumCovers
            )

            if var currentReport = lastTelegramAccessReport {
                let normMain = AppConfig.normalizeTelegramChatId(libraryState.selectedTelegramChatId)
                let syncedTg = libraryState.tracks.filter { $0.sourceKind == .telegram }
                let syncedMain = syncedTg.filter {
                    !$0.isFromArchive && (normMain.isEmpty || AppConfig.normalizeTelegramChatId($0.chatId ?? "") == normMain)
                }
                currentReport.syncedMainTracksCount = syncedMain.count
                currentReport.totalSyncedTelegramTracksCount = syncedTg.count
                currentReport.cachedTracksCount = libraryState.tracks.filter { cacheIndex.isCached($0) }.count
                lastTelegramAccessReport = currentReport
            }
        } catch {
            statusBannerMessage = error.localizedDescription
        }
    }

    public func saveLibraryState() {
        sessionStore.saveLibraryState(libraryState)
    }

    public func persistPlaybackSession() {
        let snapshot = PlaybackSessionSnapshot(
            currentTrack: currentTrack,
            queue: queue,
            currentIndex: currentIndex,
            currentTime: currentTime,
            isShuffleEnabled: isShuffleEnabled,
            repeatMode: repeatMode,
            volume: uiVolume,
            playbackSpeed: playbackSpeed,
            audioFXMode: audioFXMode,
            bassBoostEnabled: bassBoostEnabled,
            crossfadeEnabled: crossfadeEnabled,
            crossfadeDuration: crossfadeDuration,
            lyricsEngine: lyricsEngine,
            lyricsFontSize: lyricsFontSize,
            showLyricsTranslation: showLyricsTranslation
        )
        sessionStore.savePlaybackSession(snapshot)
    }

    private func restorePreviousSession() {
        guard let saved = sessionStore.loadPlaybackSession() else { return }
        let isTgReady = telegramClient.isAuthorized
        let playableQueue = isTgReady
            ? saved.queue
            : saved.queue.filter { $0.sourceKind != .telegram || cacheIndex.isCached($0) }

        self.queue = playableQueue
        self.originalQueueSource = playableQueue
        self.isShuffleEnabled = saved.isShuffleEnabled
        self.repeatMode = saved.repeatMode
        self.uiVolume = saved.volume
        self.playbackSpeed = saved.playbackSpeed
        self.audioFXMode = saved.audioFXMode
        self.bassBoostEnabled = saved.bassBoostEnabled
        self.crossfadeEnabled = saved.crossfadeEnabled
        self.crossfadeDuration = saved.crossfadeDuration
        self.lyricsEngine = saved.lyricsEngine
        self.lyricsFontSize = saved.lyricsFontSize
        self.showLyricsTranslation = saved.showLyricsTranslation

        let candidateTrack: Track? = {
            guard let t = saved.currentTrack else { return nil }
            if isTgReady || t.sourceKind != .telegram || cacheIndex.isCached(t) {
                return t
            }
            return playableQueue.first
        }()

        if let track = candidateTrack {
            self.currentTrack = track
            self.currentIndex = playableQueue.firstIndex(where: { $0.id == track.id }) ?? 0
            self.currentTime = (track.id == saved.currentTrack?.id) ? saved.currentTime : 0
            updatePalette(for: track)
            loadLyricsForCurrentTrack()
            if cacheIndex.isCached(track) {
                let url = storage.cachedAudioFileURL(for: track)
                let startSec = self.currentTime
                Task {
                    await audioEngine.loadAndPlay(track: track, fileURL: url, startAt: startSec, autoPlay: false)
                }
            }
        } else {
            self.currentTrack = nil
            self.currentIndex = 0
            self.currentTime = 0
        }
    }

    private func syncNowPlayingInfo() {
        var coverData: Data? = nil
        if let track = currentTrack,
           let resolvedHit = artworkService.resolveLocalCoverURLSync(
               for: track,
               customAlbumCovers: libraryState.customAlbumCovers,
               siblingTracks: libraryState.tracks
           ) {
            let hitPath = resolvedHit.url.path
            if let cachedData = nowPlayingArtworkDataCache[hitPath] {
                coverData = cachedData
            } else {
                let hitURL = resolvedHit.url
                let targetTrackId = track.id
                Task.detached(priority: .utility) { [weak self] in
                    guard let loaded = try? Data(contentsOf: hitURL) else { return }
                    await MainActor.run {
                        guard let self else { return }
                        if self.nowPlayingArtworkDataCache.count > 24 {
                            self.nowPlayingArtworkDataCache.removeAll(keepingCapacity: true)
                        }
                        self.nowPlayingArtworkDataCache[hitPath] = loaded
                        if self.currentTrack?.id == targetTrackId {
                            self.nowPlaying.updateNowPlaying(
                                track: self.currentTrack,
                                isPlaying: self.isPlaying,
                                currentTime: self.currentTime,
                                duration: self.duration,
                                playbackRate: self.audioEngine.effectivePlaybackRate,
                                artworkData: loaded
                            )
                        }
                    }
                }
            }
        }
        nowPlaying.updateNowPlaying(
            track: currentTrack,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            playbackRate: audioEngine.effectivePlaybackRate,
            artworkData: coverData
        )
    }
}
