import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
    public var favoriteAlbumNames: Set<String> = []
    public var favoritePlaylistIds: Set<String> = []
    public var hiddenAlbums: Set<String> = []
    public var excludedShuffleAlbums: Set<String> = []
    public var customAlbumCovers: [String: String] = [:]
    public var albumTrackOrders: [String: [String]] = [:]
    public var playCounts: [String: Int] = [:]
    public var disabledLyricsTrackIds: Set<String> = []
    public var playlistShufflePreferences: [String: PlaylistShufflePreference] = [:]
    public var selectedTelegramChatId: String = AppConfig.defaultPersonalMainChatId
    public var selectedTelegramChatTitle: String = AppConfig.defaultPersonalMainChatTitle
    public var selectedTelegramArchiveChatId: String = AppConfig.defaultPersonalArchiveChatId
    public var selectedTelegramArchiveChatTitle: String = AppConfig.defaultPersonalArchiveChatTitle
    public var isGyroscope3DCoverEnabled: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case tracks
        case playlists
        case favoriteTrackFilenames
        case favoriteArtistKeys
        case favoriteAlbumNames
        case favoritePlaylistIds
        case hiddenAlbums
        case excludedShuffleAlbums
        case customAlbumCovers
        case albumTrackOrders
        case playCounts
        case disabledLyricsTrackIds
        case playlistShufflePreferences
        case selectedTelegramChatId
        case selectedTelegramChatTitle
        case selectedTelegramArchiveChatId
        case selectedTelegramArchiveChatTitle
        case isGyroscope3DCoverEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        self.playlists = try c.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        self.favoriteTrackFilenames = try c.decodeIfPresent(Set<String>.self, forKey: .favoriteTrackFilenames) ?? []
        self.favoriteArtistKeys = try c.decodeIfPresent(Set<String>.self, forKey: .favoriteArtistKeys) ?? []
        self.favoriteAlbumNames = try c.decodeIfPresent(Set<String>.self, forKey: .favoriteAlbumNames) ?? []
        self.favoritePlaylistIds = try c.decodeIfPresent(Set<String>.self, forKey: .favoritePlaylistIds) ?? []
        self.hiddenAlbums = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenAlbums) ?? []
        self.excludedShuffleAlbums = try c.decodeIfPresent(Set<String>.self, forKey: .excludedShuffleAlbums) ?? []
        self.customAlbumCovers = try c.decodeIfPresent([String: String].self, forKey: .customAlbumCovers) ?? [:]
        self.albumTrackOrders = try c.decodeIfPresent([String: [String]].self, forKey: .albumTrackOrders) ?? [:]
        self.playCounts = try c.decodeIfPresent([String: Int].self, forKey: .playCounts) ?? [:]
        self.disabledLyricsTrackIds = try c.decodeIfPresent(Set<String>.self, forKey: .disabledLyricsTrackIds) ?? []
        self.playlistShufflePreferences = try c.decodeIfPresent([String: PlaylistShufflePreference].self, forKey: .playlistShufflePreferences) ?? [:]
        self.selectedTelegramChatId = try c.decodeIfPresent(String.self, forKey: .selectedTelegramChatId) ?? AppConfig.defaultPersonalMainChatId
        self.selectedTelegramChatTitle = try c.decodeIfPresent(String.self, forKey: .selectedTelegramChatTitle) ?? AppConfig.defaultPersonalMainChatTitle
        self.selectedTelegramArchiveChatId = try c.decodeIfPresent(String.self, forKey: .selectedTelegramArchiveChatId) ?? AppConfig.defaultPersonalArchiveChatId
        self.selectedTelegramArchiveChatTitle = try c.decodeIfPresent(String.self, forKey: .selectedTelegramArchiveChatTitle) ?? AppConfig.defaultPersonalArchiveChatTitle
        self.isGyroscope3DCoverEnabled = try c.decodeIfPresent(Bool.self, forKey: .isGyroscope3DCoverEnabled) ?? true
    }
}

/// Персистентное хранилище состояния библиотеки и сессии воспроизведения.
/// Запись и сериализация больших JSON-структур (3000+ треков) вынесены в фоновую очередь с коалесценцией,
/// а актуальные снимки хранятся в памяти для мгновенного чтения без фризов MainActor и лишнего нагрева CPU.
public final class PlaybackSessionStore: @unchecked Sendable {
    public static let shared = PlaybackSessionStore()

    private let storage: StorageManager
    private let sessionFileURL: URL
    private let libraryStateFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.bebranoid.persistence.io", qos: .utility)

    private var latestSessionInMemory: PlaybackSessionSnapshot?
    private var latestLibraryStateInMemory: UserLibraryPersistentState?
    private var sessionWriteScheduled: Bool = false
    private var libraryWriteScheduled: Bool = false

    public init(storage: StorageManager = .shared) {
        self.storage = storage
        self.sessionFileURL = storage.databaseDirectory.appendingPathComponent("playback_session_v1.json")
        self.libraryStateFileURL = storage.databaseDirectory.appendingPathComponent("user_library_state_v1.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        #if canImport(UIKit) && os(iOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flushPendingWritesSync()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flushPendingWritesSync()
        }
        #endif
    }

    public func savePlaybackSession(_ snapshot: PlaybackSessionSnapshot) {
        let shouldSchedule: Bool = {
            lock.lock()
            defer { lock.unlock() }
            latestSessionInMemory = snapshot
            if sessionWriteScheduled {
                return false
            }
            sessionWriteScheduled = true
            return true
        }()

        guard shouldSchedule else { return }
        ioQueue.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.performPendingSessionWrite()
        }
    }

    private func performPendingSessionWrite() {
        let snapshot: PlaybackSessionSnapshot? = {
            lock.lock()
            defer { lock.unlock() }
            sessionWriteScheduled = false
            return latestSessionInMemory
        }()
        guard let snapshot, let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: sessionFileURL, options: .atomic)

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
        if let inMem = latestSessionInMemory {
            lock.unlock()
            return inMem
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: sessionFileURL),
              let decoded = try? decoder.decode(PlaybackSessionSnapshot.self, from: data) else {
            return nil
        }
        lock.lock()
        if latestSessionInMemory == nil {
            latestSessionInMemory = decoded
        }
        lock.unlock()
        return decoded
    }

    public func saveLibraryState(_ state: UserLibraryPersistentState) {
        let shouldSchedule: Bool = {
            lock.lock()
            defer { lock.unlock() }
            latestLibraryStateInMemory = state
            if libraryWriteScheduled {
                return false
            }
            libraryWriteScheduled = true
            return true
        }()

        guard shouldSchedule else { return }
        ioQueue.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.performPendingLibraryWrite()
        }
    }

    private func performPendingLibraryWrite() {
        let state: UserLibraryPersistentState? = {
            lock.lock()
            defer { lock.unlock() }
            libraryWriteScheduled = false
            return latestLibraryStateInMemory
        }()
        guard let state, let data = try? encoder.encode(state) else { return }
        try? data.write(to: libraryStateFileURL, options: .atomic)
    }

    public func flushPendingWritesSync() {
        ioQueue.sync {
            if sessionWriteScheduled {
                performPendingSessionWrite()
            }
            if libraryWriteScheduled {
                performPendingLibraryWrite()
            }
        }
    }

    public func loadLibraryState() -> UserLibraryPersistentState {
        lock.lock()
        if let inMem = latestLibraryStateInMemory {
            lock.unlock()
            return inMem
        }
        guard let data = try? Data(contentsOf: libraryStateFileURL),
              var decoded = try? decoder.decode(UserLibraryPersistentState.self, from: data) else {
            lock.unlock()
            return UserLibraryPersistentState()
        }

        var didMigratePersonalChats = false
        if decoded.selectedTelegramChatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            decoded.selectedTelegramChatId = AppConfig.defaultPersonalMainChatId
            decoded.selectedTelegramChatTitle = AppConfig.defaultPersonalMainChatTitle
            didMigratePersonalChats = true
        } else if decoded.selectedTelegramChatTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || decoded.selectedTelegramChatTitle == AppConfig.defaultMainChatPlaceholderTitle {
            decoded.selectedTelegramChatTitle = AppConfig.defaultPersonalMainChatTitle
            didMigratePersonalChats = true
        }

        if decoded.selectedTelegramArchiveChatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (decoded.selectedTelegramArchiveChatTitle.isEmpty
                || decoded.selectedTelegramArchiveChatTitle == AppConfig.defaultArchiveChatPlaceholderTitle) {
            decoded.selectedTelegramArchiveChatId = AppConfig.defaultPersonalArchiveChatId
            decoded.selectedTelegramArchiveChatTitle = AppConfig.defaultPersonalArchiveChatTitle
            didMigratePersonalChats = true
        }

        latestLibraryStateInMemory = decoded
        lock.unlock()

        if didMigratePersonalChats {
            saveLibraryState(decoded)
        }
        return decoded
    }
}
