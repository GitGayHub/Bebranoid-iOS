import Foundation

public struct CachedLyricsRecord: Codable, Sendable {
    public var trackId: String
    public var title: String
    public var artist: String
    public var album: String?
    public var duration: Double
    public var syncedLyrics: String?
    public var plainLyrics: String?
    public var source: String
    public var translatedLines: [String]?
    public var savedAt: Date
}

public struct LRCLIBCandidate: Codable, Sendable {
    public var id: Int?
    public var trackName: String?
    public var artistName: String?
    public var albumName: String?
    public var duration: Double?
    public var instrumental: Bool?
    public var plainLyrics: String?
    public var syncedLyrics: String?
}

/// Сервис поиска, скоринга и кеширования текстов песен (`electron/main.js` `fetchLyrics` и `scoreLrclibCandidate` 1:1).
/// Порядок разрешения:
/// 1. Проверка индивидуальной блокировки трека (`disabledLyricsTrackIds`)
/// 2. Локальный дисковый кеш (`Lyrics/<safeTrackId>.json`) с проверкой расхождения длительности `<= 8.0s`
/// 3. Встроенные теги аудиофайла (`USLT` / `SYLT` / `©lyr`)
/// 4. Параллельные запросы к `lrclib.net/api/get` и `lrclib.net/api/search` со скорингом кандидатов
public final class LyricsService: @unchecked Sendable {
    public static let shared = LyricsService()

    private let storage: StorageManager
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(storage: StorageManager = .shared, session: URLSession = .shared) {
        self.storage = storage
        self.session = session
    }

    public func cacheFileURL(for trackId: String) -> URL {
        let safe = storage.safeCacheFilename(for: trackId)
        return storage.lyricsCacheDirectory.appendingPathComponent("\(safe).json")
    }

    public func loadCachedLyrics(for track: Track) -> CachedLyricsRecord? {
        let url = cacheFileURL(for: track.id)
        guard let data = try? Data(contentsOf: url),
              let record = try? decoder.decode(CachedLyricsRecord.self, from: data) else {
            return nil
        }

        // Проверяем допуск длительности <= 8 секунд (`electron/main.js`)
        if track.duration > 1 && record.duration > 1 {
            if abs(track.duration - record.duration) > AppConfig.lyricsDurationToleranceSeconds {
                return nil
            }
        }
        return record
    }

    public func saveCachedLyrics(_ record: CachedLyricsRecord) {
        let url = cacheFileURL(for: record.trackId)
        if let data = try? encoder.encode(record) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Оценка кандидата LRCLIB (`scoreLrclibCandidate` в `electron/main.js` 1:1):
    /// - Synced lyrics: +100, Plain lyrics: +35
    /// - Совпадение длительности (в пределах 8 с): до +50 (`diff <= 2s` -> +50, `diff <= 5s` -> +35, `diff <= 8s` -> +15, `diff > 12s` -> -45)
    /// - Совпадение названия (+20), исполнителя (+15), альбома (+25)
    public static func scoreCandidate(
        _ candidate: LRCLIBCandidate,
        targetTitle: String,
        targetArtist: String,
        targetAlbum: String?,
        targetDuration: Double
    ) -> Double {
        let hasSynced = !(candidate.syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPlain = !(candidate.plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasSynced || hasPlain else { return -1000.0 }

        var score = hasSynced ? 100.0 : 35.0

        func norm(_ s: String?) -> String {
            (s ?? "")
                .lowercased()
                .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let candTitle = norm(candidate.trackName)
        let candArtist = norm(candidate.artistName)
        let candAlbum = norm(candidate.albumName)

        let reqTitle = norm(targetTitle)
        let reqArtist = norm(targetArtist)
        let reqAlbum = norm(targetAlbum)

        if !reqTitle.isEmpty && !candTitle.isEmpty {
            if candTitle == reqTitle {
                score += 20.0
            } else if candTitle.contains(reqTitle) || reqTitle.contains(candTitle) {
                score += 10.0
            } else {
                score -= 20.0
            }
        }

        if !reqArtist.isEmpty && !candArtist.isEmpty {
            if candArtist == reqArtist || candArtist.contains(reqArtist) || reqArtist.contains(candArtist) {
                score += 15.0
            }
        }

        if !reqAlbum.isEmpty && !candAlbum.isEmpty && reqAlbum != "без альбома" {
            if candAlbum == reqAlbum || candAlbum.contains(reqAlbum) || reqAlbum.contains(candAlbum) {
                score += 25.0
            }
        }

        if targetDuration > 1.0, let candDur = candidate.duration, candDur > 1.0 {
            let diff = abs(targetDuration - candDur)
            if diff <= 2.0 {
                score += 50.0
            } else if diff <= 5.0 {
                score += 35.0
            } else if diff <= 8.0 {
                score += 15.0
            } else if diff > 12.0 {
                score -= 45.0
            }
        }

        return score
    }

    /// Основной конвейер получения и парсинга текста песни для трека
    public func resolveLyrics(
        for track: Track,
        localFileURL: URL?,
        isDisabledForTrack: Bool
    ) async -> (document: ParsedLyricsDocument, record: CachedLyricsRecord?) {
        if isDisabledForTrack {
            return (ParsedLyricsDocument(kind: .plain, lines: []), nil)
        }

        // 1. Локальный кеш
        if let cached = loadCachedLyrics(for: track) {
            let raw = cached.syncedLyrics ?? cached.plainLyrics
            var doc = LRCParser.parseLRC(raw)
            if let translations = cached.translatedLines {
                doc = Self.attachTranslations(translations, to: doc)
            }
            return (doc, cached)
        }

        // 2. Встроенные теги аудиофайла
        if let fileURL = localFileURL {
            let meta = await AudioMetadataReader.inspectAudioFile(at: fileURL)
            if let embedded = meta.embeddedLyrics, !embedded.isEmpty {
                let doc = LRCParser.parseLRC(embedded)
                let record = CachedLyricsRecord(
                    trackId: track.id,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration,
                    syncedLyrics: doc.kind != .plain ? embedded : nil,
                    plainLyrics: doc.kind == .plain ? embedded : nil,
                    source: "embedded",
                    translatedLines: nil,
                    savedAt: Date()
                )
                saveCachedLyrics(record)
                return (doc, record)
            }
        }

        // 3. Поиск через LRCLIB (параллельно /api/get и /api/search)
        if let best = await fetchFromLRCLIB(track: track) {
            let raw = (best.syncedLyrics?.isEmpty == false) ? best.syncedLyrics : best.plainLyrics
            let doc = LRCParser.parseLRC(raw)
            let record = CachedLyricsRecord(
                trackId: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                syncedLyrics: best.syncedLyrics,
                plainLyrics: best.plainLyrics,
                source: "lrclib",
                translatedLines: nil,
                savedAt: Date()
            )
            saveCachedLyrics(record)
            return (doc, record)
        }

        return (ParsedLyricsDocument(kind: .plain, lines: []), nil)
    }

    public static func attachTranslations(_ translations: [String], to document: ParsedLyricsDocument) -> ParsedLyricsDocument {
        var updated = document
        for i in 0..<min(updated.lines.count, translations.count) {
            let tr = translations[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !tr.isEmpty && tr.lowercased() != updated.lines[i].text.lowercased() {
                updated.lines[i].translation = tr
            }
        }
        return updated
    }

    private func fetchFromLRCLIB(track: Track) async -> LRCLIBCandidate? {
        let primaryArtist = ArtistSplitter.splitArtists(track.artist).first ?? track.artist
        let cleanTitle = Self.stripTrackNoise(track.title)

        async let getWithAlbum = requestLRCLIBGet(
            title: cleanTitle,
            artist: primaryArtist,
            album: track.album,
            duration: track.duration
        )
        async let getWithoutAlbum = requestLRCLIBGet(
            title: cleanTitle,
            artist: primaryArtist,
            album: nil,
            duration: track.duration
        )
        async let searchResults = requestLRCLIBSearch(
            query: "\(primaryArtist) \(cleanTitle)"
        )

        var candidates: [LRCLIBCandidate] = []
        if let c1 = await getWithAlbum { candidates.append(c1) }
        if let c2 = await getWithoutAlbum { candidates.append(c2) }
        candidates.append(contentsOf: await searchResults)

        guard !candidates.isEmpty else { return nil }

        let best = candidates.max { a, b in
            Self.scoreCandidate(a, targetTitle: cleanTitle, targetArtist: primaryArtist, targetAlbum: track.album, targetDuration: track.duration) <
            Self.scoreCandidate(b, targetTitle: cleanTitle, targetArtist: primaryArtist, targetAlbum: track.album, targetDuration: track.duration)
        }

        if let best,
           Self.scoreCandidate(best, targetTitle: cleanTitle, targetArtist: primaryArtist, targetAlbum: track.album, targetDuration: track.duration) > 0 {
            return best
        }
        return nil
    }

    private func requestLRCLIBGet(title: String, artist: String, album: String?, duration: Double) async -> LRCLIBCandidate? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let album, !album.isEmpty, album != "Без альбома" {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 1 {
            items.append(URLQueryItem(name: "duration", value: String(Int(round(duration)))))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 7.0
        req.setValue("Bebranoid-iOS/2.0 (https://github.com/GitGayHub/Bebranoid)", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              http.statusCode == 200 else {
            return nil
        }
        return try? decoder.decode(LRCLIBCandidate.self, from: data)
    }

    private func requestLRCLIBSearch(query: String) async -> [LRCLIBCandidate] {
        var comps = URLComponents(string: "https://lrclib.net/api/search")
        comps?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = comps?.url else { return [] }

        var req = URLRequest(url: url)
        req.timeoutInterval = 7.0
        req.setValue("Bebranoid-iOS/2.0 (https://github.com/GitGayHub/Bebranoid)", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              http.statusCode == 200,
              let list = try? decoder.decode([LRCLIBCandidate].self, from: data) else {
            return []
        }
        return list
    }

    public static func stripTrackNoise(_ title: String) -> String {
        title
            .replacingOccurrences(of: #"\s*\((?:feat\.?|ft\.?|prod\.?|official|audio|video|lyrics|visualizer|slowed|reverb|speed up)[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\[(?:feat\.?|ft\.?|prod\.?|official|audio|video|lyrics)[^\]]*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
