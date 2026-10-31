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
    public var nextTrackAccent: MeshRGB? = nil
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
        restorePreviousSession()
        guard !TelegramClientService.isRunningUnderXCTest else { return }
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

    private func bindArtworkAndTelegramNotifications() {
        NotificationCenter.default.publisher(for: .artworkDidResolve)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self, let current = self.currentTrack else { return }
                let resolvedTrackId = note.userInfo?["trackId"] as? String
                let resolvedAlbum = note.userInfo?["album"] as? String
                if resolvedTrackId == current.id || (resolvedAlbum != nil && resolvedAlbum == current.album) {
                    self.updatePalette(for: current)
                    self.syncNowPlayingInfo()
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
    }

    public var accentSwiftUIColor: Color {
        let norm = accentRGB.normalizedDouble
        return Color(red: norm.r, green: norm.g, blue: norm.b)
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
                let minDelta: Double
                if self.isLyricsScreenPresented {
                    minDelta = 0.025 // ~40 Hz для плавного пословного караоке Beautiful Lyrics
                } else if self.isFullScreenPlayerPresented {
                    minDelta = 0.08 // 12 Hz для плавного слайдера в полноэкранном плеере
                } else {
                    minDelta = 1.0 // 1 Hz для мини-плеера (ноль перерисовок списков при 120 Hz скролле)
                }
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
            guard let self else { return }
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
        nowPlaying.onPlayCommand = { [weak self] in self?.audioEngine.play() }
        nowPlaying.onPauseCommand = { [weak self] in self?.audioEngine.pause() }
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

    public func playTrack(_ track: Track, in contextQueue: [Track]? = nil) {
        haptics.lightTap()
        let baseQueue = (contextQueue?.isEmpty == false) ? contextQueue! : (queue.isEmpty ? availableLibraryTracks : queue)
        originalQueueSource = baseQueue

        if let foundIndex = baseQueue.firstIndex(where: { $0.id == track.id }) {
            queue = baseQueue
            currentIndex = foundIndex
        } else {
            queue = [track] + baseQueue
            currentIndex = 0
        }

        if isShuffleEnabled {
            queue = QueueOrder.reshuffleUpcoming(
                queue: queue,
                currentIndex: currentIndex,
                sourceTracks: originalQueueSource
            )
        }

        startPlayingCurrentIndex(autoPlay: true)
    }

    public func togglePlayPause() {
        haptics.lightTap()
        if currentTrack == nil, let first = queue.first ?? availableLibraryTracks.first {
            playTrack(first)
            return
        }
        audioEngine.togglePlayPause()
        syncNowPlayingInfo()
    }

    public func seek(to timeSeconds: Double) {
        audioEngine.seek(to: timeSeconds)
        syncNowPlayingInfo()
        persistPlaybackSession()
    }

    public func skipToNext(isManualUserAction: Bool = true) {
        if isManualUserAction {
            haptics.lightTap()
            audioEngine.cancelActiveCrossfade()
        }
        guard !queue.isEmpty else { return }

        if currentIndex + 1 < queue.count {
            currentIndex += 1
            startPlayingCurrentIndex(autoPlay: true)
        } else if repeatMode == .all {
            currentIndex = 0
            startPlayingCurrentIndex(autoPlay: true)
        } else {
            audioEngine.pause()
            seek(to: 0)
        }
    }

    public func skipToPrevious() {
        haptics.lightTap()
        audioEngine.cancelActiveCrossfade()
        if currentTime > 3.5 {
            seek(to: 0)
            return
        }
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
        persistPlaybackSession()
    }

    public func cycleRepeatMode() {
        haptics.softSelection()
        switch repeatMode {
        case .none: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .none
        }
        persistPlaybackSession()
    }

    /// Шаффл всей медиатеки с учётом исключённых альбомов (`excludedShuffleAlbums`), скрытых альбомов и лимитов YouTube-плейлистов (`playlistPreferences`)
    public func shuffleAllEligibleLibrary() {
        haptics.mediumImpact()
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

    private func startPlayingCurrentIndex(autoPlay: Bool, initialSeek: Double = 0) {
        guard currentIndex >= 0, currentIndex < queue.count else { return }
        let track = queue[currentIndex]
        currentTrack = track
        duration = track.duration
        updatePalette(for: track)
        loadLyricsForCurrentTrack()
        persistPlaybackSession()

        Task {
            do {
                let fileURL: URL
                if cacheIndex.isCached(track) {
                    fileURL = storage.cachedAudioFileURL(for: track)
                } else {
                    fileURL = try await telegramClient.ensureTrackDownloaded(track: track, priority: .activePlayback)
                }
                guard currentTrack?.id == track.id else { return }
                await audioEngine.loadAndPlay(track: track, fileURL: fileURL, startAt: initialSeek, autoPlay: autoPlay)
                updatePalette(for: track)
                syncNowPlayingInfo()
                prefetchUpcomingTrack()
            } catch {
                if currentTrack?.id == track.id {
                    statusBannerMessage = error.localizedDescription
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
        guard let nextIdx = peekNextTrackIndex(), nextIdx < queue.count else { return }
        let nextTrack = queue[nextIdx]
        prepareNextTrackPalette(for: nextTrack)
        guard !cacheIndex.isCached(nextTrack) else { return }

        Task.detached { [telegramClient] in
            _ = try? await telegramClient.ensureTrackDownloaded(track: nextTrack, priority: .nextTrackPrefetch)
        }
    }

    // MARK: - Harmonoid Mesh Palette Resolution

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
            let localURL = resolvedHit.url
            if let cgImage = artworkService.loadCGImage(from: localURL, tier: .meshAnalysis) {
                let analyzed = HarmonoidMeshEngine.analyzeCoverImage(cgImage)
                currentPalette = analyzed.meshColors
                accentRGB = analyzed.uiAccent
                return
            }
            #if canImport(UIKit)
            if let uiImage = UIImage(contentsOfFile: localURL.path),
               let cgImage = uiImage.cgImage {
                let analyzed = HarmonoidMeshEngine.analyzeCoverImage(cgImage)
                currentPalette = analyzed.meshColors
                accentRGB = analyzed.uiAccent
                return
            }
            #endif
        }

        // Детерминированная генерация богатой палитры из хеша обложки/альбома, пока реальная обложка извлекается
        let seedPalette = Self.deterministicSeedPalette(for: "\(track.album)|\(track.artist)")
        currentPalette = HarmonoidMeshEngine.mapPaletteToMeshColors(seedPalette)
        accentRGB = HarmonoidMeshEngine.pickAccentFromPalette(seedPalette)

        // Запускаем асинхронное разрешение реальной обложки (embedded / Telegram / YouTube)
        let customCovers = libraryState.customAlbumCovers
        let siblings = libraryState.tracks
        Task { [artworkService] in
            _ = await artworkService.resolveArtwork(
                for: track,
                customAlbumCovers: customCovers,
                siblingTracks: siblings
            )
        }
    }

    private func prepareNextTrackPalette(for nextTrack: Track) {
        if let resolvedHit = artworkService.resolveLocalCoverURLSync(
            for: nextTrack,
            customAlbumCovers: libraryState.customAlbumCovers,
            siblingTracks: libraryState.tracks
        ) {
            let localURL = resolvedHit.url
            if let cgImage = artworkService.loadCGImage(from: localURL, tier: .meshAnalysis) {
                let analyzed = HarmonoidMeshEngine.analyzeCoverImage(cgImage)
                nextTrackPalette = analyzed.meshColors
                nextTrackAccent = analyzed.uiAccent
                return
            }
            #if canImport(UIKit)
            if let uiImage = UIImage(contentsOfFile: localURL.path),
               let cgImage = uiImage.cgImage {
                let analyzed = HarmonoidMeshEngine.analyzeCoverImage(cgImage)
                nextTrackPalette = analyzed.meshColors
                nextTrackAccent = analyzed.uiAccent
                return
            }
            #endif
        }
        let seed = Self.deterministicSeedPalette(for: "\(nextTrack.album)|\(nextTrack.artist)")
        nextTrackPalette = HarmonoidMeshEngine.mapPaletteToMeshColors(seed)
        nextTrackAccent = HarmonoidMeshEngine.pickAccentFromPalette(seed)
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
            if isLyricsScreenPresented {
                isLyricsScreenPresented = false
            }
            return
        }

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

        // 1. Виртуальный альбом «Любимые» всегда первый (`src/views/Albums.jsx`)
        let sourceTracks = availableLibraryTracks
        let favTracks = sourceTracks.filter { isFavorite($0) }
        if !favTracks.isEmpty {
            albums.append(
                Album(
                    name: AppConfig.favoritesAlbumName,
                    artist: "Избранные треки",
                    tracks: favTracks,
                    customCoverPath: libraryState.customAlbumCovers[AppConfig.favoritesAlbumName],
                    isFavoriteVirtualAlbum: true,
                    isHidden: false,
                    isExcludedFromShuffle: false
                )
            )
        }

        var grouped: [String: [Track]] = [:]
        for track in sourceTracks {
            let name = track.album.isEmpty ? "Без альбома" : track.album
            grouped[name, default: []].append(track)
        }

        for (albumName, rawTracks) in grouped {
            let isHidden = libraryState.hiddenAlbums.contains(albumName)
            if isHidden && !showHiddenAlbums {
                continue
            }

            // Применяем сохранённый ручной порядок треков внутри альбома (`albumOrder`)
            var orderedTracks = rawTracks
            if let savedOrder = libraryState.albumTrackOrders[albumName], !savedOrder.isEmpty {
                let orderMap = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($1, $0) })
                orderedTracks.sort { a, b in
                    let idxA = orderMap[a.cacheKey] ?? Int.max
                    let idxB = orderMap[b.cacheKey] ?? Int.max
                    return idxA < idxB
                }
            }

            let dominantArtist = orderedTracks.first?.artist ?? "Разные исполнители"
            albums.append(
                Album(
                    name: albumName,
                    artist: dominantArtist,
                    tracks: orderedTracks,
                    customCoverPath: libraryState.customAlbumCovers[albumName],
                    isFavoriteVirtualAlbum: false,
                    isHidden: isHidden,
                    isExcludedFromShuffle: libraryState.excludedShuffleAlbums.contains(albumName)
                )
            )
        }

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
        let result = [recentAuto] + libraryState.playlists
        _cachedPlaylists = result
        return result
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

    public func importYouTubeURL(_ input: String, customTitle: String = "") async throws {
        let result = try await youtubeService.fetchYouTubeImport(input: input)
        let title = customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result.title : customTitle

        if let existingIdx = libraryState.playlists.firstIndex(where: { $0.youtubePlaylistId == result.playlistId }) {
            let reconciled = PlaylistPreferencesEngine.reconcilePlaylist(
                existingTracks: libraryState.playlists[existingIdx].tracksSnapshot,
                remoteSnapshots: result.tracks
            )
            libraryState.playlists[existingIdx].tracksSnapshot = reconciled
            libraryState.playlists[existingIdx].trackFilenames = reconciled.map { $0.cacheKey }
            libraryState.playlists[existingIdx].lastSyncedAt = Date()
        } else {
            let newPlaylist = Playlist(
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
        saveLibraryState()
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

        let hasExistingTelegramTracks = libraryState.tracks.contains(where: { $0.sourceKind == .telegram })
        await refreshTelegramChats(autoSyncIfNeeded: !hasExistingTelegramTracks)

        // Если сразу после входа TDLib ещё подгружал диалоги с сервера и треков пока 0 — автоматически повторяем синхронизацию до 2 раз
        for _ in 0..<2 {
            if !telegramClient.isAuthorized { break }
            if libraryState.tracks.contains(where: { $0.sourceKind == .telegram }) {
                statusBannerMessage = nil
                break
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await syncTelegramLibrary()
        }

        invalidateLibraryCaches()
        if let pendingTrack = currentTrack,
           pendingTrack.sourceKind == .telegram,
           !isPlaying,
           trackDownloadProgress[pendingTrack.cacheKey] == nil {
            startPlayingCurrentIndex(autoPlay: false)
        }
    }

    public func refreshTelegramChats(autoSyncIfNeeded: Bool = false) async {
        do {
            let chats = try await telegramClient.fetchAvailableAudioChats(
                configuredArchiveChatId: libraryState.selectedTelegramArchiveChatId
            )
            availableTelegramChats = chats

            var didMutateSelection = false

            // Автоматический выбор основного чата AndroSend по названию или типу форума, если пользователь ещё не выбрал чат
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

    public func syncTelegramLibrary() async {
        guard !isSyncingTelegramLibrary else { return }
        isSyncingTelegramLibrary = true
        defer { isSyncingTelegramLibrary = false }

        do {
            let scannedTracks = try await telegramClient.syncMainAndArchiveChats(
                mainChatId: libraryState.selectedTelegramChatId,
                mainChatTitle: libraryState.selectedTelegramChatTitle,
                archiveChatId: libraryState.selectedTelegramArchiveChatId,
                archiveChatTitle: libraryState.selectedTelegramArchiveChatTitle
            )
            let existingTelegram = libraryState.tracks.filter { $0.sourceKind == .telegram }
            if scannedTracks.isEmpty && !existingTelegram.isEmpty {
                return
            }
            let localAndYouTube = libraryState.tracks.filter { $0.sourceKind != .telegram }
            libraryState.tracks = scannedTracks + localAndYouTube
            saveLibraryState()
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
            coverData = try? Data(contentsOf: resolvedHit.url)
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
