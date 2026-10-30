import Foundation
import Combine

/// Высокоточный 60/120 Гц интерполятор позиции воспроизведения (`src/lib/smoothClock.js`).
/// Обеспечивает идеально плавное движение слайдера, послогового караоке и кроссфейда без рывков.
@MainActor
public final class SmoothClock: ObservableObject {
    @Published public private(set) var currentTime: Double = 0.0
    @Published public private(set) var isRunning: Bool = false

    private var timer: Timer?
    private var anchorAudioTime: Double = 0.0
    private var anchorWallTime: TimeInterval = 0.0
    private var effectiveRate: Double = 1.0
    private var sampleProvider: (() -> (time: Double, isPlaying: Bool, rate: Double))?
    private var tickHandler: ((Double) -> Void)?

    public init() {}

    public func bind(
        sampleProvider: @escaping () -> (time: Double, isPlaying: Bool, rate: Double),
        onTick: ((Double) -> Void)? = nil
    ) {
        self.sampleProvider = sampleProvider
        self.tickHandler = onTick
    }

    public func start() {
        guard timer == nil else { return }
        isRunning = true
        syncFromHardware()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.step()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Возвращает высокоточную интерполированную позицию в реальном времени (120 Гц ProMotion) без ожидания публикации `@Published`.
    public func interpolatedTime(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        guard isRunning, effectiveRate > 0 else {
            return currentTime
        }
        let dt = max(0.0, min(0.25, uptime - anchorWallTime))
        return max(0.0, anchorAudioTime + dt * effectiveRate)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    public func forceSetTime(_ time: Double) {
        anchorAudioTime = max(0, time)
        anchorWallTime = ProcessInfo.processInfo.systemUptime
        currentTime = anchorAudioTime
    }

    public func syncFromHardware() {
        guard let sample = sampleProvider?() else { return }
        anchorAudioTime = max(0, sample.time)
        anchorWallTime = ProcessInfo.processInfo.systemUptime
        effectiveRate = sample.isPlaying ? max(0.1, sample.rate) : 0.0
        currentTime = anchorAudioTime
    }

    private func step() {
        guard let sample = sampleProvider?() else { return }
        let now = ProcessInfo.processInfo.systemUptime

        if !sample.isPlaying {
            anchorAudioTime = sample.time
            anchorWallTime = now
            effectiveRate = 0.0
            currentTime = sample.time
            tickHandler?(currentTime)
            return
        }

        effectiveRate = max(0.1, sample.rate)
        let dt = max(0.0, now - anchorWallTime)
        let extrapolated = anchorAudioTime + dt * sample.rate
        let drift = abs(extrapolated - sample.time)

        // Если расхождение с аппаратным временем больше 90 мс — пересинхронизируем якорь
        if drift > 0.090 {
            anchorAudioTime = sample.time
            anchorWallTime = now
            currentTime = sample.time
        } else {
            currentTime = extrapolated
        }

        tickHandler?(currentTime)
    }
}
