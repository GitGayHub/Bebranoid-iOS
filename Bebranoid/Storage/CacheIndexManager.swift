import Foundation

/// Элемент отчёта «Сверка» кеша по альбомам (`src/views/Tracks.jsx`)
public struct AlbumCacheReconcileItem: Identifiable, Hashable, Sendable {
    public var id: String { albumName }
    public var albumName: String
    public var totalTracks: Int
    public var cachedTracks: Int
    public var missingTracks: [Track]

    public var completionPercentage: Int {
        guard totalTracks > 0 else { return 100 }
        return Int(round((Double(cachedTracks) / Double(totalTracks)) * 100.0))
    }

    public var isFullyCached: Bool {
        cachedTracks >= totalTracks && totalTracks > 0
    }
}

/// Быстрый индекс закешированных аудиофайлов и расчёт статистики хранилища
public final class CacheIndexManager: @unchecked Sendable {
    public static let shared = CacheIndexManager()

    private let storage: StorageManager
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var cachedKeys: Set<String> = []

    public init(storage: StorageManager = .shared) {
        self.storage = storage
        rebuildIndex()
    }

    /// Сканирует директорию `AudioCache` и синхронизирует быстрый in-memory индекс
    public func rebuildIndex() {
        lock.lock()
        defer { lock.unlock() }

        cachedKeys.removeAll()
        guard let urls = try? fileManager.contentsOfDirectory(
            at: storage.audioCacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls {
            if url.pathExtension.lowercased() == "part" { continue }
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize, size > 1024 {
                cachedKeys.insert(url.lastPathComponent)
            }
        }
    }

    public func markCached(for track: Track) {
        let safeKey = storage.safeCacheFilename(for: track.cacheKey)
        lock.lock()
        cachedKeys.insert(safeKey)
        cachedKeys.insert(track.cacheKey)
        lock.unlock()
    }

    public func registerCachedFile(for track: Track, fileURL: URL) {
        markCached(for: track)
    }

    public func isCached(_ track: Track) -> Bool {
        if track.sourceKind == .local, let path = track.localPath, fileManager.fileExists(atPath: path) {
            return true
        }
        let safeKey = storage.safeCacheFilename(for: track.cacheKey)
        lock.lock()
        let inSet = cachedKeys.contains(safeKey) || cachedKeys.contains(track.cacheKey)
        lock.unlock()
        if inSet { return true }
        let exists = storage.isTrackCached(track)
        if exists {
            markCached(for: track)
        }
        return exists
    }

    /// Вычисляет общий размер аудиокеша в байтах и количество файлов
    public func calculateCacheStats() -> (totalBytes: Int64, fileCount: Int) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: storage.audioCacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var bytes: Int64 = 0
        var count = 0
        for url in urls where url.pathExtension.lowercased() != "part" {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                bytes += Int64(size)
                count += 1
            }
        }
        return (bytes, count)
    }

    /// Полная очистка скачанного аудиокеша (с сохранением локально импортированных файлов и метаданных)
    public func clearAudioCache() {
        if let urls = try? fileManager.contentsOfDirectory(at: storage.audioCacheDirectory, includingPropertiesForKeys: nil) {
            for url in urls {
                try? fileManager.removeItem(at: url)
            }
        }
        lock.lock()
        cachedKeys.removeAll()
        lock.unlock()
    }

    /// Формирует отчёт «Сверка» кеша по всем альбомам медиатеки (`src/views/Tracks.jsx`)
    public func buildReconcileReport(tracks: [Track]) -> [AlbumCacheReconcileItem] {
        var grouped: [String: [Track]] = [:]
        for track in tracks {
            let albumName = track.album.isEmpty ? "Без альбома" : track.album
            grouped[albumName, default: []].append(track)
        }

        var items: [AlbumCacheReconcileItem] = []
        for (albumName, albumTracks) in grouped {
            var cachedCount = 0
            var missing: [Track] = []
            for t in albumTracks {
                if isCached(t) {
                    cachedCount += 1
                } else {
                    missing.append(t)
                }
            }
            items.append(
                AlbumCacheReconcileItem(
                    albumName: albumName,
                    totalTracks: albumTracks.count,
                    cachedTracks: cachedCount,
                    missingTracks: missing
                )
            )
        }

        return items.sorted { a, b in
            if a.completionPercentage != b.completionPercentage {
                return a.completionPercentage < b.completionPercentage
            }
            return a.albumName.localizedCaseInsensitiveCompare(b.albumName) == .orderedAscending
        }
    }
}
