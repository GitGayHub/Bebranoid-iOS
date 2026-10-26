import Foundation

public struct Album: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var artist: String
    public var tracks: [Track]
    public var customCoverPath: String?
    public var isFavoriteVirtualAlbum: Bool
    public var isHidden: Bool
    public var isExcludedFromShuffle: Bool

    public init(
        name: String,
        artist: String,
        tracks: [Track],
        customCoverPath: String? = nil,
        isFavoriteVirtualAlbum: Bool = false,
        isHidden: Bool = false,
        isExcludedFromShuffle: Bool = false
    ) {
        self.name = name
        self.artist = artist
        self.tracks = tracks
        self.customCoverPath = customCoverPath
        self.isFavoriteVirtualAlbum = isFavoriteVirtualAlbum
        self.isHidden = isHidden
        self.isExcludedFromShuffle = isExcludedFromShuffle
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
        tracks.first(where: { $0.remoteArtworkURL != nil })?.remoteArtworkURL
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
