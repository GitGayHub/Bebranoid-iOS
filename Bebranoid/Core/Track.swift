import Foundation

public enum TrackSourceKind: String, Codable, Sendable, CaseIterable {
    case telegram
    case youtube
    case local
}

public struct Track: Identifiable, Codable, Hashable, Sendable {
    /// Составной ID:
    /// - Telegram: `${chatId}:${messageId}`
    /// - YouTube: `youtube:${videoId}`
    /// - Local: `local_${relativePath}`
    public var id: String
    public var messageId: Int?
    public var chatId: String?
    public var messageThreadId: Int?
    public var fileId: String?
    public var fileUniqueId: String?
    public var fileType: String?
    public var title: String
    public var artist: String
    public var album: String
    public var year: Int?
    public var duration: Double
    public var filename: String
    public var mimeType: String?
    public var fileSize: Int64?
    public var dateAdded: Date
    public var localPath: String?
    public var coverPath: String?
    public var coverFileId: String?
    public var remoteArtworkURL: String?
    public var sourceKind: TrackSourceKind
    public var youtubeVideoId: String?
    public var youtubeUrl: String?
    public var isFromArchive: Bool
    public var formatInfo: AudioFormatInfo?

    public init(
        id: String,
        messageId: Int? = nil,
        chatId: String? = nil,
        messageThreadId: Int? = nil,
        fileId: String? = nil,
        fileUniqueId: String? = nil,
        fileType: String? = nil,
        title: String,
        artist: String,
        album: String,
        year: Int? = nil,
        duration: Double = 0,
        filename: String,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        dateAdded: Date = Date(),
        localPath: String? = nil,
        coverPath: String? = nil,
        coverFileId: String? = nil,
        remoteArtworkURL: String? = nil,
        sourceKind: TrackSourceKind = .telegram,
        youtubeVideoId: String? = nil,
        youtubeUrl: String? = nil,
        isFromArchive: Bool = false,
        formatInfo: AudioFormatInfo? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.chatId = chatId
        self.messageThreadId = messageThreadId
        self.fileId = fileId
        self.fileUniqueId = fileUniqueId
        self.fileType = fileType
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Без названия" : title
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Неизвестный исполнитель" : artist
        self.album = album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Без альбома" : album
        self.year = year
        self.duration = max(0, duration)
        self.filename = filename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.dateAdded = dateAdded
        self.localPath = localPath
        self.coverPath = coverPath
        self.coverFileId = coverFileId
        self.remoteArtworkURL = remoteArtworkURL
        self.sourceKind = sourceKind
        self.youtubeVideoId = youtubeVideoId
        self.youtubeUrl = youtubeUrl
        self.isFromArchive = isFromArchive
        self.formatInfo = formatInfo
    }

    /// Логический ключ кеша, совместимый с Windows-версией (`track.filename`)
    public var cacheKey: String {
        if sourceKind == .youtube, let vid = youtubeVideoId, !vid.isEmpty {
            return "youtube-\(vid).m4a"
        }
        return filename
    }

    /// Запрещено ли удаление трека из облака (архивный чат read-only)
    public var isCloudDeletionBlocked: Bool {
        isFromArchive || AppConfig.isArchiveChatId(chatId)
    }

    /// Фабрика для создания трека из сообщения Telegram
    public static func makeTelegramTrack(
        chatId: String,
        messageId: Int,
        messageThreadId: Int? = nil,
        fileUniqueId: String? = nil,
        title: String,
        artist: String,
        album: String,
        year: Int? = nil,
        duration: Double,
        filename: String,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        dateAdded: Date = Date(),
        coverPath: String? = nil,
        coverFileId: String? = nil,
        isFromArchive: Bool = false,
        configuredArchiveChatId: String? = nil
    ) -> Track {
        let compositeId = "\(chatId):\(messageId)"
        let archive = isFromArchive || AppConfig.isArchiveChatId(chatId, configuredArchiveChatId: configuredArchiveChatId)
        return Track(
            id: compositeId,
            messageId: messageId,
            chatId: chatId,
            messageThreadId: messageThreadId,
            fileUniqueId: fileUniqueId,
            title: title,
            artist: artist,
            album: album,
            year: year,
            duration: duration,
            filename: filename,
            mimeType: mimeType,
            fileSize: fileSize,
            dateAdded: dateAdded,
            coverPath: coverPath,
            coverFileId: coverFileId,
            sourceKind: .telegram,
            isFromArchive: archive
        )
    }

    /// Фабрика для создания YouTube-трека
    public static func makeYouTubeTrack(
        videoId: String,
        title: String,
        artist: String,
        album: String = "YouTube",
        duration: Double = 0,
        thumbnailURL: String? = nil
    ) -> Track {
        let cleanVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        return Track(
            id: "youtube:\(cleanVideoId)",
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            filename: "youtube-\(cleanVideoId).m4a",
            mimeType: "audio/mp4",
            dateAdded: Date(),
            remoteArtworkURL: thumbnailURL,
            sourceKind: .youtube,
            youtubeVideoId: cleanVideoId,
            youtubeUrl: "https://www.youtube.com/watch?v=\(cleanVideoId)"
        )
    }
}
