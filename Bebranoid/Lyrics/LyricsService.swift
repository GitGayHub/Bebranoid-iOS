import Foundation

public struct CachedLyricsRecord: Codable, Sendable {
    public static let currentSchemaVersion: Int = 2

    public var schemaVersion: Int
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

    public init(
        schemaVersion: Int = CachedLyricsRecord.currentSchemaVersion,
        trackId: String,
        title: String,
        artist: String,
        album: String?,
        duration: Double,
        syncedLyrics: String?,
        plainLyrics: String?,
        source: String,
        translatedLines: [String]?,
        savedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.trackId = trackId
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.syncedLyrics = syncedLyrics
        self.plainLyrics = plainLyrics
        self.source = source
        self.translatedLines = translatedLines
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case trackId
        case title
        case artist
        case album
        case duration
        case syncedLyrics
        case plainLyrics
        case source
        case translatedLines
        case savedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Записи старого кеша без `schemaVersion` получают версию `1` и автоматически обновляются до YouTube-синка v2
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.trackId = try c.decode(String.self, forKey: .trackId)
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        self.album = try c.decodeIfPresent(String.self, forKey: .album)
        self.duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        self.syncedLyrics = try c.decodeIfPresent(String.self, forKey: .syncedLyrics)
        self.plainLyrics = try c.decodeIfPresent(String.self, forKey: .plainLyrics)
        self.source = try c.decodeIfPresent(String.self, forKey: .source) ?? "lrclib"
        self.translatedLines = try c.decodeIfPresent([String].self, forKey: .translatedLines)
        self.savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
    }
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

private struct ResolvedOnlineLyricsCandidate: Sendable {
    let rawSynced: String?
    let rawPlain: String?
    let document: ParsedLyricsDocument
    let remoteDuration: Double?
    let source: String
    let providerBonus: Double
}

/// Сервис высокоточного поиска, скоринга и кеширования синхронизированных текстов песен (YouTube Music / BetterLyrics TTML + YouTube RichSync + LRCLIB).
/// Порядок разрешения:
/// 1. Проверка индивидуальной блокировки трека (`disabledLyricsTrackIds`)
/// 2. Локальный дисковый кеш (`schemaVersion == 2`, допуск длительности `<= 3.8s`)
/// 3. Встроенные синхронизированные теги аудиофайла (`SYLT` / LRC в `USLT` / `©lyr`) + точная длительность аудиофайла
/// 4. Параллельный опрос YouTube Music (`lyrics-api.boidu.dev` TTML + `music.youtube.com` `videoId` -> `SimpMusic` RichSync) и `LRCLIB` с жёсткой проверкой совпадения длительности
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

    public func loadCachedLyrics(for track: Track, effectiveDuration: Double? = nil) -> CachedLyricsRecord? {
        let url = cacheFileURL(for: track.id)
        guard let data = try? Data(contentsOf: url),
              let record = try? decoder.decode(CachedLyricsRecord.self, from: data) else {
            return nil
        }

        guard record.schemaVersion >= CachedLyricsRecord.currentSchemaVersion else {
            return nil
        }

        let targetDur = effectiveDuration ?? track.duration
        if targetDur > 1 && record.duration > 1 {
            if abs(targetDur - record.duration) > AppConfig.lyricsDurationToleranceSeconds {
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

    /// Оценка кандидата LRCLIB с приоритетом пословного караоке `<mm:ss.xx>` и жёстким штрафом за расхождение длительности (клип vs альбом)
    public static func scoreCandidate(
        _ candidate: LRCLIBCandidate,
        targetTitle: String,
        targetArtist: String,
        targetAlbum: String?,
        targetDuration: Double
    ) -> Double {
        let syncedRaw = (candidate.syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let plainRaw = (candidate.plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSynced = !syncedRaw.isEmpty
        let hasPlain = !plainRaw.isEmpty
        guard hasSynced || hasPlain else { return -1000.0 }

        var score = hasSynced ? 105.0 : 30.0
        if hasSynced && syncedRaw.range(of: #"<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>"#, options: .regularExpression) != nil {
            score += 45.0
        }

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
                score += 24.0
            } else if candTitle.contains(reqTitle) || reqTitle.contains(candTitle) {
                score += 10.0
            } else {
                score -= 25.0
            }
        }

        if !reqArtist.isEmpty && !candArtist.isEmpty {
            if candArtist == reqArtist {
                score += 20.0
            } else if candArtist.contains(reqArtist) || reqArtist.contains(candArtist) {
                score += 12.0
            } else {
                score -= 18.0
            }
        }

        if !reqAlbum.isEmpty && !candAlbum.isEmpty && reqAlbum != "без альбома" && reqAlbum != "youtube" {
            if candAlbum == reqAlbum {
                score += 14.0
            } else if candAlbum.contains(reqAlbum) || reqAlbum.contains(candAlbum) {
                score += 6.0
            }
        }

        if targetDuration > 1.0, let candDur = candidate.duration, candDur > 1.0 {
            let diff = abs(targetDuration - candDur)
            if diff <= 1.5 {
                score += 70.0
            } else if diff <= 3.0 {
                score += 45.0
            } else if diff <= 4.2 {
                score += 12.0
            } else {
                score -= 95.0
            }
        }

        return score
    }

    /// Основной конвейер получения и парсинга идеально синхронизированного текста песни для трека
    public func resolveLyrics(
        for track: Track,
        localFileURL: URL?,
        isDisabledForTrack: Bool
    ) async -> (document: ParsedLyricsDocument, record: CachedLyricsRecord?) {
        if isDisabledForTrack {
            return (ParsedLyricsDocument(kind: .plain, lines: []), nil)
        }

        // Проверяем реальную длительность и встроенные теги локального аудиофайла, если он уже в кеше
        var effectiveDuration = track.duration
        var embeddedPlainFallback: (doc: ParsedLyricsDocument, raw: String)? = nil

        if let fileURL = localFileURL {
            let meta = await AudioMetadataReader.inspectAudioFile(at: fileURL)
            if meta.duration > 1.0 {
                effectiveDuration = meta.duration
            }
            if let embedded = meta.embeddedLyrics, !embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let embeddedDoc = LRCParser.parseLRC(embedded)
                if embeddedDoc.kind != .plain && !embeddedDoc.lines.isEmpty {
                    let record = CachedLyricsRecord(
                        trackId: track.id,
                        title: track.title,
                        artist: track.artist,
                        album: track.album,
                        duration: effectiveDuration,
                        syncedLyrics: embedded,
                        plainLyrics: nil,
                        source: "embedded-synced",
                        translatedLines: nil,
                        savedAt: Date()
                    )
                    saveCachedLyrics(record)
                    return (embeddedDoc, record)
                } else if !embeddedDoc.lines.isEmpty {
                    embeddedPlainFallback = (embeddedDoc, embedded)
                }
            }
        }

        // 1. Локальный кеш v2 (или сохраняем ранее переведённые строки при обновлении с v1)
        let previousTranslations: [String]? = {
            let url = cacheFileURL(for: track.id)
            guard let data = try? Data(contentsOf: url),
                  let old = try? decoder.decode(CachedLyricsRecord.self, from: data) else {
                return nil
            }
            return old.translatedLines
        }()

        if let cached = loadCachedLyrics(for: track, effectiveDuration: effectiveDuration) {
            let raw = cached.syncedLyrics ?? cached.plainLyrics
            var doc = LRCParser.parseLRC(raw)
            if let translations = cached.translatedLines {
                doc = Self.attachTranslations(translations, to: doc)
            }
            if !doc.lines.isEmpty {
                return (doc, cached)
            }
        }

        // 2. Параллельный поиск идеальной синхронизации: YouTube Music TTML + YouTube videoId RichSync + LRCLIB
        let primaryArtist = ArtistSplitter.splitArtists(track.artist).first ?? track.artist
        let cleanTitle = Self.stripTrackNoise(track.title)

        async let betterLyricsTask = fetchFromBetterLyricsYouTubeMusic(
            title: cleanTitle,
            artist: primaryArtist,
            album: track.album,
            targetDuration: effectiveDuration
        )
        async let youtubeSimpTask = fetchFromYouTubeSimpMusic(
            track: track,
            cleanTitle: cleanTitle,
            primaryArtist: primaryArtist,
            targetDuration: effectiveDuration
        )
        async let lrclibTask = fetchFromLRCLIBResolved(
            track: track,
            cleanTitle: cleanTitle,
            primaryArtist: primaryArtist,
            targetDuration: effectiveDuration
        )

        var pool: [ResolvedOnlineLyricsCandidate] = []
        if let c1 = await betterLyricsTask { pool.append(c1) }
        if let c2 = await youtubeSimpTask { pool.append(c2) }
        if let c3 = await lrclibTask { pool.append(c3) }

        if let winner = Self.pickBestResolvedCandidate(pool, targetDuration: effectiveDuration) {
            var finalDoc = winner.document
            let keptTranslations: [String]? = (previousTranslations?.count == finalDoc.lines.count) ? previousTranslations : nil
            if let keptTranslations {
                finalDoc = Self.attachTranslations(keptTranslations, to: finalDoc)
            }

            let record = CachedLyricsRecord(
                trackId: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: effectiveDuration > 1 ? effectiveDuration : (winner.remoteDuration ?? track.duration),
                syncedLyrics: winner.rawSynced,
                plainLyrics: winner.rawPlain,
                source: winner.source,
                translatedLines: keptTranslations,
                savedAt: Date()
            )
            saveCachedLyrics(record)
            return (finalDoc, record)
        }

        // 3. Если онлайн-синхронизация не найдена, возвращаем встроенный несинхронизированный текст (если был в тегах)
        if let fallback = embeddedPlainFallback {
            let record = CachedLyricsRecord(
                trackId: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: effectiveDuration,
                syncedLyrics: nil,
                plainLyrics: fallback.raw,
                source: "embedded-plain",
                translatedLines: nil,
                savedAt: Date()
            )
            saveCachedLyrics(record)
            return (fallback.doc, record)
        }

        return (ParsedLyricsDocument(kind: .plain, lines: []), nil)
    }

    private static func pickBestResolvedCandidate(
        _ candidates: [ResolvedOnlineLyricsCandidate],
        targetDuration: Double
    ) -> ResolvedOnlineLyricsCandidate? {
        guard !candidates.isEmpty else { return nil }

        func totalScore(_ c: ResolvedOnlineLyricsCandidate) -> Double {
            guard !c.document.lines.isEmpty else { return -1000.0 }
            var s = c.providerBonus
            switch c.document.kind {
            case .word:
                s += 165.0
            case .line:
                s += 115.0
            case .plain:
                s += 25.0
            }

            if targetDuration > 1.0, let remDur = c.remoteDuration, remDur > 1.0 {
                let diff = abs(targetDuration - remDur)
                if diff <= 1.5 {
                    s += 65.0
                } else if diff <= 3.2 {
                    s += 40.0
                } else if diff <= 4.5 {
                    s += 8.0
                } else {
                    s -= 120.0
                }
            }
            return s
        }

        let best = candidates.max { totalScore($0) < totalScore($1) }
        guard let best, totalScore(best) > 0 else { return nil }
        return best
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

    // MARK: - Provider 1: BetterLyrics for YouTube Music TTML (`lyrics-api.boidu.dev`)

    private func fetchFromBetterLyricsYouTubeMusic(
        title: String,
        artist: String,
        album: String?,
        targetDuration: Double
    ) async -> ResolvedOnlineLyricsCandidate? {
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        var comps = URLComponents(string: "https://lyrics-api.boidu.dev/getLyrics")
        var items = [
            URLQueryItem(name: "s", value: title),
            URLQueryItem(name: "a", value: artist)
        ]
        if let album, !album.isEmpty, album != "Без альбома", album.lowercased() != "youtube" {
            items.append(URLQueryItem(name: "al", value: album))
        }
        if targetDuration > 1.0 {
            items.append(URLQueryItem(name: "d", value: String(Int(round(targetDuration)))))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5.5
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ttml = json["ttml"] as? String,
              !ttml.isEmpty else {
            return nil
        }

        let doc = LRCParser.parseTTML(ttml)
        guard !doc.lines.isEmpty else { return nil }

        // Извлекаем общую длительность из `<body dur="...">`, чтобы убедиться, что это не клип другой длины
        var bodyDuration: Double? = nil
        if let durRegex = try? NSRegularExpression(pattern: #"<body\b[^>]*\bdur\s*=\s*"([^"]+)""#, options: [.caseInsensitive]),
           let m = durRegex.firstMatch(in: ttml, options: [], range: NSRange(location: 0, length: (ttml as NSString).length)) {
            let durRaw = (ttml as NSString).substring(with: m.range(at: 1))
            bodyDuration = LRCParser.parseFlexibleTimestamp(durRaw)
        }
        if targetDuration > 1.0, let bDur = bodyDuration, abs(targetDuration - bDur) > 4.2 {
            return nil
        }
        if targetDuration > 1.0, let lastLineEnd = doc.lines.last?.endTime, lastLineEnd > targetDuration + 3.5 {
            return nil
        }

        return ResolvedOnlineLyricsCandidate(
            rawSynced: ttml,
            rawPlain: nil,
            document: doc,
            remoteDuration: bodyDuration ?? targetDuration,
            source: "youtube-music-ttml",
            providerBonus: 34.0
        )
    }

    // MARK: - Provider 2: YouTube Music `videoId` + SimpMusic RichSync (`api-lyrics.simpmusic.org`)

    private func fetchFromYouTubeSimpMusic(
        track: Track,
        cleanTitle: String,
        primaryArtist: String,
        targetDuration: Double
    ) async -> ResolvedOnlineLyricsCandidate? {
        var videoCandidates: [(videoId: String, isDirectTrackVideo: Bool)] = []

        if let directVid = track.youtubeVideoId, !directVid.isEmpty {
            videoCandidates.append((directVid, true))
        }

        let searchedVids = await searchYouTubeMusicSongVideoIds(
            query: "\(primaryArtist) \(cleanTitle)",
            targetDuration: targetDuration
        )
        for vid in searchedVids where !videoCandidates.contains(where: { $0.videoId == vid }) {
            videoCandidates.append((vid, false))
        }

        for candidate in videoCandidates.prefix(3) {
            if let resolved = await requestSimpMusicByVideoId(
                videoId: candidate.videoId,
                isDirectTrackVideo: candidate.isDirectTrackVideo,
                targetDuration: targetDuration
            ) {
                return resolved
            }
        }
        return nil
    }

    private func searchYouTubeMusicSongVideoIds(query: String, targetDuration: Double) async -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false") else {
            return []
        }

        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20250101.01.00",
                    "hl": "ru",
                    "gl": "US"
                ]
            ],
            "query": trimmed,
            "params": "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D" // Официальный фильтр «Песни» (Songs) в YouTube Music
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              http.statusCode == 200,
              let raw = String(data: data, encoding: .utf8) else {
            return []
        }

        guard let regex = try? NSRegularExpression(pattern: #""videoId"\s*:\s*"([A-Za-z0-9_-]{11})""#, options: []) else {
            return []
        }
        let ns = raw as NSString
        var uniqueIds: [String] = []
        for m in regex.matches(in: raw, options: [], range: NSRange(location: 0, length: ns.length)) {
            let vid = ns.substring(with: m.range(at: 1))
            if !uniqueIds.contains(vid) {
                uniqueIds.append(vid)
            }
            if uniqueIds.count >= 3 { break }
        }
        return uniqueIds
    }

    private func requestSimpMusicByVideoId(
        videoId: String,
        isDirectTrackVideo: Bool,
        targetDuration: Double
    ) async -> ResolvedOnlineLyricsCandidate? {
        guard let url = URL(string: "https://api-lyrics.simpmusic.org/v1/\(videoId)") else {
            return nil
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5.0
        req.setValue("SimpMusicLyrics/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]],
              !items.isEmpty else {
            return nil
        }

        var bestCandidate: ResolvedOnlineLyricsCandidate? = nil
        var bestScore: Double = -1000.0

        for item in items {
            let itemDur: Double? = {
                if let d = item["durationSeconds"] as? Double { return d }
                if let i = item["durationSeconds"] as? Int { return Double(i) }
                if let s = item["durationSeconds"] as? String, let d = Double(s) { return d }
                return nil
            }()

            if !isDirectTrackVideo, targetDuration > 1.0, let itemDur, itemDur > 1.0 {
                if abs(targetDuration - itemDur) > 4.2 {
                    continue
                }
            }

            let richRaw = (item["richSyncLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let syncedRaw = (item["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let plainRaw = (item["plainLyric"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let chosenSynced = (richRaw?.isEmpty == false) ? richRaw : ((syncedRaw?.isEmpty == false) ? syncedRaw : nil)
            let rawToParse = chosenSynced ?? plainRaw
            guard let rawToParse, !rawToParse.isEmpty else { continue }

            let doc = LRCParser.parseLRC(rawToParse)
            guard !doc.lines.isEmpty else { continue }

            if targetDuration > 1.0, let lastStart = doc.lines.last?.time, lastStart > targetDuration + 2.5 {
                continue
            }

            let bonus: Double = isDirectTrackVideo ? 42.0 : 30.0
            let durPenalty: Double = {
                guard targetDuration > 1.0, let itemDur, itemDur > 1.0 else { return 0.0 }
                return -abs(targetDuration - itemDur) * 4.0
            }()
            let candScore = bonus + (doc.kind == .word ? 165.0 : (doc.kind == .line ? 115.0 : 25.0)) + durPenalty

            if candScore > bestScore {
                bestScore = candScore
                bestCandidate = ResolvedOnlineLyricsCandidate(
                    rawSynced: chosenSynced,
                    rawPlain: plainRaw,
                    document: doc,
                    remoteDuration: itemDur,
                    source: isDirectTrackVideo ? "youtube-video-richsync" : "youtube-music-richsync",
                    providerBonus: bonus
                )
            }
        }

        return bestCandidate
    }

    // MARK: - Provider 3: LRCLIB (`/api/get` + `/api/search`)

    private func fetchFromLRCLIBResolved(
        track: Track,
        cleanTitle: String,
        primaryArtist: String,
        targetDuration: Double
    ) async -> ResolvedOnlineLyricsCandidate? {
        guard let best = await fetchFromLRCLIB(
            track: track,
            cleanTitle: cleanTitle,
            primaryArtist: primaryArtist,
            targetDuration: targetDuration
        ) else {
            return nil
        }
        let hasSynced = (best.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        let raw = hasSynced ? best.syncedLyrics : best.plainLyrics
        let doc = LRCParser.parseLRC(raw)
        guard !doc.lines.isEmpty else { return nil }

        return ResolvedOnlineLyricsCandidate(
            rawSynced: hasSynced ? best.syncedLyrics : nil,
            rawPlain: best.plainLyrics,
            document: doc,
            remoteDuration: best.duration,
            source: "lrclib",
            providerBonus: 22.0
        )
    }

    private func fetchFromLRCLIB(
        track: Track,
        cleanTitle: String,
        primaryArtist: String,
        targetDuration: Double
    ) async -> LRCLIBCandidate? {
        async let getWithAlbum = requestLRCLIBGet(
            title: cleanTitle,
            artist: primaryArtist,
            album: track.album,
            duration: targetDuration
        )
        async let getWithoutAlbum = requestLRCLIBGet(
            title: cleanTitle,
            artist: primaryArtist,
            album: nil,
            duration: targetDuration
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
            Self.scoreCandidate(a, targetTitle: cleanTitle, targetArtist: primaryArtist, targetAlbum: track.album, targetDuration: targetDuration) <
            Self.scoreCandidate(b, targetTitle: cleanTitle, targetArtist: primaryArtist, targetAlbum: track.album, targetDuration: targetDuration)
        }

        if let best,
           Self.scoreCandidate(best, targetTitle: cleanTitle, targetArtist: primaryArtist, targetAlbum: track.album, targetDuration: targetDuration) > 20.0 {
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
        if let album, !album.isEmpty, album != "Без альбома", album.lowercased() != "youtube" {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 1 {
            items.append(URLQueryItem(name: "duration", value: String(Int(round(duration)))))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 6.0
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
        req.timeoutInterval = 6.0
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
            .replacingOccurrences(of: #"\s*\((?:feat\.?|ft\.?|prod\.?|official|audio|video|music video|lyric video|lyrics|visualizer|hd|hq|4k|remaster(?:ed)?)[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\[(?:feat\.?|ft\.?|prod\.?|official|audio|video|music video|lyric video|lyrics|visualizer|hd|hq|4k)[^\]]*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
