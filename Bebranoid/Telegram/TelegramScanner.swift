import Foundation

public struct AndroSendCaptionMetadata: Equatable, Sendable {
    public var path: String?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var durationMs: Int?
    public var year: Int?

    public init(
        path: String? = nil,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        durationMs: Int? = nil,
        year: Int? = nil
    ) {
        self.path = path
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.year = year
    }
}

public struct RawTelegramAudioMessage: Sendable {
    public var chatId: String
    public var chatTitle: String
    public var messageId: Int
    public var messageThreadId: Int?
    public var topicTitle: String?
    public var caption: String?
    public var performer: String?
    public var audioTitle: String?
    public var filename: String
    public var mimeType: String?
    public var fileSize: Int64?
    public var durationSeconds: Double
    public var fileUniqueId: String?
    public var coverFileId: String?
    public var date: Date

    public init(
        chatId: String,
        chatTitle: String,
        messageId: Int,
        messageThreadId: Int? = nil,
        topicTitle: String? = nil,
        caption: String? = nil,
        performer: String? = nil,
        audioTitle: String? = nil,
        filename: String,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        durationSeconds: Double = 0,
        fileUniqueId: String? = nil,
        coverFileId: String? = nil,
        date: Date = Date()
    ) {
        self.chatId = chatId
        self.chatTitle = chatTitle
        self.messageId = messageId
        self.messageThreadId = messageThreadId
        self.topicTitle = topicTitle
        self.caption = caption
        self.performer = performer
        self.audioTitle = audioTitle
        self.filename = filename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.durationSeconds = durationSeconds
        self.fileUniqueId = fileUniqueId
        self.coverFileId = coverFileId
        self.date = date
    }
}

/// Точный 1:1 порт парсера метаданных `key=value` из подписи, разрешения альбомов из топиков форума и 3-уровневой дедупликации архива (`electron/main.js`).
public enum TelegramScanner {
    /// Парсит пары `key=value` из подписи аудиосообщения (`parseMetaFromCaption` в `electron/main.js`):
    /// Поддерживает ключи `path=`, `title=`, `artist=`, `album=`, `durationMs=`, `year=`
    public static func parseMetaFromCaption(_ caption: String?) -> AndroSendCaptionMetadata {
        guard let raw = caption, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AndroSendCaptionMetadata()
        }

        var meta = AndroSendCaptionMetadata()
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eqRange = trimmed.range(of: "=") else { continue }
            let key = String(trimmed[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let val = String(trimmed[eqRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !val.isEmpty else { continue }

            switch key {
            case "path":
                meta.path = val
            case "title":
                meta.title = val
            case "artist":
                meta.artist = val
            case "album":
                meta.album = val
            case "durationms", "duration_ms":
                meta.durationMs = Int(val)
            case "year", "date":
                if let y = Int(val.prefix(4)) {
                    meta.year = y
                }
            default:
                break
            }
        }
        return meta
    }

    /// Извлекает название родительской папки из пути `path` (`extractFolderFromPath` в `electron/main.js`)
    public static func extractParentFolderFromPath(_ path: String?) -> String? {
        guard let raw = path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.components(separatedBy: "/").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let parent = parts[parts.count - 2].trimmingCharacters(in: .whitespacesAndNewlines)
        let ignoredFolders: Set<String> = ["music", "audio", "downloads", "download", "tracks", "files", "storage", "emulated", "0"]
        if parent.isEmpty || ignoredFolders.contains(parent.lowercased()) {
            return nil
        }
        return parent
    }

    /// Проверяет, совпадает ли название топика форума с именем одного конкретного трека (`isSingleTrackTopic` в `electron/main.js`).
    /// Предотвращает превращение топиков одиночных песен в альбомы из 1 трека.
    public static func isSingleTrackTopic(topicTitle: String, trackTitle: String, artist: String, filename: String) -> Bool {
        func clean(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: #"\.[a-z0-9]{2,5}$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let normTopic = clean(topicTitle)
        guard !normTopic.isEmpty else { return false }

        let normTitle = clean(trackTitle)
        let normFile = clean(filename)
        let normArtistTitle = clean("\(artist) \(trackTitle)")

        if normTopic == normTitle || normTopic == normFile || normTopic == normArtistTitle {
            return true
        }

        // Проверяем пересечение слов >= 75%
        let topicWords = Set(normTopic.components(separatedBy: " ").filter { $0.count >= 2 })
        guard !topicWords.isEmpty else { return false }

        let targetWords = Set((normArtistTitle + " " + normFile).components(separatedBy: " ").filter { $0.count >= 2 })
        let intersectionCount = topicWords.intersection(targetWords).count
        let ratio = Double(intersectionCount) / Double(topicWords.count)
        return ratio >= 0.75
    }

    /// Разрешает итоговое имя альбома по иерархии приоритетов (`resolveAlbumName` в `electron/main.js`):
    /// 1. `captionMeta.album`
    /// 2. Название топика форума (`topicTitle`), если это не `General` и не `isSingleTrackTopic`
    /// 3. Родительская папка из `captionMeta.path`
    /// 4. Название чата (если оно не совпадает с названием корневого облачного/архивного чата) или `"Без альбома"`
    public static func resolveAlbumName(
        captionMeta: AndroSendCaptionMetadata,
        topicTitle: String?,
        trackTitle: String,
        artist: String,
        filename: String,
        chatTitle: String,
        ignoredChatTitles: Set<String> = []
    ) -> String {
        if let capAlbum = captionMeta.album?.trimmingCharacters(in: .whitespacesAndNewlines),
           !capAlbum.isEmpty,
           capAlbum.lowercased() != "unknown",
           capAlbum.lowercased() != "<unknown>" {
            return capAlbum
        }

        if let topic = topicTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !topic.isEmpty,
           topic.lowercased() != "general",
           !isSingleTrackTopic(topicTitle: topic, trackTitle: trackTitle, artist: artist, filename: filename) {
            return topic
        }

        if let folder = extractParentFolderFromPath(captionMeta.path) {
            return folder
        }

        let trimmedChat = chatTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedChat.isEmpty && !ignoredChatTitles.contains(trimmedChat) {
            return trimmedChat
        }

        return "Без альбома"
    }

    /// Преобразует `RawTelegramAudioMessage` в доменную модель `Track`
    public static func buildTrack(
        from msg: RawTelegramAudioMessage,
        isFromArchive: Bool = false,
        ignoredChatTitles: Set<String> = []
    ) -> Track {
        let cap = parseMetaFromCaption(msg.caption)
        let stem = (msg.filename as NSString).deletingPathExtension
        let fallbackParsed = StorageManager.parseArtistTitleFromFilename(stem)

        let resolvedTitle = (cap.title ?? msg.audioTitle ?? fallbackParsed.title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedArtist = (cap.artist ?? msg.performer ?? fallbackParsed.artist)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedDuration: Double = {
            if msg.durationSeconds > 0 { return msg.durationSeconds }
            if let ms = cap.durationMs, ms > 0 { return Double(ms) / 1000.0 }
            return 0
        }()

        let resolvedAlbum = resolveAlbumName(
            captionMeta: cap,
            topicTitle: msg.topicTitle,
            trackTitle: resolvedTitle,
            artist: resolvedArtist,
            filename: msg.filename,
            chatTitle: msg.chatTitle,
            ignoredChatTitles: ignoredChatTitles
        )

        let format = AudioFormatInfo.fallbackFromFilename(
            msg.filename,
            fileSize: msg.fileSize,
            duration: resolvedDuration
        )

        var track = Track.makeTelegramTrack(
            chatId: msg.chatId,
            messageId: msg.messageId,
            messageThreadId: msg.messageThreadId,
            fileUniqueId: msg.fileUniqueId,
            title: resolvedTitle,
            artist: resolvedArtist,
            album: resolvedAlbum,
            year: cap.year,
            duration: resolvedDuration,
            filename: msg.filename,
            mimeType: msg.mimeType,
            fileSize: msg.fileSize,
            dateAdded: msg.date,
            coverFileId: msg.coverFileId,
            isFromArchive: isFromArchive
        )
        track.formatInfo = format
        return track
    }

    /// Нормализованный ключ `artist + title` для дедупликации архивного чата
    public static func normalizedArtistTitleKey(artist: String, title: String) -> String {
        let combined = "\(artist.lowercased())|\(title.lowercased())"
        return combined
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Объединяет треки основного чата и архивного чата с 3-уровневой дедупликацией (`electron/main.js` `scanAllAudio`):
    /// Трек из архива пропускается, если в основном чате уже есть трек с тем же:
    /// 1) `fileUniqueId`
    /// 2) `filename.lowercased()`
    /// 3) `normalizedArtistTitleKey(artist, title)`
    public static func mergeMainAndArchiveTracks(
        mainTracks: [Track],
        archiveTracks: [Track]
    ) -> [Track] {
        var seenUniqueIds = Set<String>()
        var seenFilenames = Set<String>()
        var seenArtistTitles = Set<String>()

        for t in mainTracks {
            if let uid = t.fileUniqueId, !uid.isEmpty {
                seenUniqueIds.insert(uid)
            }
            if !t.filename.isEmpty {
                seenFilenames.insert(t.filename.lowercased())
            }
            seenArtistTitles.insert(normalizedArtistTitleKey(artist: t.artist, title: t.title))
        }

        var merged = mainTracks
        for var archTrack in archiveTracks {
            archTrack.isFromArchive = true
            if let uid = archTrack.fileUniqueId, !uid.isEmpty, seenUniqueIds.contains(uid) {
                continue
            }
            if !archTrack.filename.isEmpty, seenFilenames.contains(archTrack.filename.lowercased()) {
                continue
            }
            let artTitleKey = normalizedArtistTitleKey(artist: archTrack.artist, title: archTrack.title)
            if seenArtistTitles.contains(artTitleKey) {
                continue
            }

            if let uid = archTrack.fileUniqueId, !uid.isEmpty {
                seenUniqueIds.insert(uid)
            }
            if !archTrack.filename.isEmpty {
                seenFilenames.insert(archTrack.filename.lowercased())
            }
            seenArtistTitles.insert(artTitleKey)
            merged.append(archTrack)
        }

        return merged
    }
}
