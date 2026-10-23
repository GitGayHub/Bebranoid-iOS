import Foundation

public enum PlaylistKind: String, Codable, Sendable {
    case recentAuto
    case userCustom
    case youtube
}

public struct Playlist: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: PlaylistKind
    public var trackFilenames: [String]
    public var tracksSnapshot: [Track]
    public var sourceUrl: String?
    public var youtubePlaylistId: String?
    public var customCoverPath: String?
    public var remoteArtworkURL: String?
    public var lastSyncedAt: Date?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: PlaylistKind = .userCustom,
        trackFilenames: [String] = [],
        tracksSnapshot: [Track] = [],
        sourceUrl: String? = nil,
        youtubePlaylistId: String? = nil,
        customCoverPath: String? = nil,
        remoteArtworkURL: String? = nil,
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.trackFilenames = trackFilenames
        self.tracksSnapshot = tracksSnapshot
        self.sourceUrl = sourceUrl
        self.youtubePlaylistId = youtubePlaylistId
        self.customCoverPath = customCoverPath
        self.remoteArtworkURL = remoteArtworkURL
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
    }

    public var isYouTubePlaylist: Bool {
        kind == .youtube || (sourceUrl != nil && !(sourceUrl ?? "").isEmpty)
    }

    public var isRecentAutoPlaylist: Bool {
        id == AppConfig.recent30PlaylistId || kind == .recentAuto
    }
}
