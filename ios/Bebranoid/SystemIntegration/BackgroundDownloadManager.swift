import Foundation

/// Менеджер фоновых загрузок `URLSession` (`background` configuration) и пакетного кеширования треков.
public final class BackgroundDownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = BackgroundDownloadManager()

    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.bebranoid.ios.background-downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private var destinationByTaskId: [Int: URL] = [:]

    private override init() {
        super.init()
    }

    public func scheduleBackgroundDownload(from remoteURL: URL, to destinationURL: URL) {
        let task = backgroundSession.downloadTask(with: remoteURL)
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
