import Foundation

/// Точный 1:1 порт `src/lib/playlistPreferences.js`
public struct PlaylistShufflePreference: Codable, Hashable, Sendable {
    public static let defaultLimit: Int = 15
    public static let maxLimit: Int = 5000

    public var limit: Int
    public var include: [String]
    public var exclude: [String]

    public init(
        limit: Int = PlaylistShufflePreference.defaultLimit,
        include: [String] = [],
        exclude: [String] = []
    ) {
        self.limit = Self.clampLimit(limit)
        let cleanInclude = Self.dedupStrings(include)
        let includeSet = Set(cleanInclude)
        let cleanExclude = Self.dedupStrings(exclude).filter { !includeSet.contains($0) }
        self.include = cleanInclude
        self.exclude = cleanExclude
    }

    public static func clampLimit(_ value: Int) -> Int {
        min(maxLimit, max(0, value))
    }

    private static func dedupStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !seen.contains(trimmed) {
                seen.insert(trimmed)
                result.append(trimmed)
            }
        }
        return result
    }

    /// Изменяет лимит на заданную дельту (например `-10` или `+10`)
    public mutating func adjustLimit(by delta: Int) {
        limit = Self.clampLimit(limit + delta)
    }

    /// Переключает ручное принудительное включение трека сверх лимита
    public mutating func toggleInclude(filename: String) {
        let key = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if let idx = include.firstIndex(of: key) {
            include.remove(at: idx)
        } else {
            include.append(key)
            exclude.removeAll { $0 == key }
        }
    }

    /// Переключает ручное принудительное исключение трека из шаффла
    public mutating func toggleExclude(filename: String) {
        let key = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if let idx = exclude.firstIndex(of: key) {
            exclude.remove(at: idx)
        } else {
            exclude.append(key)
            include.removeAll { $0 == key }
        }
    }
}

public enum PlaylistPreferencesEngine {
    /// Возвращает треки плейлиста, допущенные к общему шаффлу медиатеки (`eligiblePlaylistTracks` из `playlistPreferences.js`):
    /// `!exclude.has(track.filename) && (include.has(track.filename) || index < options.limit)`
    public static func eligiblePlaylistTracks(
        tracks: [Track],
        preference: PlaylistShufflePreference?
    ) -> [Track] {
        let norm = preference ?? PlaylistShufflePreference()
        let includeSet = Set(norm.include)
        let excludeSet = Set(norm.exclude)

        var eligible: [Track] = []
        for (index, track) in tracks.enumerated() {
            let key = track.cacheKey
            if excludeSet.contains(key) {
                continue
            }
            if includeSet.contains(key) || index < norm.limit {
                eligible.append(track)
            }
        }
        return eligible
    }

    /// Сверяет и обновляет существующий список треков плейлиста со свежим снапшотом из YouTube (`reconcilePlaylist` из `playlistPreferences.js`).
    /// Сохраняет локальные/ручные треки, заменяя и упорядочивая удалённые YouTube-треки согласно новому снапшоту.
    public static func reconcilePlaylist(
        existingTracks: [Track],
        remoteSnapshots: [Track]
    ) -> [Track] {
        guard !remoteSnapshots.isEmpty else { return existingTracks }

        var existingByKey: [String: Track] = [:]
        for track in existingTracks {
            existingByKey[track.cacheKey] = track
        }

        let remoteKeys = Set(remoteSnapshots.map { $0.cacheKey })

        // Ручные не-YouTube треки, которых нет в удалённом снапшоте, сохраняем в конце
        let preservedLocalTracks = existingTracks.filter { track in
            track.sourceKind != .youtube && !remoteKeys.contains(track.cacheKey)
        }

        var mergedRemote: [Track] = []
        var seenRemote = Set<String>()
        for snapshot in remoteSnapshots {
            let key = snapshot.cacheKey
            if seenRemote.contains(key) { continue }
            seenRemote.insert(key)

            if var existing = existingByKey[key] {
                existing.title = snapshot.title
                existing.artist = snapshot.artist
                if snapshot.duration > 0 {
                    existing.duration = snapshot.duration
                }
                if let art = snapshot.remoteArtworkURL {
                    existing.remoteArtworkURL = art
                }
                mergedRemote.append(existing)
            } else {
                mergedRemote.append(snapshot)
            }
        }

        return mergedRemote + preservedLocalTracks
    }
}
