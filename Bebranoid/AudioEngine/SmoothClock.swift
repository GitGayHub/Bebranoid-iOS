import Foundation
import Combine

/// Высокоточный 60/120 Гц интерполятор позиции воспроизведения (`src/lib/smoothClock.js`).
/// Обеспечивает идеально плавное движение слайдера, послогового караоке и кроссфейда без рывков
/// и без лишних пробуждений CPU (интерполяция выполняется аналитически по системному `systemUptime`,
/// а фоновая сверка с аппаратным аудио-узлом работает на экономичной частоте 4 Гц, повышаясь до 30 Гц только на время кроссфейда).
@MainActor
public final class SmoothClock: ObservableObject {
    @Published public private(set) var currentTime: Double = 0.0
    @Published public private(set) var isRunning: Bool = false

    private var timer: Timer?
    private var currentInterval: TimeInterval = 0.25
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

    public func start(highFrequencyForCrossfade: Bool = false) {
        let desiredInterval: TimeInterval = highFrequencyForCrossfade ? (1.0 / 30.0) : 0.25
        if timer != nil && abs(currentInterval - desiredInterval) < 0.005 {
            return
        }
        timer?.invalidate()
        timer = nil
        currentInterval = desiredInterval
        isRunning = true
        syncFromHardware()

        let newTimer = Timer(timeInterval: desiredInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.step()
            }
        }
        newTimer.tolerance = highFrequencyForCrossfade ? 0.005 : 0.04
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    public func setCrossfadeHighFrequency(_ enabled: Bool) {
        guard isRunning else { return }
        let desiredInterval: TimeInterval = enabled ? (1.0 / 30.0) : 0.25
        guard abs(currentInterval - desiredInterval) >= 0.005 else { return }
        start(highFrequencyForCrossfade: enabled)
    }

    /// Возвращает высокоточную интерполированную позицию в реальном времени (120 Гц ProMotion) без ожидания публикации `@Published`.
    public func interpolatedTime(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        guard isRunning, effectiveRate > 0 else {
            return currentTime
        }
        let dt = max(0.0, min(1.50, uptime - anchorWallTime))
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
            if abs(currentTime - sample.time) > 0.01 {
                currentTime = sample.time
            }
            tickHandler?(currentTime)
            return
        }

        effectiveRate = max(0.1, sample.rate)
        let dt = max(0.0, now - anchorWallTime)
        let extrapolated = anchorAudioTime + dt * sample.rate
        let drift = abs(extrapolated - sample.time)

        if drift > 0.085 {
            anchorAudioTime = sample.time
            anchorWallTime = now
            currentTime = sample.time
        } else {
            anchorAudioTime = extrapolated
            anchorWallTime = now
            currentTime = extrapolated
        }

        tickHandler?(currentTime)
    }
}
