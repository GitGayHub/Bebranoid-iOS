import Foundation

public enum YouTubeURLKind: String, Codable, Equatable, Sendable {
    case playlist = "playlist"
    case video = "video"
    case invalid = "invalid"
}

public struct ParsedYouTubeInput: Equatable, Sendable {
    public var kind: YouTubeURLKind
    public var playlistId: String?
    public var videoId: String?
    public var canonicalURL: String?

    public init(
        kind: YouTubeURLKind,
        playlistId: String? = nil,
        videoId: String? = nil,
        canonicalURL: String? = nil
    ) {
        self.kind = kind
        self.playlistId = playlistId
        self.videoId = videoId
        self.canonicalURL = canonicalURL
    }
}

/// Точный 1:1 порт `electron/youtube.cjs` (`extractPlaylistId`, `extractVideoId`, `detectUrlKind`).
/// Поддерживает:
/// - `youtube.com/playlist?list=...`, `music.youtube.com/playlist?list=...`
/// - `youtube.com/watch?v=...&list=...` (с выбором режима плейлиста или одиночного видео)
/// - `youtu.be/<videoId>`, `youtube.com/shorts/<videoId>`, `music.youtube.com/watch?v=<videoId>`
/// - Прямые 11-символьные `videoId` и прямые `playlistId` (`PL...`, `OLAK5uy_...`, `UU...`, `FL...`, `LL...`, `RD...`)
public enum YouTubeLinkParser {
    private static let bareVideoIdPattern = #"^[A-Za-z0-9_-]{11}$"#
    private static let barePlaylistIdPattern = #"^(?:PL|OLAK5uy_|UU|FL|LL|RD|WL|VL)[A-Za-z0-9_-]{10,}$"#

    public static func isValidVideoId(_ candidate: String?) -> Bool {
        guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count == 11 else {
            return false
        }
        return raw.range(of: bareVideoIdPattern, options: .regularExpression) != nil
    }

    public static func isValidPlaylistId(_ candidate: String?) -> Bool {
        guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 12 else {
            return false
        }
        return raw.range(of: barePlaylistIdPattern, options: .regularExpression) != nil
    }

    /// Извлекает `playlistId` из URL или голой строки ID (`extractPlaylistId` в `electron/youtube.cjs`)
    public static func extractPlaylistId(_ input: String?) -> String? {
        guard let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        if isValidPlaylistId(trimmed) {
            return trimmed
        }

        if let comps = URLComponents(string: trimmed),
           let listParam = comps.queryItems?.first(where: { $0.name.lowercased() == "list" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
           !listParam.isEmpty {
            return listParam
        }

        // Регулярный фолбэк для неполных ссылок без схемы
        let pattern = #"[?&]list=([A-Za-z0-9_-]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
            return (trimmed as NSString).substring(with: match.range(at: 1))
        }

        return nil
    }

    /// Извлекает 11-символьный `videoId` из URL или голой строки (`extractVideoId` в `electron/youtube.cjs`)
    public static func extractVideoId(_ input: String?) -> String? {
        guard let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        if isValidVideoId(trimmed) {
            return trimmed
        }

        if let comps = URLComponents(string: trimmed),
           let host = comps.host?.lowercased() {
            if host == "youtu.be" || host.hasSuffix(".youtu.be") {
                let pathSeg = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/").first
                if isValidVideoId(pathSeg) {
                    return pathSeg
                }
            }

            if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
                if let vParam = comps.queryItems?.first(where: { $0.name == "v" })?.value,
                   isValidVideoId(vParam) {
                    return vParam
                }

                let segments = comps.path.components(separatedBy: "/").filter { !$0.isEmpty }
                if segments.count >= 2, ["shorts", "embed", "live", "v"].contains(segments[0].lowercased()) {
                    let candidate = segments[1]
                    if isValidVideoId(candidate) {
                        return candidate
                    }
                }
            }
        }

        // Регулярный фолбэк
        let patterns = [
            #"(?:v=|youtu\.be/|/shorts/|/embed/|/live/)([A-Za-z0-9_-]{11})(?:[^A-Za-z0-9_-]|$)"#
        ]
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: []),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                let id = (trimmed as NSString).substring(with: match.range(at: 1))
                if isValidVideoId(id) {
                    return id
                }
            }
        }

        return nil
    }

    /// Определяет тип ссылки YouTube (`detectUrlKind` в `electron/youtube.cjs`)
    /// Если ссылка содержит `/playlist` или параметр `list=` без `v=` — это `.playlist`.
    /// Если ссылка содержит и `v=`, и `list=`, по умолчанию приоритет отдаётся `.playlist`, если `preferPlaylistWhenBoth == true`.
    public static func parseInput(_ input: String?, preferPlaylistWhenBoth: Bool = true) -> ParsedYouTubeInput {
        let playlistId = extractPlaylistId(input)
        let videoId = extractVideoId(input)

        if let playlistId, videoId == nil || preferPlaylistWhenBoth {
            return ParsedYouTubeInput(
                kind: .playlist,
                playlistId: playlistId,
                videoId: videoId,
                canonicalURL: "https://www.youtube.com/playlist?list=\(playlistId)"
            )
        }

        if let videoId {
            return ParsedYouTubeInput(
                kind: .video,
                playlistId: playlistId,
                videoId: videoId,
                canonicalURL: "https://www.youtube.com/watch?v=\(videoId)"
            )
        }

        if let playlistId {
            return ParsedYouTubeInput(
                kind: .playlist,
                playlistId: playlistId,
                videoId: nil,
                canonicalURL: "https://www.youtube.com/playlist?list=\(playlistId)"
            )
        }

        return ParsedYouTubeInput(kind: .invalid)
    }
}
