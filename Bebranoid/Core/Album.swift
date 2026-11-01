import Foundation

public struct Album: Identifiable, Hashable, Sendable {
    public var id: String { linkedPlaylistId.map { "playlist_\($0)" } ?? name }
    public var name: String
    public var artist: String
    public var tracks: [Track]
    public var customCoverPath: String?
    public var explicitRemoteArtworkURL: String?
    public var isFavoriteVirtualAlbum: Bool
    public var isLikedFavorite: Bool
    public var linkedPlaylistId: String?
    public var isHidden: Bool
    public var isExcludedFromShuffle: Bool

    public init(
        name: String,
        artist: String,
        tracks: [Track],
        customCoverPath: String? = nil,
        explicitRemoteArtworkURL: String? = nil,
        isFavoriteVirtualAlbum: Bool = false,
        isLikedFavorite: Bool = false,
        linkedPlaylistId: String? = nil,
        isHidden: Bool = false,
        isExcludedFromShuffle: Bool = false
    ) {
        self.name = name
        self.artist = artist
        self.tracks = tracks
        self.customCoverPath = customCoverPath
        self.explicitRemoteArtworkURL = explicitRemoteArtworkURL
        self.isFavoriteVirtualAlbum = isFavoriteVirtualAlbum
        self.isLikedFavorite = isLikedFavorite
        self.linkedPlaylistId = linkedPlaylistId
        self.isHidden = isHidden
        self.isExcludedFromShuffle = isExcludedFromShuffle
    }

    public var representativeTrack: Track? {
        tracks.first(where: {
            ($0.coverPath?.isEmpty == false) ||
            ($0.coverFileId?.isEmpty == false) ||
            ($0.remoteArtworkURL?.isEmpty == false) ||
            ($0.youtubeVideoId?.isEmpty == false)
        }) ?? tracks.first
    }

    public var coverPath: String? {
        if let customCoverPath, !customCoverPath.isEmpty {
            return customCoverPath
        }
        if let explicit = tracks.first(where: { $0.coverPath != nil })?.coverPath {
            return explicit
        }
        for track in tracks {
            if let resolved = ArtworkService.shared.resolveLocalCoverURLSync(for: track) {
                return resolved.url.path
            }
        }
        return nil
    }

    public var remoteArtworkURL: String? {
        if let explicitRemoteArtworkURL, !explicitRemoteArtworkURL.isEmpty {
            return explicitRemoteArtworkURL
        }
        return tracks.first(where: { $0.remoteArtworkURL != nil })?.remoteArtworkURL
    }

    public var totalDuration: Double {
        tracks.reduce(0) { $0 + $1.duration }
    }
}

public struct ArtistSummary: Identifiable, Hashable, Sendable {
    public var id: String { normalizedKey }
    public var normalizedKey: String
    public var displayName: String
    public var tracks: [Track]
    public var albums: [String]
    public var isPinnedFavorite: Bool

    public init(
        normalizedKey: String,
        displayName: String,
        tracks: [Track],
        albums: [String],
        isPinnedFavorite: Bool = false
    ) {
        self.normalizedKey = normalizedKey
        self.displayName = displayName
        self.tracks = tracks
        self.albums = albums
        self.isPinnedFavorite = isPinnedFavorite
    }

    /// Первый трек артиста с наибольшим шансом иметь реальную обложку (`Artists.jsx` `artist.tracks[0]` + smart fallback)
    public var representativeTrack: Track? {
        tracks.first(where: {
            ($0.coverPath?.isEmpty == false) ||
            ($0.coverFileId?.isEmpty == false) ||
            ($0.remoteArtworkURL?.isEmpty == false) ||
            ($0.youtubeVideoId?.isEmpty == false)
        }) ?? tracks.first
    }

    public var representativeCoverPath: String? {
        if let explicit = tracks.first(where: { $0.coverPath != nil })?.coverPath {
            return explicit
        }
        for track in tracks {
            if let resolved = ArtworkService.shared.resolveLocalCoverURLSync(for: track) {
                return resolved.url.path
            }
        }
        return nil
    }

    public var representativeRemoteArtwork: String? {
        tracks.first(where: { $0.remoteArtworkURL != nil })?.remoteArtworkURL
    }
}
