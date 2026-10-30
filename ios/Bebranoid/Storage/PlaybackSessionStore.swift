import Foundation

/// Снимок состояния сессии воспроизведения (`bebranoid_playback_session_v1` из `src/App.jsx`)
public struct PlaybackSessionSnapshot: Codable, Sendable {
    public var currentTrack: Track?
    public var queue: [Track]
    public var currentIndex: Int
    public var currentTime: Double
    public var isShuffleEnabled: Bool
    public var repeatMode: RepeatMode
    public var volume: Double
    public var playbackSpeed: Float
    public var audioFXMode: AudioFXMode
    public var bassBoostEnabled: Bool
    public var crossfadeEnabled: Bool
    public var crossfadeDuration: Double
    public var lyricsEngine: LyricsEngineKind
    public var lyricsFontSize: LyricsFontSizePreset
    public var showLyricsTranslation: Bool
    public var savedAt: Date

    public init(
        currentTrack: Track? = nil,
        queue: [Track] = [],
        currentIndex: Int = 0,
        currentTime: Double = 0,
        isShuffleEnabled: Bool = false,
        repeatMode: RepeatMode = .none,
        volume: Double = 0.85,
        playbackSpeed: Float = 1.0,
        audioFXMode: AudioFXMode = .normal,
        bassBoostEnabled: Bool = false,
        crossfadeEnabled: Bool = true,
        crossfadeDuration: Double = AppConfig.defaultCrossfadeDuration,
        lyricsEngine: LyricsEngineKind = .beautiful,
        lyricsFontSize: LyricsFontSizePreset = .medium,
        showLyricsTranslation: Bool = false,
        savedAt: Date = Date()
    ) {
        self.currentTrack = currentTrack
        self.queue = queue
        self.currentIndex = currentIndex
        self.currentTime = currentTime
        self.isShuffleEnabled = isShuffleEnabled
        self.repeatMode = repeatMode
        self.volume = volume
        self.playbackSpeed = playbackSpeed
        self.audioFXMode = audioFXMode
        self.bassBoostEnabled = bassBoostEnabled
        self.crossfadeEnabled = crossfadeEnabled
        self.crossfadeDuration = crossfadeDuration
        self.lyricsEngine = lyricsEngine
        self.lyricsFontSize = lyricsFontSize
        self.showLyricsTranslation = showLyricsTranslation
        self.savedAt = savedAt
    }
}

/// Полное состояние пользовательских коллекций, избранного, скрытых альбомов, счётчиков и настроек
public struct UserLibraryPersistentState: Codable, Sendable {
    public var tracks: [Track] = []
    public var playlists: [Playlist] = []
    public var favoriteTrackFilenames: Set<String> = []
    public var favoriteArtistKeys: Set<String> = []
    public var hiddenAlbums: Set<String> = []
    public var excludedShuffleAlbums: Set<String> = []
    public var customAlbumCovers: [String: String] = [:]
    public var albumTrackOrders: [String: [String]] = [:]
    public var playCounts: [String: Int] = [:]
    public var disabledLyricsTrackIds: Set<String> = []
    public var playlistShufflePreferences: [String: PlaylistShufflePreference] = [:]
    public var selectedTelegramChatId: String = ""
    public var selectedTelegramChatTitle: String = AppConfig.defaultMainChatPlaceholderTitle
    public var selectedTelegramArchiveChatId: String = ""
    public var selectedTelegramArchiveChatTitle: String = AppConfig.defaultArchiveChatPlaceholderTitle

    public init() {}
}

/// Персистентное хранилище состояния библиотеки и сессии воспроизведения
public final class PlaybackSessionStore: @unchecked Sendable {
    public static let shared = PlaybackSessionStore()

    private let storage: StorageManager
    private let sessionFileURL: URL
    private let libraryStateFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(storage: StorageManager = .shared) {
        self.storage = storage
        self.sessionFileURL = storage.databaseDirectory.appendingPathComponent("playback_session_v1.json")
        self.libraryStateFileURL = storage.databaseDirectory.appendingPathComponent("user_library_state_v1.json")

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public func savePlaybackSession(_ snapshot: PlaybackSessionSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: sessionFileURL, options: .atomic)

        // Синхронизируем краткую карточку в AppGroup UserDefaults для виджетов iOS
        if let sharedDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier),
           let track = snapshot.currentTrack {
            sharedDefaults.set(track.title, forKey: "widget_track_title")
            sharedDefaults.set(track.artist, forKey: "widget_track_artist")
            sharedDefaults.set(track.album, forKey: "widget_track_album")
            sharedDefaults.set(track.formatInfo?.computeQualityBadge().label ?? "Audio", forKey: "widget_quality_badge")
        }
    }

    public func loadPlaybackSession() -> PlaybackSessionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: sessionFileURL) else { return nil }
        return try? decoder.decode(PlaybackSessionSnapshot.self, from: data)
    }

    public func saveLibraryState(_ state: UserLibraryPersistentState) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: libraryStateFileURL, options: .atomic)
    }

    public func loadLibraryState() -> UserLibraryPersistentState {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: libraryStateFileURL),
              let decoded = try? decoder.decode(UserLibraryPersistentState.self, from: data) else {
            return UserLibraryPersistentState()
        }
        return decoded
    }
}
