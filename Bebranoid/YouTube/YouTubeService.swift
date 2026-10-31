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
    private static let visionOSClientVersion = "1.02"
    private static let visionOSUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private static let androidClientVersion = "20.10.38"
    private static let androidUserAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 15; en_US) gzip"
    /// googlevideo отдаёт `403` на запрос без `Range` и на чанки > 1 МБ без PoToken, поэтому аудио качается кусками по 512 КБ.
    private static let downloadChunkSize: Int64 = 512 * 1024

    private static let cookieFreeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 25.0
        return URLSession(configuration: config)
    }()

    public init(session: URLSession? = nil) {
        self.session = session ?? Self.cookieFreeSession
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
        preemptionToken: DownloadPreemptionToken,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> URL {
        guard let videoId = track.youtubeVideoId, !videoId.isEmpty else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Отсутствует videoId у YouTube-трека"])
        }

        onProgress?(1)
        try preemptionToken.throwIfPreempted(key: track.cacheKey)
        let candidates = try await resolveAudioStreamCandidates(videoId: videoId)
        try preemptionToken.throwIfPreempted(key: track.cacheKey)
        onProgress?(3)

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lastDownloadError: Error?
        for (candidateIndex, candidate) in candidates.enumerated() {
            do {
                let activePartURL = candidate.isWebMOpus
                    ? partialURL.deletingPathExtension().appendingPathExtension("webm.part")
                    : partialURL
                if candidateIndex > 0 {
                    try? fileManager.removeItem(at: activePartURL)
                }
                try await downloadRawStreamToFile(
                    streamURL: candidate.url,
                    partialURL: activePartURL,
                    cacheKey: track.cacheKey,
                    preemptionToken: preemptionToken,
                    onProgress: onProgress
                )

                if candidate.isWebMOpus {
                    let cafTargetURL = destinationURL.deletingPathExtension().appendingPathExtension("caf")
                    do {
                        try WebMOpusRemuxer.remuxWebMFileToVerifiedCAF(
                            webmURL: activePartURL,
                            cafDestinationURL: cafTargetURL
                        )
                        try? fileManager.removeItem(at: activePartURL)
                        try? fileManager.removeItem(at: destinationURL)
                        onProgress?(100)
                        return cafTargetURL
                    } catch {
                        // Если ремукс WebM Opus не прошёл валидацию AVAudioFile, прозрачно переходим к нативному AAC (itag 141/140)
                        try? fileManager.removeItem(at: activePartURL)
                        try? fileManager.removeItem(at: cafTargetURL)
                        lastDownloadError = error
                        continue
                    }
                } else {
                    try? fileManager.removeItem(at: destinationURL)
                    try fileManager.moveItem(at: activePartURL, to: destinationURL)
                    onProgress?(100)
                    return destinationURL
                }
            } catch let preempt as DownloadPreemptedError {
                throw preempt
            } catch {
                lastDownloadError = error
                continue
            }
        }

        throw lastDownloadError ?? NSError(
            domain: "YouTubeService",
            code: 502,
            userInfo: [NSLocalizedDescriptionKey: "Не удалось скачать аудиопоток YouTube максимального качества"]
        )
    }

    private func downloadRawStreamToFile(
        streamURL: URL,
        partialURL: URL,
        cacheKey: String,
        preemptionToken: DownloadPreemptionToken,
        onProgress: (@Sendable (Int) -> Void)?
    ) async throws {
        let fileManager = FileManager.default
        var offset: Int64 = 0
        if let attrs = try? fileManager.attributesOfItem(atPath: partialURL.path),
           let size = attrs[.size] as? NSNumber,
           size.int64Value > 0 {
            offset = size.int64Value
        } else {
            try? fileManager.removeItem(at: partialURL)
            fileManager.createFile(atPath: partialURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: partialURL)
        var total: Int64 = 0
        let streamURLString = streamURL.absoluteString
        let isVisionOSStream = streamURLString.contains("c=VISIONOS")
        let isAndroidStream = streamURLString.contains("c=ANDROID")
        let streamUserAgent = isVisionOSStream ? Self.visionOSUserAgent : (isAndroidStream ? Self.androidUserAgent : Self.iosUserAgent)

        do {
            while total == 0 || offset < total {
                try preemptionToken.throwIfPreempted(key: cacheKey, bytesSaved: offset)

                var request = URLRequest(url: streamURL)
                request.timeoutInterval = 30.0
                request.httpShouldHandleCookies = false
                request.setValue("bytes=\(offset)-\(offset + Self.downloadChunkSize - 1)", forHTTPHeaderField: "Range")
                request.setValue(streamUserAgent, forHTTPHeaderField: "User-Agent")
                if isVisionOSStream {
                    request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                    request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
                }

                let (data, response) = try await session.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode == 416 {
                    break
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 403, offset >= Self.downloadChunkSize {
                    break
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 206 || http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 502
                    throw NSError(domain: "YouTubeService", code: code, userInfo: [NSLocalizedDescriptionKey: "Ошибка скачивания аудиопотока YouTube (HTTP \(code))"])
                }

                if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
                   let totalPart = contentRange.split(separator: "/").last,
                   let parsedTotal = Int64(totalPart) {
                    total = parsedTotal
                } else if http.statusCode == 200 {
                    try handle.truncate(atOffset: 0)
                    offset = 0
                    total = Int64(data.count)
                }

                if data.isEmpty { break }
                try handle.seek(toOffset: UInt64(offset))
                try handle.write(contentsOf: data)
                offset += Int64(data.count)
                if total > 0 {
                    let pct = min(98, max(2, Int((Double(offset) / Double(total)) * 100.0)))
                    onProgress?(pct)
                }
            }
            try handle.close()
        } catch {
            try? handle.close()
            if offset == 0 {
                try? fileManager.removeItem(at: partialURL)
            }
            throw error
        }

        guard offset > 1024 else {
            try? fileManager.removeItem(at: partialURL)
            throw NSError(domain: "YouTubeService", code: 502, userInfo: [NSLocalizedDescriptionKey: "Получен пустой аудиопоток YouTube"])
        }
    }

    private func fetchWatchPageSessionContext(videoId: String) async -> (visitorData: String?, cookieHeader: String?) {
        guard let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)&bpctr=9999999999&has_verified=1") else {
            return (nil, nil)
        }
        var req = URLRequest(url: watchURL)
        req.timeoutInterval = 10.0
        req.httpShouldHandleCookies = false
        req.setValue(Self.visionOSUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await session.data(for: req),
              let html = String(data: data, encoding: .utf8) else {
            return (nil, nil)
        }

        var visitorData: String? = nil
        if let regex = try? NSRegularExpression(pattern: #""VISITOR_DATA":"([^"]+)""#),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            visitorData = String(html[range])
        }

        var cookieHeader: String? = nil
        if let http = response as? HTTPURLResponse {
            var pairs: [String] = []
            for (k, v) in http.allHeaderFields {
                if String(describing: k).lowercased() == "set-cookie" {
                    let raw = String(describing: v)
                    for part in raw.components(separatedBy: ",") {
                        if let firstPair = part.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces),
                           firstPair.contains("="),
                           !firstPair.lowercased().hasPrefix("expires="),
                           !firstPair.lowercased().hasPrefix("path="),
                           !firstPair.lowercased().hasPrefix("domain=") {
                            pairs.append(firstPair)
                        }
                    }
                }
            }
            if !pairs.isEmpty {
                cookieHeader = pairs.joined(separator: "; ")
            }
        }
        return (visitorData, cookieHeader)
    }

    public struct AudioStreamCandidate: Sendable {
        public let url: URL
        public let itag: Int
        public let bitrate: Int
        public let isWebMOpus: Bool
        public let isOriginalTrack: Bool
    }

    public func resolveAudioStreamURL(videoId: String) async throws -> URL {
        let candidates = try await resolveAudioStreamCandidates(videoId: videoId)
        guard let first = candidates.first else {
            throw NSError(domain: "YouTubeService", code: 404, userInfo: nil)
        }
        return first.url
    }

    public func resolveAudioStreamCandidates(videoId: String) async throws -> [AudioStreamCandidate] {
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: nil)
        }

        let watchCtx = await fetchWatchPageSessionContext(videoId: videoId)

        let clientProfiles: [(name: String, clientId: String, version: String, userAgent: String, extra: [String: Any])] = [
            (
                name: "VISIONOS",
                clientId: "101",
                version: Self.visionOSClientVersion,
                userAgent: Self.visionOSUserAgent,
                extra: [
                    "deviceMake": "Apple",
                    "deviceModel": "RealityDevice17,1",
                    "osName": "visionOS",
                    "osVersion": "26.5.23O471",
                    "utcOffsetMinutes": 0
                ]
            ),
            (
                name: "IOS",
                clientId: "5",
                version: Self.iosClientVersion,
                userAgent: Self.iosUserAgent,
                extra: [
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "osName": "iPhone",
                    "osVersion": "18.3.2.22D82",
                    "utcOffsetMinutes": 0
                ]
            ),
            (
                name: "ANDROID",
                clientId: "3",
                version: Self.androidClientVersion,
                userAgent: Self.androidUserAgent,
                extra: [
                    "androidSdkVersion": 35,
                    "osName": "Android",
                    "osVersion": "15",
                    "utcOffsetMinutes": 0
                ]
            )
        ]

        var lastError: Error?

        for profile in clientProfiles {
            var clientDict: [String: Any] = [
                "clientName": profile.name,
                "clientVersion": profile.version,
                "hl": "en",
                "gl": "US"
            ]
            for (k, v) in profile.extra {
                clientDict[k] = v
            }
            if let vd = watchCtx.visitorData, !vd.isEmpty {
                clientDict["visitorData"] = vd
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
            request.httpShouldHandleCookies = false
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(profile.clientId, forHTTPHeaderField: "X-Youtube-Client-Name")
            request.setValue(profile.version, forHTTPHeaderField: "X-Youtube-Client-Version")
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
            if let vd = watchCtx.visitorData, !vd.isEmpty {
                request.setValue(vd, forHTTPHeaderField: "X-Goog-Visitor-Id")
            }
            if let cookies = watchCtx.cookieHeader, !cookies.isEmpty {
                request.setValue(cookies, forHTTPHeaderField: "Cookie")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            do {
                let (data, _) = try await session.data(for: request)
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                let ranked = try Self.inspectPlayerResponseCandidates(root)
                if !ranked.isEmpty {
                    return ranked
                }
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

    /// Проверяет JSON-ответ `/youtubei/v1/player` и возвращает лучший аудиопоток по качеству
    public static func inspectPlayerResponseJSON(_ root: [String: Any]) throws -> URL {
        let ranked = try inspectPlayerResponseCandidates(root)
        guard let best = ranked.first else {
            throw NSError(
                domain: "YouTubeService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Прямая аудиодорожка YouTube не найдена."]
            )
        }
        return best.url
    }

    /// Ранжирует доступные прямые аудиопотоки YouTube по максимальному качеству звука:
    /// 1) Оригинальная дорожка (`audioIsDefault != false`, чтобы не брать автодубляж);
    /// 2) `AUDIO_QUALITY_HIGH` (`itag 141` 256 kbps AAC-LC / `itag 774` 256 kbps Opus);
    /// 3) `itag 251` (`Opus 48 kHz ~135–165 kbps` с беспотерьным ремуксом в CoreAudio `.caf`) выше `itag 140` (`AAC 44.1 kHz ~129 kbps`);
    /// 4) Нативный `audio/mp4` (`itag 140`) как гарантированный резервный поток для `AVAudioEngine`.
    public static func inspectPlayerResponseCandidates(_ root: [String: Any]) throws -> [AudioStreamCandidate] {
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

        var scored: [(candidate: AudioStreamCandidate, score: Int)] = []

        for fmt in allFormats {
            guard let urlStr = fmt["url"] as? String,
                  let streamURL = URL(string: urlStr) else {
                continue
            }
            let mime = ((fmt["mimeType"] as? String) ?? "").lowercased()
            let itag = (fmt["itag"] as? Int) ?? 0
            let isAudioOnly = mime.hasPrefix("audio/")
            let isM4A = mime.contains("audio/mp4")
            let isWebMOpus = mime.contains("audio/webm") && mime.contains("opus")
            guard isM4A || isWebMOpus || isAudioOnly else {
                continue
            }

            let avgBitrate = (fmt["averageBitrate"] as? Int)
                ?? (fmt["bitrate"] as? Int)
                ?? (itag == 141 ? 256_000 : (itag == 251 ? 140_000 : (itag == 140 ? 129_000 : 64_000)))
            let qualityLabel = ((fmt["audioQuality"] as? String) ?? "").uppercased()
            let audioTrack = fmt["audioTrack"] as? [String: Any]
            let isOriginal = (audioTrack?["audioIsDefault"] as? Bool) != false

            // Приоритет качества:
            // - Оригинальная дорожка (+10_000_000)
            // - AUDIO_QUALITY_HIGH / itag 141 256 kbps (+2_000_000)
            // - Opus 48 kHz (itag 251 / 774) даёт лучшую перцептивную чёткость и ВЧ до 20 кГц по сравнению с 128 kbps AAC (+35_000 эквивалентного бонуса)
            // - Нативный m4a / Opus выше прочих контейнеров (+500_000)
            var score = avgBitrate
            if isOriginal {
                score += 10_000_000
            }
            if qualityLabel == "AUDIO_QUALITY_HIGH" || itag == 141 || itag == 774 {
                score += 2_000_000
            } else if qualityLabel == "AUDIO_QUALITY_MEDIUM" || itag == 251 || itag == 140 {
                score += 1_000_000
            }
            if isWebMOpus {
                score += 535_000
            } else if isM4A {
                score += 500_000
            }

            scored.append((
                candidate: AudioStreamCandidate(
                    url: streamURL,
                    itag: itag,
                    bitrate: avgBitrate,
                    isWebMOpus: isWebMOpus,
                    isOriginalTrack: isOriginal
                ),
                score: score
            ))
        }

        scored.sort { $0.score > $1.score }
        if !scored.isEmpty {
            return scored.map(\.candidate)
        }

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
            userInfo: [NSLocalizedDescriptionKey: "Прямая аудиодорожка YouTube не найдена."]
        )
    }
}
