import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum ArtworkSourcePriority: Int, Codable, Sendable, Comparable {
    case customCover = 1
    case localDiskCover = 2
    case embeddedAudioArtwork = 3
    case telegramMessageThumbnail = 4
    case albumSiblingCover = 5
    case youtubeCroppedThumbnail = 6
    case proceduralFallback = 7

    public static let customAlbumCover: ArtworkSourcePriority = .customCover

    public static func < (lhs: ArtworkSourcePriority, rhs: ArtworkSourcePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ArtworkSizeTier: String, Sendable {
    case listThumbnail = "thumb_120"
    case albumGrid = "grid_384"
    case fullPlayer = "player_1024"
    case meshAnalysis = "mesh_64"

    public static let grid384: ArtworkSizeTier = .albumGrid
    public static let playerFull: ArtworkSizeTier = .fullPlayer

    public var maxPixelDimension: Int {
        switch self {
        case .listThumbnail: return 120
        case .albumGrid: return 384
        case .fullPlayer: return 1024
        case .meshAnalysis: return 64
        }
    }
}

public struct ResolvedArtworkResult: Sendable {
    public let fileURL: URL?
    public let imageData: Data?
    public let source: ArtworkSourcePriority

    public var localFileURL: URL? { fileURL }

    public init(fileURL: URL?, imageData: Data?, source: ArtworkSourcePriority) {
        self.fileURL = fileURL
        self.imageData = imageData
        self.source = source
    }
}

public extension Notification.Name {
    static let artworkDidResolve = Notification.Name("Bebranoid.artworkDidResolve")
}

/// Централизованный сервис обложек Bebranoid iOS (`electron/main.js` `getCoverPath` + `extractCoverFromAudio` + `downloadCoverFromTelegram` + `youtube.cjs` `transformCover` 1:1).
///
/// Реализует строгую 7-уровневую цепочку приоритетов:
/// 1. Пользовательская обложка (`customAlbumCovers` / `customCoverPath`)
/// 2. Локально сохранённая обложка на диске (`Covers/<track>.jpg` или `Covers/albums/<album>.jpg`)
/// 3. Встроенная обложка внутри аудиофайла (`FLAC METADATA_BLOCK_PICTURE`, `MP3 ID3v2 APIC`, `M4A/ALAC covr`)
/// 4. Миниатюра аудиосообщения Telegram (`coverFileId` через `downloadCoverFromTelegram`)
/// 5. Обложка альбома / соседнего трека того же альбома из каталога
/// 6. Миниатюра YouTube (`maxresdefault.jpg` / `hqdefault.jpg`) с центральной квадратной обрезкой 16:9 / 4:3 letterbox -> 1:1 (`side = min(h, floor(w * 9 / 16))`)
/// 7. Процедурный градиентный плейсхолдер (только если реальной обложки нет ни в одном источнике)
public final class ArtworkService: @unchecked Sendable {
    public static let shared = ArtworkService()

    private let storage: StorageManager
    private let session: URLSession
    private let fileManager = FileManager.default
    private let lock = NSLock()

    private var inFlightTasks: [String: Task<ResolvedArtworkResult?, Never>] = [:]
    private var syncCoverPathCache: [String: (url: URL, priority: ArtworkSourcePriority)?] = [:]
    private var dataCache = NSCache<NSString, NSData>()
    #if canImport(CoreGraphics)
    private var cgImageCache = NSCache<NSString, CGImage>()
    #endif

    private var _loadedArtworkCount: Int = 0
    private var _failedArtworkCount: Int = 0
    private var _cacheHitCount: Int = 0

    public var albumsCoversDirectory: URL {
        let dir = storage.coversDirectory.appendingPathComponent("albums", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public init(storage: StorageManager = .shared, session: URLSession = .shared) {
        self.storage = storage
        self.session = session
        self.dataCache.countLimit = 300
        self.dataCache.totalCostLimit = 64 * 1024 * 1024
        _ = self.albumsCoversDirectory
    }

    public var loadedArtworkCount: Int {
        withLock { _loadedArtworkCount }
    }

    public var failedArtworkCount: Int {
        withLock { _failedArtworkCount }
    }

    public var cacheHitCount: Int {
        withLock { _cacheHitCount }
    }

    // MARK: - Synchronous Disk Lookup (Priorities 1, 2, 3, 5)

    /// Синхронно разрешает локальный путь обложки для трека по цепочке приоритетов 1 -> 2 -> 3 -> 5 (без сетевых запросов)
    public func resolveLocalCoverURLSync(
        for track: Track,
        customAlbumCovers: [String: String] = [:],
        siblingTracks: [Track] = []
    ) -> (url: URL, priority: ArtworkSourcePriority)? {
        // Priority 1: Custom album cover
        if let customPath = customAlbumCovers[track.album],
           !customPath.isEmpty,
           isValidImageFile(atPath: customPath) {
            return (URL(fileURLWithPath: customPath), .customCover)
        }

        if customAlbumCovers.isEmpty, siblingTracks.isEmpty,
           let cachedEntry = withLock({ syncCoverPathCache[track.id] }) {
            return cachedEntry
        }

        let resolved: (url: URL, priority: ArtworkSourcePriority)? = {
            // Priority 2a: Direct coverPath on Track
            if let direct = track.coverPath,
               !direct.isEmpty,
               isValidImageFile(atPath: direct) {
                let isCustom = direct.contains("CustomCovers")
                return (URL(fileURLWithPath: direct), isCustom ? .customCover : .localDiskCover)
            }

            // Priority 2b: Covers/<safeCacheKey>.jpg or Covers/<stem>.jpg
            let safeKey = storage.safeCacheFilename(for: track.cacheKey)
            let safeStem = (safeKey as NSString).deletingPathExtension
            let candidateTrackPaths = [
                storage.coversDirectory.appendingPathComponent("\(safeKey).jpg"),
                storage.coversDirectory.appendingPathComponent("\(safeStem).jpg"),
                storage.coversDirectory.appendingPathComponent("\(safeStem).png")
            ]
            for candidate in candidateTrackPaths where isValidImageFile(atPath: candidate.path) {
                return (candidate, .localDiskCover)
            }

            // Priority 3: Embedded cover inside local/cached audio file
            let audioURL = storage.cachedAudioFileURL(for: track)
            if fileManager.fileExists(atPath: audioURL.path),
               let embeddedData = AudioMetadataReader.extractEmbeddedArtworkSync(from: audioURL),
               embeddedData.count > 64 {
                let savedURL = saveTrackAndAlbumCoverToDisk(
                    imageData: embeddedData,
                    trackFilename: track.cacheKey,
                    albumName: track.album
                )
                if let savedURL {
                    recordArtworkLoaded()
                    return (savedURL, .embeddedAudioArtwork)
                }
            }

            let hasIndividualRemoteCover = (track.sourceKind == .youtube)
                || !(track.youtubeVideoId ?? "").isEmpty
                || !(track.remoteArtworkURL ?? "").isEmpty
                || !(track.coverFileId ?? "").isEmpty

            // Priority 2c: Covers/albums/<safeAlbumName>.jpg (только если у трека нет собственной обложки YouTube / Telegram)
            if !hasIndividualRemoteCover, isNamedAlbum(track.album) {
                let safeAlbum = storage.safeCacheFilename(for: track.album)
                let albumCoverURL = albumsCoversDirectory.appendingPathComponent("\(safeAlbum).jpg")
                if isValidImageFile(atPath: albumCoverURL.path) {
                    return (albumCoverURL, .localDiskCover)
                }
            }

            // Priority 5: Sibling track in the same named album (только для альбомов без индивидуальной удалённой обложки)
            if !hasIndividualRemoteCover, isNamedAlbum(track.album) {
                if let sibling = siblingTracks.first(where: {
                    $0.album == track.album && $0.id != track.id && ($0.coverPath != nil)
                }), let sibPath = sibling.coverPath, isValidImageFile(atPath: sibPath) {
                    return (URL(fileURLWithPath: sibPath), .albumSiblingCover)
                }
            }

            return nil
        }()

        if customAlbumCovers.isEmpty, siblingTracks.isEmpty {
            withLock {
                if syncCoverPathCache.count > 4000 {
                    syncCoverPathCache.removeAll(keepingCapacity: true)
                }
                syncCoverPathCache[track.id] = resolved
            }
        }

        return resolved
    }

    // MARK: - Full Async 7-Level Resolution (Including Telegram Thumbnail & YouTube 1:1 Crop)

    /// Полное асинхронное разрешение обложки трека по всем 7 уровням приоритета с дедупликацией in-flight запросов
    public func resolveArtwork(
        for track: Track,
        customAlbumCovers: [String: String] = [:],
        siblingTracks: [Track] = []
    ) async -> ResolvedArtworkResult? {
        if let syncHit = resolveLocalCoverURLSync(
            for: track,
            customAlbumCovers: customAlbumCovers,
            siblingTracks: siblingTracks
        ) {
            let data = loadCachedData(from: syncHit.url)
            return ResolvedArtworkResult(fileURL: syncHit.url, imageData: data, source: syncHit.priority)
        }

        let dedupKey = "track_\(track.id)"
        if let existingTask = withLock({ inFlightTasks[dedupKey] }) {
            return await existingTask.value
        }

        let task = Task<ResolvedArtworkResult?, Never> { [weak self] in
            guard let self else { return nil }
            defer {
                _ = self.withLock { self.inFlightTasks.removeValue(forKey: dedupKey) }
            }

            // Priority 4: Telegram coverFileId / message thumbnail via TDLib
            if track.sourceKind == .telegram || !(track.coverFileId ?? "").isEmpty {
                if let downloadedPath = await TelegramClientService.shared.downloadCoverForTrack(track),
                   self.isValidImageFile(atPath: downloadedPath) {
                    let url = URL(fileURLWithPath: downloadedPath)
                    let data = self.loadCachedData(from: url)
                    if let data, self.isNamedAlbum(track.album) {
                        self.saveAlbumCoverIfMissing(imageData: data, albumName: track.album)
                    }
                    self.recordArtworkLoaded()
                    self.notifyArtworkResolved(trackId: track.id, albumName: track.album, fileURL: url)
                    return ResolvedArtworkResult(fileURL: url, imageData: data, source: .telegramMessageThumbnail)
                }
            }

            // Priority 6: YouTube thumbnail (maxresdefault -> hqdefault -> remoteArtworkURL) with 16:9 / 4:3 -> 1:1 center crop
            if track.sourceKind == .youtube || !(track.youtubeVideoId ?? "").isEmpty || !(track.remoteArtworkURL ?? "").isEmpty {
                if let ytResult = await self.downloadAndCropRemoteArtwork(for: track) {
                    self.recordArtworkLoaded()
                    self.notifyArtworkResolved(trackId: track.id, albumName: track.album, fileURL: ytResult.fileURL)
                    return ytResult
                }
            }

            // Priority 5 (fallback): Обложка альбома, если у не-YouTube трека не удалось получить собственную обложку
            if track.sourceKind != .youtube, self.isNamedAlbum(track.album) {
                let safeAlbum = self.storage.safeCacheFilename(for: track.album)
                let albumCoverURL = self.albumsCoversDirectory.appendingPathComponent("\(safeAlbum).jpg")
                if self.isValidImageFile(atPath: albumCoverURL.path) {
                    let data = self.loadCachedData(from: albumCoverURL)
                    return ResolvedArtworkResult(fileURL: albumCoverURL, imageData: data, source: .albumSiblingCover)
                }
            }

            return nil
        }

        withLock { inFlightTasks[dedupKey] = task }
        return await task.value
    }

    /// Скачивает миниатюру YouTube (с фолбэком `maxresdefault.jpg` -> `hqdefault.jpg`) или произвольный `remoteArtworkURL`,
    /// обрезает 16:9 / 4:3 letterbox в квадрат 1:1 (`cropYouTubeThumbnailToSquare`) и сохраняет в `Covers/`.
    public func downloadAndCropRemoteArtwork(for track: Track) async -> ResolvedArtworkResult? {
        var candidateURLs: [URL] = []
        if let vid = track.youtubeVideoId, !vid.isEmpty {
            if let maxRes = URL(string: "https://i.ytimg.com/vi/\(vid)/maxresdefault.jpg") {
                candidateURLs.append(maxRes)
            }
            if let hq = URL(string: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg") {
                candidateURLs.append(hq)
            }
        }
        if let remoteStr = track.remoteArtworkURL, let remoteURL = URL(string: remoteStr) {
            if !candidateURLs.contains(remoteURL) {
                candidateURLs.append(remoteURL)
            }
        }

        for url in candidateURLs {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0
            guard let (rawData, resp) = try? await session.data(for: request),
                  let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  rawData.count > 256 else {
                continue
            }

            let isYouTubeHost = (url.host?.contains("ytimg.com") == true) || track.sourceKind == .youtube
            let finalData: Data = {
                if isYouTubeHost, let cropped = Self.cropYouTubeThumbnailToSquare(rawData) {
                    return cropped
                }
                return rawData
            }()

            if let savedURL = saveTrackAndAlbumCoverToDisk(
                imageData: finalData,
                trackFilename: track.cacheKey,
                albumName: track.album
            ) {
                return ResolvedArtworkResult(fileURL: savedURL, imageData: finalData, source: .youtubeCroppedThumbnail)
            }
        }

        recordArtworkFailure()
        return nil
    }

    // MARK: - YouTube 16:9 / 4:3 Letterbox -> 1:1 Center-Square Crop (`electron/main.js` line 1866)

    public func cropYouTubeThumbnailToSquare(imageData: Data) -> Data? {
        Self.cropYouTubeThumbnailToSquare(imageData)
    }

    /// Обрезает 16:9 (`1280×720`) или 4:3 с чёрными полосами (`480×360` `hqdefault.jpg`) миниатюру YouTube
    /// до центральной квадратной области `1:1` по формуле `side = min(height, floor(width * 9 / 16))` из `electron/main.js`.
    public static func cropYouTubeThumbnailToSquare(_ imageData: Data) -> Data? {
        #if canImport(CoreGraphics)
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        if width == height {
            return imageData
        }

        let side = max(1, min(height, Int(floor(Double(width) * 9.0 / 16.0))))
        let cropX = max(0, (width - side) / 2)
        let cropY = max(0, (height - side) / 2)
        let cropRect = CGRect(x: cropX, y: cropY, width: side, height: side)

        guard let croppedCG = cgImage.cropping(to: cropRect) else {
            return imageData
        }
        return encodeCGImageAsJPEG(croppedCG, quality: 0.92) ?? imageData
        #else
        return imageData
        #endif
    }

    #if canImport(CoreGraphics)
    /// Декодирует и масштабирует изображение под нужный уровень размера (`listThumbnail`, `albumGrid`, `fullPlayer`, `meshAnalysis`)
    public func loadCGImage(from fileURL: URL, tier: ArtworkSizeTier = .albumGrid) -> CGImage? {
        let cacheKey = "\(fileURL.path)|\(tier.rawValue)" as NSString
        if let cached = cgImageCache.object(forKey: cacheKey) {
            withLock { _cacheHitCount += 1 }
            return cached
        }

        guard fileManager.fileExists(atPath: fileURL.path),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: tier.maxPixelDimension
        ]

        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        cgImageCache.setObject(thumb, forKey: cacheKey)
        recordArtworkLoaded()
        return thumb
    }

    public static func encodeCGImageAsJPEG(_ cgImage: CGImage, quality: Double = 0.92) -> Data? {
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
        #else
        let mutableData = CFDataCreateMutable(nil, 0)!
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
        #endif
    }
    #endif

    // MARK: - Helpers & Disk Persistence

    @discardableResult
    public func saveTrackAndAlbumCoverToDisk(
        imageData: Data,
        trackFilename: String,
        albumName: String? = nil
    ) -> URL? {
        guard imageData.count > 64 else { return nil }
        let safeKey = storage.safeCacheFilename(for: trackFilename)
        let targetURL = storage.coversDirectory.appendingPathComponent("\(safeKey).jpg")
        do {
            try imageData.write(to: targetURL, options: .atomic)
            dataCache.setObject(imageData as NSData, forKey: targetURL.path as NSString, cost: imageData.count)
            withLock { syncCoverPathCache.removeAll(keepingCapacity: true) }
            if let albumName, isNamedAlbum(albumName), !safeKey.lowercased().hasPrefix("youtube-") {
                saveAlbumCoverIfMissing(imageData: imageData, albumName: albumName)
            }
            return targetURL
        } catch {
            recordArtworkFailure()
            return nil
        }
    }

    public func saveAlbumCoverIfMissing(imageData: Data, albumName: String) {
        guard isNamedAlbum(albumName), imageData.count > 64 else { return }
        let safeAlbum = storage.safeCacheFilename(for: albumName)
        let albumURL = albumsCoversDirectory.appendingPathComponent("\(safeAlbum).jpg")
        if !isValidImageFile(atPath: albumURL.path) {
            try? imageData.write(to: albumURL, options: .atomic)
            withLock { syncCoverPathCache.removeAll(keepingCapacity: true) }
        }
    }

    public func loadCachedData(from url: URL) -> Data? {
        let key = url.path as NSString
        if let cached = dataCache.object(forKey: key) {
            withLock { _cacheHitCount += 1 }
            return cached as Data
        }
        guard let data = try? Data(contentsOf: url), data.count > 64 else { return nil }
        dataCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    public func isValidImageFile(atPath path: String) -> Bool {
        guard !path.isEmpty, fileManager.fileExists(atPath: path) else { return false }
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            return size > 64
        }
        return true
    }

    public func isNamedAlbum(_ album: String) -> Bool {
        let trimmed = album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !trimmed.isEmpty &&
               trimmed != "без альбома" &&
               trimmed != "unknown album" &&
               trimmed != "unknown" &&
               trimmed != "<unknown>"
    }

    public func recordArtworkLoaded() {
        withLock { _loadedArtworkCount += 1 }
    }

    public func recordArtworkFailure() {
        withLock { _failedArtworkCount += 1 }
    }

    private func notifyArtworkResolved(trackId: String, albumName: String, fileURL: URL?) {
        withLock { syncCoverPathCache.removeValue(forKey: trackId) }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .artworkDidResolve,
                object: nil,
                userInfo: [
                    "trackId": trackId,
                    "album": albumName,
                    "albumName": albumName,
                    "path": fileURL?.path ?? ""
                ]
            )
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
