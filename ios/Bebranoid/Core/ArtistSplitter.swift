import Foundation

/// Точный 1:1 порт `src/lib/artists.js`
public enum ArtistSplitter {
    private static let unknownArtist = "Неизвестный исполнитель"

    /// Разделяет строку исполнителей по разделителям:
    /// `/\s*[,&/;|\\]\s*|\s+feat\.?\s+|\s+ft\.?\s+|\s+[x×]\s+|\s+и\s+/i`
    public static func splitArtists(_ rawArtist: String?) -> [String] {
        guard let raw = rawArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return [unknownArtist]
        }

        let pattern = #"\s*[,&/;|\\]\s*|\s+feat\.?\s+|\s+ft\.?\s+|\s+[x×]\s+|\s+и\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [raw]
        }

        let nsString = raw as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: raw, options: [], range: fullRange)

        var parts: [String] = []
        var lastIndex = 0
        for match in matches {
            let segmentRange = NSRange(location: lastIndex, length: match.range.location - lastIndex)
            let segment = nsString.substring(with: segmentRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                parts.append(segment)
            }
            lastIndex = match.range.location + match.range.length
        }

        if lastIndex < nsString.length {
            let tail = nsString.substring(from: lastIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                parts.append(tail)
            }
        }

        // Удаляем дубликаты без учёта регистра с сохранением порядка
        var seen = Set<String>()
        var unique: [String] = []
        for p in parts {
            let key = normalizeArtistKey(p)
            if !key.isEmpty && !seen.contains(key) {
                seen.insert(key)
                unique.append(p)
            }
        }

        return unique.isEmpty ? [unknownArtist] : unique
    }

    public static func normalizeArtistKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    /// Выбирает наиболее качественное написание имени артиста (предпочитает смешанный регистр / Title Case вместо ALL CAPS или all lowercase)
    public static func pickBestSpelling(_ variants: [String: Int]) -> String {
        guard !variants.isEmpty else { return unknownArtist }

        func scoreVariant(_ text: String, count: Int) -> Double {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isAllLower = trimmed == trimmed.lowercased()
            let isAllUpper = trimmed == trimmed.uppercased() && trimmed.count > 1
            var styleBonus = 0.0
            if !isAllLower && !isAllUpper {
                styleBonus = 2.5
            } else if isAllUpper {
                styleBonus = 1.0
            }
            return Double(count) + styleBonus
        }

        return variants.max { a, b in
            let scoreA = scoreVariant(a.key, count: a.value)
            let scoreB = scoreVariant(b.key, count: b.value)
            if abs(scoreA - scoreB) > 1e-6 {
                return scoreA < scoreB
            }
            return a.key > b.key
        }?.key ?? unknownArtist
    }

    /// Группирует все треки медиатеки по отдельным исполнителям
    public static func buildArtistSummaries(
        tracks: [Track],
        favoriteArtistKeys: Set<String>
    ) -> [ArtistSummary] {
        var tracksByKey: [String: [Track]] = [:]
        var albumsByKey: [String: Set<String>] = [:]
        var spellingsByKey: [String: [String: Int]] = [:]

        for track in tracks {
            let names = splitArtists(track.artist)
            for name in names {
                let key = normalizeArtistKey(name)
                tracksByKey[key, default: []].append(track)
                if !track.album.isEmpty {
                    albumsByKey[key, default: []].insert(track.album)
                }
                spellingsByKey[key, default: [:]][name, default: 0] += 1
            }
        }

        var summaries: [ArtistSummary] = []
        for (key, artistTracks) in tracksByKey {
            let bestName = pickBestSpelling(spellingsByKey[key] ?? [key: 1])
            let sortedAlbums = Array(albumsByKey[key] ?? []).sorted()
            let isPinned = favoriteArtistKeys.contains(key) || favoriteArtistKeys.contains(bestName.lowercased())
            summaries.append(
                ArtistSummary(
                    normalizedKey: key,
                    displayName: bestName,
                    tracks: artistTracks,
                    albums: sortedAlbums,
                    isPinnedFavorite: isPinned
                )
            )
        }

        return summaries.sorted { a, b in
            if a.isPinnedFavorite != b.isPinnedFavorite {
                return a.isPinnedFavorite && !b.isPinnedFavorite
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }
}
