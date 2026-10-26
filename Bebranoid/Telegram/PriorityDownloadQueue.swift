import Foundation

/// Ошибка кооперативного вытеснения фоновой загрузки более приоритетной задачей (`DownloadPreempted` в `electron/download-queue.cjs`)
public struct DownloadPreemptedError: Error, Sendable {
    public let key: String
    public let bytesSaved: Int64

    public init(key: String, bytesSaved: Int64 = 0) {
        self.key = key
        self.bytesSaved = bytesSaved
    }
}

/// Уровни приоритетов загрузки (`electron/download-queue.cjs` 1:1):
/// - `3`: Активный воспроизводимый прямо сейчас трек (понижает предыдущие задачи с приоритетом 3 до 1 и вытесняет фоновые задачи `< 3`)
/// - `1`: Предзагрузка следующего трека очереди (prefetch)
/// - `0`: Пакетное фоновое кеширование (например из окна «Сверка»)
public enum DownloadPriorityLevel: Int, Comparable, Sendable {
    case backgroundBatch = 0
    case nextTrackPrefetch = 1
    case activePlayback = 3

    public static func < (lhs: DownloadPriorityLevel, rhs: DownloadPriorityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Контекст кооперативного вытеснения, передаваемый внутрь воркера скачивания
public final class DownloadPreemptionToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isPreempted: Bool = false

    public init() {}

    public var isPreempted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isPreempted
    }

    public func triggerPreempt() {
        lock.lock()
        _isPreempted = true
        lock.unlock()
    }

    public func throwIfPreempted(key: String, bytesSaved: Int64 = 0) throws {
        if isPreempted {
            throw DownloadPreemptedError(key: key, bytesSaved: bytesSaved)
        }
    }
}

/// Точный 1:1 порт `PriorityDownloadQueue` из `electron/download-queue.cjs`.
public actor PriorityDownloadQueue {
    public static let shared = PriorityDownloadQueue()
    public typealias DownloadWorker = @Sendable (DownloadPreemptionToken) async throws -> URL

    private struct QueuedJob {
        let key: String
        var priority: Int
        let sequenceId: UInt64
        let worker: DownloadWorker
        var continuations: [CheckedContinuation<URL, Error>]
    }

    private struct ActiveJob {
        let key: String
        var priority: Int
        let token: DownloadPreemptionToken
        let worker: DownloadWorker
        var continuations: [CheckedContinuation<URL, Error>]
    }

    private let concurrency: Int
    private var sequenceCounter: UInt64 = 0
    private var pendingJobs: [String: QueuedJob] = [:]
    private var activeJobs: [String: ActiveJob] = [:]
    public private(set) var failedDownloadsCount: Int = 0

    public init(concurrency: Int = 2) {
        self.concurrency = max(1, concurrency)
    }

    public var pendingCount: Int {
        pendingJobs.count
    }

    public var activeCount: Int {
        activeJobs.count
    }

    public func enqueue(
        key: String,
        trackId: String? = nil,
        priority: DownloadPriorityLevel,
        worker: @escaping DownloadWorker
    ) async throws -> URL {
        try await enqueue(key: key, priority: priority.rawValue, worker: worker)
    }

    /// Постановка задачи скачивания в очередь с указанным приоритетом (`enqueue(key, priority, fn)`)
    public func enqueue(
        key: String,
        priority: Int = DownloadPriorityLevel.backgroundBatch.rawValue,
        worker: @escaping DownloadWorker
    ) async throws -> URL {
        // При появлении новой задачи с приоритетом >= 3 понижаем предыдущие ожидающие задачи с приоритетом 3 до 1
        // и кооперативно вытесняем активные задачи с приоритетом < 3
        if priority >= DownloadPriorityLevel.activePlayback.rawValue {
            demoteExistingTopPriorityJobs(exceptKey: key)
            preemptLowerPriorityActiveJobs(threshold: priority, exceptKey: key)
        }

        // Если задача уже выполняется — повышаем её приоритет и подписываемся на результат
        if var running = activeJobs[key] {
            if priority > running.priority {
                running.priority = priority
                activeJobs[key] = running
            }
            return try await withCheckedThrowingContinuation { continuation in
                var current = activeJobs[key]!
                current.continuations.append(continuation)
                activeJobs[key] = current
            }
        }

        // Если задача уже в очереди ожидания — обновляем приоритет до максимального и подписываемся
        if var queued = pendingJobs[key] {
            if priority > queued.priority {
                queued.priority = priority
            }
            return try await withCheckedThrowingContinuation { continuation in
                queued.continuations.append(continuation)
                pendingJobs[key] = queued
                pumpQueue()
            }
        }

        sequenceCounter &+= 1
        let seq = sequenceCounter

        return try await withCheckedThrowingContinuation { continuation in
            let job = QueuedJob(
                key: key,
                priority: priority,
                sequenceId: seq,
                worker: worker,
                continuations: [continuation]
            )
            pendingJobs[key] = job
            pumpQueue()
        }
    }

    private func demoteExistingTopPriorityJobs(exceptKey: String) {
        for (k, var job) in pendingJobs where k != exceptKey && job.priority >= DownloadPriorityLevel.activePlayback.rawValue {
            job.priority = DownloadPriorityLevel.nextTrackPrefetch.rawValue
            pendingJobs[k] = job
        }
        for (k, var job) in activeJobs where k != exceptKey && job.priority >= DownloadPriorityLevel.activePlayback.rawValue {
            job.priority = DownloadPriorityLevel.nextTrackPrefetch.rawValue
            activeJobs[k] = job
        }
    }

    private func preemptLowerPriorityActiveJobs(threshold: Int, exceptKey: String) {
        for (k, job) in activeJobs where k != exceptKey && job.priority < threshold {
            job.token.triggerPreempt()
        }
    }

    private func pumpQueue() {
        while activeJobs.count < concurrency, let nextKey = selectHighestPriorityKey() {
            guard let job = pendingJobs.removeValue(forKey: nextKey) else { break }
            let token = DownloadPreemptionToken()
            let active = ActiveJob(
                key: job.key,
                priority: job.priority,
                token: token,
                worker: job.worker,
                continuations: job.continuations
            )
            activeJobs[job.key] = active

            Task {
                await executeActiveJob(key: job.key, token: token, worker: job.worker)
            }
        }
    }

    private func selectHighestPriorityKey() -> String? {
        pendingJobs.values.max { a, b in
            if a.priority != b.priority {
                return a.priority < b.priority
            }
            return a.sequenceId > b.sequenceId
        }?.key
    }

    private func executeActiveJob(key: String, token: DownloadPreemptionToken, worker: @escaping DownloadWorker) async {
        do {
            let resultURL = try await worker(token)
            guard let finished = activeJobs.removeValue(forKey: key) else { return }
            for cont in finished.continuations {
                cont.resume(returning: resultURL)
            }
        } catch is DownloadPreemptedError {
            // Задача была кооперативно вытеснена более важной загрузкой — возвращаем её в очередь ожидания с приоритетом 1/0
            if let preempted = activeJobs.removeValue(forKey: key) {
                sequenceCounter &+= 1
                let requeued = QueuedJob(
                    key: preempted.key,
                    priority: min(preempted.priority, DownloadPriorityLevel.nextTrackPrefetch.rawValue),
                    sequenceId: sequenceCounter,
                    worker: preempted.worker,
                    continuations: preempted.continuations
                )
                pendingJobs[key] = requeued
            }
        } catch {
            failedDownloadsCount += 1
            if let failed = activeJobs.removeValue(forKey: key) {
                for cont in failed.continuations {
                    cont.resume(throwing: error)
                }
            }
        }
        pumpQueue()
    }
}
