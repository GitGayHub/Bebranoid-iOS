import Foundation

/// Управление директориями приложения, локальным аудиокешем, обложками, текстами песен и импортированными файлами.
public final class StorageManager: @unchecked Sendable {
    public static let shared = StorageManager()

    public let rootDirectory: URL
    public let audioCacheDirectory: URL
    public let coversDirectory: URL
    public let customCoversDirectory: URL
    public let lyricsCacheDirectory: URL
    public let importedAudioDirectory: URL
    public let databaseDirectory: URL

    private let fileManager = FileManager.default

    public init(customRootDirectory: URL? = nil) {
        if let customRootDirectory {
            self.rootDirectory = customRootDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.rootDirectory = appSupport.appendingPathComponent("Bebranoid", isDirectory: true)
        }

        self.audioCacheDirectory = rootDirectory.appendingPathComponent("AudioCache", isDirectory: true)
        self.coversDirectory = rootDirectory.appendingPathComponent("Covers", isDirectory: true)
        self.customCoversDirectory = rootDirectory.appendingPathComponent("CustomCovers", isDirectory: true)
        self.lyricsCacheDirectory = rootDirectory.appendingPathComponent("Lyrics", isDirectory: true)
        self.importedAudioDirectory = rootDirectory.appendingPathComponent("ImportedAudio", isDirectory: true)
        self.databaseDirectory = rootDirectory.appendingPathComponent("Database", isDirectory: true)

        ensureDirectoriesExist()
    }

    public func ensureDirectoriesExist() {
        let dirs = [
            rootDirectory,
            audioCacheDirectory,
            coversDirectory,
            customCoversDirectory,
            lyricsCacheDirectory,
            importedAudioDirectory,
            databaseDirectory
        ]
        for dir in dirs {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Безопасное имя файла в кеше (замена недопустимых символов пути)
    public func safeCacheFilename(for rawFilename: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = rawFilename.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "track.m4a" : cleaned
    }

    public func cachedAudioFileURL(for track: Track) -> URL {
        if let local = track.localPath, fileManager.fileExists(atPath: local) {
            return URL(fileURLWithPath: local)
        }
        let safeName = safeCacheFilename(for: track.cacheKey)
        let baseURL = audioCacheDirectory.appendingPathComponent(safeName)
        if track.sourceKind == .youtube {
            let cafURL = baseURL.deletingPathExtension().appendingPathExtension("caf")
            if fileManager.fileExists(atPath: cafURL.path) {
                return cafURL
            }
        }
        return baseURL
    }

    public func partialAudioFileURL(for track: Track) -> URL {
        cachedAudioFileURL(for: track).appendingPathExtension("part")
    }

    public func isTrackCached(_ track: Track) -> Bool {
        if let local = track.localPath, fileManager.fileExists(atPath: local) {
            return true
        }
        let url = cachedAudioFileURL(for: track)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            return size > 1024
        }
        return true
    }

    /// Сохраняет пользовательскую обложку альбома или плейлиста и возвращает локальный путь
    public func saveCustomCover(imageData: Data, identifier: String) throws -> String {
        let safeId = safeCacheFilename(for: identifier)
        let targetURL = customCoversDirectory.appendingPathComponent("\(safeId)_\(Int(Date().timeIntervalSince1970)).jpg")
        try imageData.write(to: targetURL, options: .atomic)
        return targetURL.path
    }

    /// Импортирует локальный аудиофайл из системного файлового пикера (`UIDocumentPickerViewController`)
    public func importLocalAudioFile(from sourceURL: URL) throws -> Track {
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let filename = sourceURL.lastPathComponent
        let safeName = safeCacheFilename(for: filename)
        let destURL = importedAudioDirectory.appendingPathComponent(safeName)

        if fileManager.fileExists(atPath: destURL.path) {
            try? fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)

        let attrs = try? fileManager.attributesOfItem(atPath: destURL.path)
        let fileSize = attrs?[.size] as? Int64

        let baseTitle = (filename as NSString).deletingPathExtension
        let parsed = Self.parseArtistTitleFromFilename(baseTitle)
        let format = AudioFormatInfo.fallbackFromFilename(filename, fileSize: fileSize, duration: 0)

        return Track(
            id: "local_\(safeName)",
            title: parsed.title,
            artist: parsed.artist,
            album: "Локальные файлы",
            duration: 0,
            filename: safeName,
            fileSize: fileSize,
            dateAdded: Date(),
            localPath: destURL.path,
            sourceKind: .local,
            formatInfo: format
        )
    }

    /// Парсинг `Artist - Title` из имени файла (как в `electron/main.js`)
    public static func parseArtistTitleFromFilename(_ stem: String) -> (artist: String, title: String) {
        let cleaned = stem.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = [" — ", " – ", " - "]
        for sep in separators {
            if let range = cleaned.range(of: sep) {
                let artist = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !artist.isEmpty && !title.isEmpty {
                    return (artist, title)
                }
            }
        }
        return ("Неизвестный исполнитель", cleaned.isEmpty ? "Без названия" : cleaned)
    }
}
