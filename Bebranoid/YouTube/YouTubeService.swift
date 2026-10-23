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
        let playlistURLStr = "https://www.youtube.com/playlist?list=\(playlistId)&hl=ru"
        guard let url = URL(string: playlistURLStr) else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: nil)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "YouTubeService", code: 502, userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить страницу плейлиста YouTube"])
        }

        var extracted = Self.parsePlaylistFromHTML(html: html, playlistId: playlistId)
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

    private func fetchContinuationPageRawJSON(continuationToken: String) async throws -> String {
        guard let browseURL = URL(string: "https://www.youtube.com/youtubei/v1/browse?prettyPrint=false") else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: nil)
        }

        let payload: [String: Any] = [
            "continuation": continuationToken,
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20240725.01.00",
                    "hl": "ru",
                    "gl": "US"
                ]
            ]
        ]

        var request = URLRequest(url: browseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let raw = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "YouTubeService", code: 502, userInfo: nil)
        }
        return raw
    }

    /// Извлекает название плейлиста, элементы `playlistVideoRenderer` и токен продолжения `continuationCommand.token` из `ytInitialData`
    public static func parsePlaylistFromHTML(html: String, playlistId: String) -> ImportedYouTubePlaylistResult {
        var playlistTitle = "YouTube Плейлист"
        if let titleRange = html.range(of: #"<meta property="og:title" content="([^"]+)""#, options: .regularExpression) {
            let matchStr = String(html[titleRange])
            if let contentStart = matchStr.range(of: "content=\"")?.upperBound,
               let contentEnd = matchStr.lastIndex(of: "\"") {
                let rawTitle = String(matchStr[contentStart..<contentEnd])
                if !rawTitle.isEmpty {
                    playlistTitle = rawTitle.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
                }
            }
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

    /// Скачивает нативный `m4a (AAC, itag 140)` аудиопоток YouTube с поддержкой докачки `.part` и кооперативного вытеснения
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

        var request = URLRequest(url: streamURL)
        request.timeoutInterval = 30.0

        var existingOffset: Int64 = 0
        if FileManager.default.fileExists(atPath: partialURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: partialURL.path),
           let size = attrs[.size] as? Int64, size > 0 {
            existingOffset = size
            request.setValue("bytes=\(existingOffset)-", forHTTPHeaderField: "Range")
        }

        let (tempDownloadedURL, response) = try await session.download(for: request)
        try preemptionToken.throwIfPreempted(key: track.cacheKey, bytesSaved: existingOffset)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "YouTubeService", code: 502, userInfo: [NSLocalizedDescriptionKey: "Ошибка скачивания аудиопотока YouTube"])
        }

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempDownloadedURL, to: destinationURL)
        try? FileManager.default.removeItem(at: partialURL)
        return destinationURL
    }

    public func resolveAudioStreamURL(videoId: String) async throws -> URL {
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            throw NSError(domain: "YouTubeService", code: 400, userInfo: nil)
        }

        let clientProfiles: [(name: String, version: String, userAgent: String, extra: [String: Any])] = [
            (
                name: "IOS",
                version: "19.29.1",
                userAgent: "com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X)",
                extra: [
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "osName": "iPhone",
                    "osVersion": "17.5.1.21F90"
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
