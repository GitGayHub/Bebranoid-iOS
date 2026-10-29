import Foundation

public struct ImportedYouTubePlaylistResult: Sendable {
    public var playlistId: String
    public var title: String
    public var author: String?
    public var thumbnailURL: String?
    public var tracks: [Track]
    public var canonicalURL: String
    public var nextContinuationToken: String?

    public init(
        playlistId: String,
        title: String,
        author: String? = nil,
        thumbnailURL: String? = nil,
        tracks: [Track],
        canonicalURL: String,
        nextContinuationToken: String? = nil
    ) {
        self.playlistId = playlistId
        self.title = title
        self.author = author
        self.thumbnailURL = thumbnailURL
        self.tracks = tracks
        self.canonicalURL = canonicalURL
        self.nextContinuationToken = nextContinuationToken
    }
}

/// Нативный iOS-сервис YouTube (`electron/youtube.cjs` и `docs/youtube-playlists.md`).
/// Извлекает метаданные плейлистов (до 5000 треков с поддержкой пагинации Innertube `browse` continuation и дедупликацией по `videoId`)
/// и одиночных видео, создавая треки с ID `youtube:<videoId>` и ключом кеша `youtube-<videoId>.m4a`.
///
/// Ограничение нативной среды iOS (без внешнего процесса `yt-dlp` / Node.js):
/// - Если YouTube отдаёт прямой URL потока `audio/mp4` (`itag 140`), файл скачивается с поддержкой `.part` докачки.
/// - Если видео защищено `signatureCipher`, DRM или возрастным ограничением (`playabilityStatus != OK`),
///   сервис честно возвращает диагностическую ошибку без имитации воспроизведения.
public final class YouTubeService: @unchecked Sendable {
    public static let shared = YouTubeService()

    private let session: URLSession

    /// Клиент IOS 19.29.1 YouTube уже отклоняет (`400 Precondition check failed`) — нужна актуальная версия.
    private static let iosClientVersion = "20.10.4"
    private static let iosUserAgent = "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
    /// googlevideo отдаёт `403` на запрос без `Range`, поэтому аудио качается кусками.
    private static let downloadChunkSize: Int64 = 2 * 1024 * 1024

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Импортирует плейлист или одиночное видео по ссылке/ID
    public func fetchYouTubeImport(input: String) async throws -> ImportedYouTubePlaylistResult {
        let parsed = YouTubeLinkParser.parseInput(input)
        switch parsed.kind {
        case .playlist:
            guard let pid = parsed.playlistId else {
                throw NSError(domain: "YouTubeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Не удалось распознать ID плейлиста YouTube"])
            }
            return try await fetchPlaylistMetadata(playlistId: pid)

        case .video:
            guard let vid = parsed.videoId else {
                throw NSError(domain: "YouTubeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Не удалось распознать ID видео YouTube"])
            }
            let singleTrack = try await fetchSingleVideoTrack(videoId: vid)
            return ImportedYouTubePlaylistResult(
                playlistId: "single_\(vid)",
                title: singleTrack.title,
                author: singleTrack.artist,
                thumbnailURL: singleTrack.remoteArtworkURL,
                tracks: [singleTrack],
                canonicalURL: "https://www.youtube.com/watch?v=\(vid)"
            )

        case .invalid:
            throw NSError(
                domain: "YouTubeService",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Поддерживаются ссылки на плейлисты и видео YouTube / YouTube Music / Shorts."]
            )
        }
    }

    /// Загружает метаданные одиночного видео через YouTube oEmbed
    public func fetchSingleVideoTrack(videoId: String) async throws -> Track {
        let oembedURLStr = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json"
        guard let url = URL(string: oembedURLStr) else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: nil)
        }

        var title = "YouTube Track (\(videoId))"
        var author = "YouTube"
        var thumb = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"

        if let (data, resp) = try? await session.data(from: url),
           let http = resp as? HTTPURLResponse,
           http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = json["title"] as? String, !t.isEmpty { title = t }
            if let a = json["author_name"] as? String, !a.isEmpty { author = a }
            if let th = json["thumbnail_url"] as? String, !th.isEmpty { thumb = th }
        }

        let parsedArtistTitle = StorageManager.parseArtistTitleFromFilename(title)
        let finalArtist = parsedArtistTitle.artist != "Неизвестный исполнитель" ? parsedArtistTitle.artist : author
        let finalTitle = parsedArtistTitle.artist != "Неизвестный исполнитель" ? parsedArtistTitle.title : title

        return Track.makeYouTubeTrack(
            videoId: videoId,
            title: finalTitle,
            artist: finalArtist,
            album: "YouTube",
            duration: 0,
            thumbnailURL: thumb
        )
    }

    /// Загружает список видео плейлиста с поддержкой многостраничной пагинации Innertube `browse` (`continuation`)
    /// и дедупликацией до `AppConfig.maxPlaylistTrackLimit` (5000 треков).
    public func fetchPlaylistMetadata(playlistId: String) async throws -> ImportedYouTubePlaylistResult {
        // Основной путь — Innertube `/browse` (VL<playlistId>): HTML-страница в Европе отдаёт consent-экран,
        // а видео теперь приходят в формате `lockupViewModel`, который старый regex не находил
        // (отсюда ошибка «плейлист не найден», хотя он существует). HTML остаётся запасным вариантом.
        var extracted: ImportedYouTubePlaylistResult
        if let viaBrowse = try? await fetchPlaylistFirstPageViaBrowse(playlistId: playlistId),
           !viaBrowse.tracks.isEmpty {
            extracted = viaBrowse
        } else {
            extracted = try await fetchPlaylistFirstPageViaHTML(playlistId: playlistId)
        }

        var seenVideoIds = Set(extracted.tracks.compactMap { $0.youtubeVideoId })
        var continuationToken = extracted.nextContinuationToken
        var pageCount = 1
        let maxContinuationPages = 50 // до 5000 треков

        while let token = continuationToken,
              !token.isEmpty,
              extracted.tracks.count < AppConfig.maxPlaylistTrackLimit,
              pageCount < maxContinuationPages {
            pageCount += 1
            guard let pagePayload = try? await fetchContinuationPageRawJSON(continuationToken: token) else {
                break
            }

            let pageItems = Self.extractPlaylistItemsAndToken(
                fromRawText: pagePayload,
                playlistTitle: extracted.title,
                seenVideoIds: &seenVideoIds,
                remainingLimit: AppConfig.maxPlaylistTrackLimit - extracted.tracks.count
            )
            if pageItems.tracks.isEmpty {
                break
            }
            extracted.tracks.append(contentsOf: pageItems.tracks)
            if pageItems.nextToken == continuationToken {
                break
            }
            continuationToken = pageItems.nextToken
        }

        extracted.nextContinuationToken = continuationToken

        if extracted.tracks.isEmpty {
            throw NSError(
                domain: "YouTubeService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Плейлист пуст или является приватным. Откройте доступ по ссылке и повторите попытку."]
            )
        }
        return extracted
    }

    private static let webUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private func fetchContinuationPageRawJSON(continuationToken: String) async throws -> String {
        try await fetchBrowseRawJSON(extra: ["continuation": continuationToken])
    }

    /// POST `/youtubei/v1/browse` (WEB-клиент) с cookie `SOCS`, снимающим европейский consent-экран.
    private func fetchBrowseRawJSON(extra: [String: Any]) async throws -> String {
        guard let browseURL = URL(string: "https://www.youtube.com/youtubei/v1/browse?prettyPrint=false") else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: nil)
        }

        var payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20250101.00.00",
                    "hl": "ru",
                    "gl": "US"
                ]
            ]
        ]
        for (key, value) in extra {
            payload[key] = value
        }

        var request = URLRequest(url: browseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20.0
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("SOCS=CAI; CONSENT=YES+1", forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let raw = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "YouTubeService",
                code: 502,
                userInfo: [NSLocalizedDescriptionKey: "YouTube вернул ошибку при загрузке плейлиста. Проверьте подключение к интернету."]
            )
        }
        return raw
    }

    private func fetchPlaylistFirstPageViaBrowse(playlistId: String) async throws -> ImportedYouTubePlaylistResult {
        let cleanId = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        let raw = try await fetchBrowseRawJSON(extra: ["browseId": "VL" + cleanId])
        let title = Self.extractPlaylistTitle(fromRawJSON: raw) ?? "YouTube Плейлист"
        var seen = Set<String>()
        let page = Self.extractPlaylistItemsAndToken(
            fromRawText: raw,
            playlistTitle: title,
            seenVideoIds: &seen,
            remainingLimit: AppConfig.maxPlaylistTrackLimit
        )
        return ImportedYouTubePlaylistResult(
            playlistId: cleanId,
            title: title,
            author: nil,
            thumbnailURL: page.tracks.first?.remoteArtworkURL,
            tracks: page.tracks,
            canonicalURL: "https://www.youtube.com/playlist?list=\(cleanId)",
            nextContinuationToken: page.nextToken
        )
    }

    private func fetchPlaylistFirstPageViaHTML(playlistId: String) async throws -> ImportedYouTubePlaylistResult {
        let cleanId = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        let playlistURLStr = "https://www.youtube.com/playlist?list=\(cleanId)&hl=ru"
        guard let url = URL(string: playlistURLStr) else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: nil)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.httpShouldHandleCookies = false
        request.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("SOCS=CAI; CONSENT=YES+1", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "YouTubeService", code: 502, userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить страницу плейлиста YouTube"])
        }
        return Self.parsePlaylistFromHTML(html: html, playlistId: cleanId)
    }

    // MARK: - Structured JSON parsing (lockupViewModel + legacy playlistVideoRenderer)

    struct PlaylistPage {
        var tracks: [Track]
        var continuationToken: String?
    }

    static func extractPlaylistTitle(fromRawJSON raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let metadata = json["metadata"] as? [String: Any],
           let renderer = metadata["playlistMetadataRenderer"] as? [String: Any],
           let title = renderer["title"] as? String, !title.isEmpty {
            return title
        }
        if let header = json["header"] as? [String: Any],
           let renderer = header["pageHeaderRenderer"] as? [String: Any],
           let title = renderer["pageTitle"] as? String, !title.isEmpty {
            return title
        }
        return nil
    }

    /// Разбирает одну страницу ответа `/browse`. Элементы плейлиста берутся из массива, содержащего
    /// `lockupViewModel`/`playlistVideoRenderer`; токен продолжения — из того же массива (а не из меню сортировки).
    static func parsePlaylistPage(json: Any, albumTitle: String) -> PlaylistPage {
        var tracks: [Track] = []
        var token: String?
        scanForItemArrays(node: json, albumTitle: albumTitle, tracks: &tracks, token: &token)
        return PlaylistPage(tracks: tracks, continuationToken: token)
    }

    private static func scanForItemArrays(node: Any, albumTitle: String, tracks: inout [Track], token: inout String?) {
        if let array = node as? [Any] {
            let isItemArray = array.contains { element in
                guard let dict = element as? [String: Any] else { return false }
                return dict["lockupViewModel"] != nil || dict["playlistVideoRenderer"] != nil
            }

            if isItemArray {
                for element in array {
                    guard let dict = element as? [String: Any] else { continue }
                    if let lockup = dict["lockupViewModel"] as? [String: Any] {
                        if let track = trackFromLockup(lockup, albumTitle: albumTitle) {
                            tracks.append(track)
                        }
                    } else if let renderer = dict["playlistVideoRenderer"] as? [String: Any] {
                        if let track = trackFromLegacyRenderer(renderer, albumTitle: albumTitle) {
                            tracks.append(track)
                        }
                    } else if token == nil, let found = findContinuationToken(in: dict) {
                        token = found
                    }
                }
                return
            }

            for element in array {
                scanForItemArrays(node: element, albumTitle: albumTitle, tracks: &tracks, token: &token)
            }
        } else if let dict = node as? [String: Any] {
            for value in dict.values {
                scanForItemArrays(node: value, albumTitle: albumTitle, tracks: &tracks, token: &token)
            }
        }
    }

    private static func trackFromLockup(_ lockup: [String: Any], albumTitle: String) -> Track? {
        guard let videoId = lockup["contentId"] as? String,
              YouTubeLinkParser.isValidVideoId(videoId) else {
            return nil
        }

        let metadataModel = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
        let rawTitle = ((metadataModel?["title"] as? [String: Any])?["content"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawTitle.isEmpty, !isUnavailableTitle(rawTitle) else { return nil }

        var author = ""
        if let contentMetadata = (metadataModel?["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any],
           let rows = contentMetadata["metadataRows"] as? [[String: Any]],
           let parts = rows.first?["metadataParts"] as? [[String: Any]],
           let text = (parts.first?["text"] as? [String: Any])?["content"] as? String {
            author = text
        }

        var duration: Double = 0
        if let badge = firstValue(forKey: "thumbnailBadgeViewModel", in: lockup) as? [String: Any],
           let text = badge["text"] as? String {
            duration = parseClockDuration(text)
        }

        let split = splitArtistTitle(rawTitle: rawTitle, author: author)
        return Track.makeYouTubeTrack(
            videoId: videoId,
            title: split.title,
            artist: split.artist,
            album: albumTitle,
            duration: duration,
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        )
    }

    private static func trackFromLegacyRenderer(_ renderer: [String: Any], albumTitle: String) -> Track? {
        guard let videoId = renderer["videoId"] as? String,
              YouTubeLinkParser.isValidVideoId(videoId) else {
            return nil
        }

        let rawTitle = (((renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]])?.first?["text"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawTitle.isEmpty, !isUnavailableTitle(rawTitle) else { return nil }

        let author = (((renderer["shortBylineText"] as? [String: Any])?["runs"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        let duration = Double((renderer["lengthSeconds"] as? String) ?? "") ?? 0

        let split = splitArtistTitle(rawTitle: rawTitle, author: author)
        return Track.makeYouTubeTrack(
            videoId: videoId,
            title: split.title,
            artist: split.artist,
            album: albumTitle,
            duration: duration,
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        )
    }

    private static func isUnavailableTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return lowered == "deleted video" || lowered == "private video"
            || lowered == "[deleted video]" || lowered == "[private video]"
            || lowered == "удалённое видео" || lowered == "закрытое видео"
    }

    /// `Artist - Title` из названия ролика, иначе имя канала (без суффикса ` - Topic`).
    static func splitArtistTitle(rawTitle: String, author: String) -> (artist: String, title: String) {
        let parsed = StorageManager.parseArtistTitleFromFilename(rawTitle)
        if parsed.artist != "Неизвестный исполнитель" {
            return (parsed.artist, parsed.title)
        }
        var channel = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if channel.hasSuffix(" - Topic") {
            channel = String(channel.dropLast(" - Topic".count))
        }
        return (channel.isEmpty ? "YouTube" : channel, rawTitle)
    }

    /// `3:55` → 235, `1:02:03` → 3723
    static func parseClockDuration(_ text: String) -> Double {
        let parts = text.split(separator: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.count <= 3 else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private static func findContinuationToken(in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let command = dict["continuationCommand"] as? [String: Any],
               let token = command["token"] as? String, !token.isEmpty {
                return token
            }
            for value in dict.values {
                if let token = findContinuationToken(in: value) { return token }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let token = findContinuationToken(in: value) { return token }
            }
        }
        return nil
    }

    private static func firstValue(forKey key: String, in node: Any) -> Any? {
        if let dict = node as? [String: Any] {
            if let direct = dict[key] { return direct }
            for value in dict.values {
                if let found = firstValue(forKey: key, in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = firstValue(forKey: key, in: value) { return found }
            }
        }
        return nil
    }

    /// Выделяет JSON-объект `ytInitialData` из HTML-страницы плейлиста YouTube
    static func extractYtInitialDataJSONString(fromHTML html: String) -> String? {
        let markers = ["var ytInitialData = ", "window[\"ytInitialData\"] = ", "ytInitialData = "]
        for marker in markers {
            guard let startRange = html.range(of: marker) else { continue }
            let afterMarker = html[startRange.upperBound...]
            if let endRange = afterMarker.range(of: ";</script>") {
                let candidate = String(afterMarker[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.hasPrefix("{") && candidate.hasSuffix("}") {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Извлекает название плейлиста, элементы `lockupViewModel` / `playlistVideoRenderer` и токен продолжения `continuationCommand.token` из `ytInitialData`
    public static func parsePlaylistFromHTML(html: String, playlistId: String) -> ImportedYouTubePlaylistResult {
        var playlistTitle = "YouTube Плейлист"
        if let titleRange = html.range(of: #"<meta property="og:title" content="([^"]+)""#, options: .regularExpression) {
            let matchStr = String(html[titleRange])
            if let contentStart = matchStr.range(of: "content=\"")?.upperBound,
               let contentEnd = matchStr.lastIndex(of: "\"") {
                let rawTitle = String(matchStr[contentStart..<contentEnd])
                if !rawTitle.isEmpty, rawTitle.lowercased() != "youtube" {
                    playlistTitle = rawTitle.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
                }
            }
        }
        if playlistTitle == "YouTube Плейлист",
           let initialJSON = extractYtInitialDataJSONString(fromHTML: html),
           let jsonTitle = extractPlaylistTitle(fromRawJSON: initialJSON),
           !jsonTitle.isEmpty {
            playlistTitle = jsonTitle
        }

        var seenVideoIds = Set<String>()
        let parsed = extractPlaylistItemsAndToken(
            fromRawText: html,
            playlistTitle: playlistTitle,
            seenVideoIds: &seenVideoIds,
            remainingLimit: AppConfig.maxPlaylistTrackLimit
        )

        return ImportedYouTubePlaylistResult(
            playlistId: playlistId,
            title: playlistTitle,
            author: nil,
            thumbnailURL: parsed.tracks.first?.remoteArtworkURL,
            tracks: parsed.tracks,
            canonicalURL: "https://www.youtube.com/playlist?list=\(playlistId)",
            nextContinuationToken: parsed.nextToken
        )
    }

    /// Извлекает треки и `continuationCommand.token` из страницы HTML или JSON-ответа `/youtubei/v1/browse`
    public static func extractPlaylistItemsAndToken(
        fromRawText rawText: String,
        playlistTitle: String,
        seenVideoIds: inout Set<String>,
        remainingLimit: Int
    ) -> (tracks: [Track], nextToken: String?) {
        // JSON-ответ `/youtubei/v1/browse` или `var ytInitialData = {...}` внутри HTML:
        // структурный разбор (новый `lockupViewModel` и старый `playlistVideoRenderer`)
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonCandidate: String? = trimmedText.hasPrefix("{")
            ? trimmedText
            : extractYtInitialDataJSONString(fromHTML: rawText)

        if let jsonStr = jsonCandidate,
           let data = jsonStr.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            let page = parsePlaylistPage(json: json, albumTitle: playlistTitle)
            if !page.tracks.isEmpty || trimmedText.hasPrefix("{") {
                var uniqueTracks: [Track] = []
                for track in page.tracks {
                    if uniqueTracks.count >= remainingLimit { break }
                    guard let vid = track.youtubeVideoId, !seenVideoIds.contains(vid) else { continue }
                    seenVideoIds.insert(vid)
                    uniqueTracks.append(track)
                }
                return (uniqueTracks, page.continuationToken)
            }
        }

        let itemPattern = #""playlistVideoRenderer":\{"videoId":"([A-Za-z0-9_-]{11})".*?"title":\{"runs":\[\{"text":"((?:\\.|[^"\\])*)"\}"#
        let regex = try? NSRegularExpression(pattern: itemPattern, options: [])
        let nsText = rawText as NSString
        let matches = regex?.matches(in: rawText, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []

        var tracks: [Track] = []
        for match in matches {
            if tracks.count >= remainingLimit {
                break
            }
            let vid = nsText.substring(with: match.range(at: 1))
            if seenVideoIds.contains(vid) { continue }
            seenVideoIds.insert(vid)

            let rawTitle = nsText.substring(with: match.range(at: 2))
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\u0026", with: "&")

            let parsed = StorageManager.parseArtistTitleFromFilename(rawTitle)
            let thumb = "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg"

            let track = Track.makeYouTubeTrack(
                videoId: vid,
                title: parsed.title,
                artist: parsed.artist,
                album: playlistTitle,
                duration: 0,
                thumbnailURL: thumb
            )
            tracks.append(track)
        }

        let tokenPattern = #""continuationCommand":\{"token":"([^"]+)""#
        var nextToken: String? = nil
        if let tokenRegex = try? NSRegularExpression(pattern: tokenPattern, options: []),
           let tokenMatch = tokenRegex.firstMatch(in: rawText, options: [], range: NSRange(location: 0, length: nsText.length)) {
            nextToken = nsText.substring(with: tokenMatch.range(at: 1))
        }

        return (tracks, nextToken)
    }

    /// Скачивает нативный `m4a (AAC, itag 140)` аудиопоток YouTube кусками по `Range` с настоящей докачкой `.part`
    /// и кооперативным вытеснением между кусками (googlevideo отвечает `403` на запрос без `Range`).
    public func downloadAudioStream(
        for track: Track,
        destinationURL: URL,
        partialURL: URL,
        preemptionToken: DownloadPreemptionToken
    ) async throws -> URL {
        guard let videoId = track.youtubeVideoId, !videoId.isEmpty else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Отсутствует videoId у YouTube-трека"])
        }

        try preemptionToken.throwIfPreempted(key: track.cacheKey)
        let streamURL = try await resolveAudioStreamURL(videoId: videoId)
        try preemptionToken.throwIfPreempted(key: track.cacheKey)

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var offset: Int64 = 0
        if let attrs = try? fileManager.attributesOfItem(atPath: partialURL.path),
           let size = attrs[.size] as? NSNumber {
            offset = size.int64Value
        } else {
            fileManager.createFile(atPath: partialURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: partialURL)
        var total: Int64 = 0

        do {
            while total == 0 || offset < total {
                try preemptionToken.throwIfPreempted(key: track.cacheKey, bytesSaved: offset)

                var request = URLRequest(url: streamURL)
                request.timeoutInterval = 30.0
                request.setValue("bytes=\(offset)-\(offset + Self.downloadChunkSize - 1)", forHTTPHeaderField: "Range")
                request.setValue(Self.iosUserAgent, forHTTPHeaderField: "User-Agent")

                let (data, response) = try await session.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode == 416 {
                    // Запрошенный диапазон за пределами файла: `.part` уже полный
                    break
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 206 || http.statusCode == 200 else {
                    throw NSError(domain: "YouTubeService", code: 502, userInfo: [NSLocalizedDescriptionKey: "Ошибка скачивания аудиопотока YouTube"])
                }

                if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
                   let totalPart = contentRange.split(separator: "/").last,
                   let parsedTotal = Int64(totalPart) {
                    total = parsedTotal
                } else if http.statusCode == 200 {
                    // Сервер проигнорировал Range и отдал файл целиком: начинаем с нуля
                    try handle.truncate(atOffset: 0)
                    offset = 0
                    total = Int64(data.count)
                }

                if data.isEmpty { break }
                try handle.seek(toOffset: UInt64(offset))
                try handle.write(contentsOf: data)
                offset += Int64(data.count)
            }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: partialURL, to: destinationURL)
        return destinationURL
    }

    public func resolveAudioStreamURL(videoId: String) async throws -> URL {
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: nil)
        }

        let clientProfiles: [(name: String, version: String, userAgent: String, extra: [String: Any])] = [
            (
                name: "IOS",
                version: Self.iosClientVersion,
                userAgent: Self.iosUserAgent,
                extra: [
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "osName": "iPhone",
                    "osVersion": "18.3.2.22D82"
                ]
            ),
            (
                name: "ANDROID_VR",
                version: "1.56.21",
                userAgent: "com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1) gzip",
                extra: [
                    "deviceMake": "Oculus",
                    "deviceModel": "Quest 3",
                    "osName": "Android",
                    "osVersion": "12",
                    "androidSdkVersion": 32
                ]
            )
        ]

        var lastError: Error?

        for profile in clientProfiles {
            var clientDict: [String: Any] = [
                "clientName": profile.name,
                "clientVersion": profile.version,
                "hl": "ru",
                "gl": "US"
            ]
            for (k, v) in profile.extra {
                clientDict[k] = v
            }

            let payload: [String: Any] = [
                "videoId": videoId,
                "contentCheckOk": true,
                "racyCheckOk": true,
                "context": ["client": clientDict]
            ]

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 15.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            do {
                let (data, _) = try await session.data(for: request)
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                return try Self.inspectPlayerResponseJSON(root)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(
            domain: "YouTubeService",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "Прямой аудиопоток YouTube недоступен для видео \(videoId) в автономном iOS-режиме."]
        )
    }

    /// Проверяет JSON-ответ `/youtubei/v1/player`:
    /// - Проверяет `playabilityStatus.status == "OK"`
    /// - Извлекает прямой URL `audio/mp4` (`itag 140`) или любой прямой `audio/*` поток
    /// - Честно детектирует `signatureCipher` / DRM без создания фальшивого потока
    public static func inspectPlayerResponseJSON(_ root: [String: Any]) throws -> URL {
        if let playability = root["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           status != "OK" {
            let reason = (playability["reason"] as? String) ?? status
            throw NSError(
                domain: "YouTubeService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Видео YouTube недоступно для прямого воспроизведения (\(reason))."]
            )
        }

        guard let streamingData = root["streamingData"] as? [String: Any] else {
            throw NSError(
                domain: "YouTubeService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "YouTube не вернул streamingData (возможна блокировка региона или возрастное ограничение)."]
            )
        }

        let adaptiveFormats = (streamingData["adaptiveFormats"] as? [[String: Any]]) ?? []
        let muxedFormats = (streamingData["formats"] as? [[String: Any]]) ?? []
        let allFormats = adaptiveFormats + muxedFormats

        // 1. Предпочитаем нативный для iOS контейнер audio/mp4 (itag 140, AAC) с прямым URL
        if let m4aFormat = allFormats.first(where: {
            (($0["itag"] as? Int) == 140 || (($0["mimeType"] as? String)?.contains("audio/mp4") == true))
                && ($0["url"] as? String) != nil
        }), let urlStr = m4aFormat["url"] as? String, let streamURL = URL(string: urlStr) {
            return streamURL
        }

        // 2. Любой прямой аудиопоток с открытым URL
        if let anyAudio = allFormats.first(where: {
            (($0["mimeType"] as? String)?.hasPrefix("audio/") == true)
                && ($0["url"] as? String) != nil
        }), let urlStr = anyAudio["url"] as? String, let streamURL = URL(string: urlStr) {
            return streamURL
        }

        // 3. Честная диагностика signatureCipher / cipher
        let hasSignatureCipher = allFormats.contains {
            $0["signatureCipher"] != nil || $0["cipher"] != nil
        }
        if hasSignatureCipher {
            throw NSError(
                domain: "YouTubeService",
                code: 424,
                userInfo: [NSLocalizedDescriptionKey: "Аудиопоток этого видео YouTube защищён динамическим шифром signatureCipher. В автономном iOS-режиме без внешнего декодера прямое скачивание этого трека ограничено."]
            )
        }

        throw NSError(
            domain: "YouTubeService",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Прямая аудиодорожка m4a не найдена в ответе YouTube."]
        )
    }
}
