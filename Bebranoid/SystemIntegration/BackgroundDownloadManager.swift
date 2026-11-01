import Foundation

/// Менеджер загрузок `URLSession` с автоматической защитой совместимости с LiveContainer / Sideload окружениями
/// (внутри LiveContainer фоновый идентификатор чужого Bundle ID может приводить к принудительному завершению со стороны `nsurlsessiond`).
public final class BackgroundDownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = BackgroundDownloadManager()

    /// Определяет, запущено ли приложение внутри хост-процесса LiveContainer
    public static var isRunningInsideLiveContainer: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["LC_HOME_PATH"] != nil || env["LIVECONTAINER"] != nil {
            return true
        }
        if let bundleId = Bundle.main.bundleIdentifier,
           bundleId.lowercased().contains("livecontainer") {
            return true
        }
        return false
    }

    private lazy var downloadSession: URLSession = {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.bebranoid.ios"
        if Self.isRunningInsideLiveContainer || bundleId != "com.bebranoid.ios" {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.timeoutIntervalForResource = 300
            return URLSession(configuration: config, delegate: self, delegateQueue: nil)
        } else {
            let config = URLSessionConfiguration.background(withIdentifier: "\(bundleId).background-downloads")
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            return URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }
    }()

    private let lock = NSLock()
    private var destinationByTaskId: [Int: URL] = [:]

    private override init() {
        super.init()
    }

    public func scheduleBackgroundDownload(from remoteURL: URL, to destinationURL: URL) {
        let task = downloadSession.downloadTask(with: remoteURL)
        lock.lock()
        destinationByTaskId[task.taskIdentifier] = destinationURL
        lock.unlock()
        task.resume()
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        let dest = destinationByTaskId.removeValue(forKey: downloadTask.taskIdentifier)
        lock.unlock()

        guard let dest else { return }
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: location, to: dest)
    }
}
