import Foundation
import AVFoundation
import Combine

/// Двухпоточный аудио-движок Bebranoid (`src/App.jsx` 1:1).
/// Реализует:
/// - Два независимых дека (`Deck A` и `Deck B`) на базе `AVAudioEngine` с защитой от несовпадения форматов моно/стерео и смены маршрутов (AirPods / Bluetooth / LiveContainer)
/// - Настоящий перекрывающийся кроссфейд (0.5–30 с, по умолчанию 6 с) с синхронным `crossfadeProgress` для `HarmonoidMeshView`
/// - Мгновенный hard-cut при ручном выборе трека или нажатии Next / Prev
/// - Корректную отмену кроссфейда при постановке на паузу
/// - Перцептивную кривую громкости `uiToGain(u) = u^2.75`
/// - Эффекты `normal`, `slowed`, `slowed_reverb`, `speedup`, `speedup_reverb`, `Bass Boost (+8 dB @ 180 Hz)` и скорость `0.5x–2.0x`
/// - Автоматический подсчёт прослушивания после 5 секунд реального воспроизведения
@MainActor
public final class DualStreamAudioEngine: ObservableObject {
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentTime: Double = 0.0
    @Published public private(set) var duration: Double = 0.0
    @Published public private(set) var crossfadeProgress: Double = 0.0
    @Published public private(set) var isCrossfading: Bool = false
    @Published public private(set) var currentFormatInfo: AudioFormatInfo?

    public var uiVolume: Double = 0.85 {
        didSet { updateDeckVolumes() }
    }
    public var playbackSpeed: Float = 1.0 {
        didSet { applyFXToBothDecks() }
    }
    public var audioFXMode: AudioFXMode = .normal {
        didSet { applyFXToBothDecks() }
    }
    public var bassBoostEnabled: Bool = false {
        didSet { applyFXToBothDecks() }
    }
    public var crossfadeEnabled: Bool = true
    public var crossfadeDuration: Double = AppConfig.defaultCrossfadeDuration

    /// Колбэки жизненного цикла для `BebranoidAppState`
    public var onRequestNextTrackForCrossfade: (() -> (track: Track, fileURL: URL)?)?
    public var onCrossfadeCompleted: ((Track) -> Void)?
    public var onTrackNaturallyEnded: (() -> Void)?
    public var onPlayCountThresholdReached: ((Track) -> Void)?

    private let engine = AVAudioEngine()
    private let deckA = DeckAudioFXChain()
    private let deckB = DeckAudioFXChain()
    private var activeDeckIsA: Bool = true
    private var needsGraphReconnect: Bool = false
    private var didFireNaturalEndForCurrentGen: Bool = false

    private var primaryAudioFile: AVAudioFile?
    private var secondaryAudioFile: AVAudioFile?
    private var primaryStartTimeOffset: Double = 0
    private var secondaryStartTimeOffset: Double = 0

    private var activeTrack: Track?
    private var crossfadingNextTrack: Track?
    private var crossfadeStartWallTime: TimeInterval = 0
    private var accumulatedListenSeconds: Double = 0
    private var lastTickWallTime: TimeInterval = 0
    private var hasCountedPlayForCurrentTrack: Bool = false
    private var scheduleGeneration: UInt64 = 0
    private var seekAnchorUptime: TimeInterval = 0
    private var seekGraceUntilUptime: TimeInterval = 0

    public let smoothClock = SmoothClock()

    /// Мгновенная 120 Гц интерполированная позиция для прогресс-бара и караоке без рывков квантования
    public var livePlaybackTime: Double {
        let raw = isPlaying ? smoothClock.interpolatedTime() : currentTime
        if duration > 0 {
            return min(duration, max(0.0, raw))
        }
        return max(0.0, raw)
    }

    public init() {
        setupEngineGraph()
        setupAudioSessionNotifications()
        smoothClock.bind(
            sampleProvider: { [weak self] in
                guard let self else { return (0, false, 1.0) }
                return (self.readHardwareTime(forPrimary: true), self.isPlaying, Double(self.effectivePlaybackRate))
            },
            onTick: { [weak self] interpolatedTime in
                self?.handleClockTick(interpolatedTime)
            }
        )
    }

    public var effectivePlaybackRate: Float {
        let base = max(0.5, min(2.0, playbackSpeed))
        return audioFXMode.shiftsPitchWithRate ? (audioFXMode.defaultRateMultiplier * base) : base
    }

    private var primaryDeck: DeckAudioFXChain {
        activeDeckIsA ? deckA : deckB
    }

    private var secondaryDeck: DeckAudioFXChain {
        activeDeckIsA ? deckB : deckA
    }

    private func currentValidBusFormat() -> AVAudioFormat? {
        let format = engine.outputNode.outputFormat(forBus: 0)
        if format.sampleRate > 0 && format.channelCount > 0 {
            return format
        }
        return AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
    }

    private func setupEngineGraph() {
        let validFormat = currentValidBusFormat()
        deckA.attachAndConnect(to: engine, format: validFormat)
        deckB.attachAndConnect(to: engine, format: validFormat)
        applyFXToBothDecks()
        updateDeckVolumes()
        needsGraphReconnect = false
    }

    private func rebuildEngineConnectionsIfNeeded() {
        guard needsGraphReconnect else { return }
        if engine.isRunning {
            engine.stop()
        }
        let validFormat = currentValidBusFormat()
        deckA.connectGraph(in: engine, busFormat: validFormat)
        deckB.connectGraph(in: engine, busFormat: validFormat)
        if let pf = primaryAudioFile {
            primaryDeck.preparePlayerConnection(for: pf, in: engine)
        }
        if let sf = secondaryAudioFile {
            secondaryDeck.preparePlayerConnection(for: sf, in: engine)
        }
        applyFXToBothDecks()
        updateDeckVolumes()
        needsGraphReconnect = false
    }

    public func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true)
        } catch {
            // AudioSession может быть недоступна в headless CI окружении или временно удерживаться контейнером
        }
        #endif
    }

    @discardableResult
    private func ensureEngineRunning() -> Bool {
        configureAudioSession()
        rebuildEngineConnectionsIfNeeded()
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                // Повторная попытка с пересборкой соединений после смены аудио-маршрута / LiveContainer
                needsGraphReconnect = true
                rebuildEngineConnectionsIfNeeded()
                engine.prepare()
                try? engine.start()
            }
        }
        return engine.isRunning
    }

    // MARK: - Playback Controls

    /// Загружает и запускает трек на основном деке. Если шёл кроссфейд — выполняет мгновенный hard-cut.
    public func loadAndPlay(track: Track, fileURL: URL, startAt timeSec: Double = 0, autoPlay: Bool = true) async {
        cancelActiveCrossfade()
        scheduleGeneration &+= 1
        let currentGen = scheduleGeneration
        didFireNaturalEndForCurrentGen = false

        let initialPos = max(0.0, timeSec)
        primaryStartTimeOffset = initialPos
        currentTime = initialPos
        if track.duration > 0 {
            duration = track.duration
        }
        smoothClock.forceSetTime(initialPos)
        let preNow = ProcessInfo.processInfo.systemUptime
        seekAnchorUptime = preNow
        seekGraceUntilUptime = preNow + 0.32

        let inspected = await AudioMetadataReader.inspectAudioFile(at: fileURL)
        guard currentGen == scheduleGeneration else { return }

        activeTrack = track
        currentFormatInfo = inspected.formatInfo
        accumulatedListenSeconds = 0
        hasCountedPlayForCurrentTrack = false
        lastTickWallTime = ProcessInfo.processInfo.systemUptime

        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let sr = audioFile.processingFormat.sampleRate
            let totalFrames = audioFile.length
            guard sr > 0, totalFrames > 0 else {
                isPlaying = false
                return
            }

            primaryAudioFile = audioFile
            let computedDuration = Double(totalFrames) / sr
            duration = computedDuration > 0.5 ? computedDuration : max(computedDuration, track.duration)

            primaryDeck.deckMixerNode.outputVolume = 0.0
            primaryDeck.playerNode.stop()
            primaryDeck.resetDSPState()
            primaryDeck.preparePlayerConnection(for: audioFile, in: engine)

            let engineReady = ensureEngineRunning()

            let clampedStart = max(0.0, min(timeSec, max(0.0, duration - 0.05)))
            let startFrame = AVAudioFramePosition(clampedStart * sr)
            primaryStartTimeOffset = clampedStart
            let remainingFrames = AVAudioFrameCount(max(0, totalFrames - startFrame))

            if remainingFrames > 0 && engineReady {
                primaryDeck.playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startFrame,
                    frameCount: remainingFrames,
                    at: nil,
                    completionCallbackType: .dataPlayedBack
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.scheduleGeneration == currentGen,
                              !self.didFireNaturalEndForCurrentGen,
                              self.isPlaying,
                              !self.isCrossfading else { return }
                        let liveNow = self.livePlaybackTime
                        if self.duration > 0 && (self.duration - liveNow) < max(4.5, self.duration * 0.09) {
                            self.didFireNaturalEndForCurrentGen = true
                            self.isPlaying = false
                            self.smoothClock.stop()
                            self.onTrackNaturallyEnded?()
                        }
                    }
                }
            }

            applyFXToBothDecks()
            updateDeckVolumes()
            let postNow = ProcessInfo.processInfo.systemUptime
            seekAnchorUptime = postNow
            seekGraceUntilUptime = postNow + 0.28
            smoothClock.forceSetTime(clampedStart)
            currentTime = clampedStart

            if autoPlay && engineReady && remainingFrames > 0 {
                primaryDeck.playerNode.play()
                isPlaying = true
                smoothClock.start(highFrequencyForCrossfade: false)
            } else {
                isPlaying = false
                smoothClock.stop()
            }
        } catch {
            isPlaying = false
            smoothClock.stop()
        }
    }

    public func play() {
        guard let audioFile = primaryAudioFile else { return }
        guard ensureEngineRunning() else {
            isPlaying = false
            return
        }
        updateDeckVolumes()
        if !primaryDeck.playerNode.isPlaying {
            // Если после смены маршрута буфер был сброшен — перепланируем с текущей позиции
            let sr = audioFile.processingFormat.sampleRate
            if sr > 0 && (primaryDeck.playerNode.lastRenderTime == nil || needsGraphReconnect) {
                seek(to: currentTime, forcePlayAfterSeek: true)
                return
            }
            primaryDeck.playerNode.play()
        }
        lastTickWallTime = ProcessInfo.processInfo.systemUptime
        isPlaying = true
        smoothClock.start(highFrequencyForCrossfade: isCrossfading)
    }

    /// Пауза. Мгновенно глушит микшер и сбрасывает буферы реверберации (`resetDSPState`), чтобы в `Slowed + Reverb` не звучало эхо после паузы.
    public func pause() {
        if isCrossfading {
            cancelActiveCrossfade()
        }
        primaryDeck.deckMixerNode.outputVolume = 0.0
        secondaryDeck.deckMixerNode.outputVolume = 0.0
        if engine.isRunning {
            primaryDeck.playerNode.pause()
            secondaryDeck.playerNode.stop()
        }
        primaryDeck.resetDSPState()
        secondaryDeck.resetDSPState()
        isPlaying = false
        smoothClock.stop()
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func seek(to targetSeconds: Double, forcePlayAfterSeek: Bool = false) {
        guard let audioFile = primaryAudioFile else { return }
        if isCrossfading {
            cancelActiveCrossfade()
        }

        let sr = audioFile.processingFormat.sampleRate
        guard sr > 0 else { return }
        let clamped = max(0.0, min(targetSeconds, max(0.0, duration - 0.05)))
        let startFrame = AVAudioFramePosition(clamped * sr)
        let remainingFrames = AVAudioFrameCount(max(0, audioFile.length - startFrame))

        let shouldPlay = isPlaying || forcePlayAfterSeek
        scheduleGeneration &+= 1
        let currentGen = scheduleGeneration
        didFireNaturalEndForCurrentGen = false

        primaryDeck.deckMixerNode.outputVolume = 0.0
        primaryDeck.playerNode.stop()
        primaryDeck.resetDSPState()
        primaryDeck.preparePlayerConnection(for: audioFile, in: engine)
        primaryStartTimeOffset = clamped

        let engineReady = ensureEngineRunning()

        if remainingFrames > 0 && engineReady {
            primaryDeck.playerNode.scheduleSegment(
                audioFile,
                startingFrame: startFrame,
                frameCount: remainingFrames,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.scheduleGeneration == currentGen,
                          !self.didFireNaturalEndForCurrentGen,
                          self.isPlaying,
                          !self.isCrossfading else { return }
                    let liveNow = self.livePlaybackTime
                    if self.duration > 0 && (self.duration - liveNow) < max(4.5, self.duration * 0.09) {
                        self.didFireNaturalEndForCurrentGen = true
                        self.isPlaying = false
                        self.smoothClock.stop()
                        self.onTrackNaturallyEnded?()
                    }
                }
            }
        }

        let seekNow = ProcessInfo.processInfo.systemUptime
        seekAnchorUptime = seekNow
        seekGraceUntilUptime = seekNow + 0.30
        smoothClock.forceSetTime(clamped)
        currentTime = clamped

        if shouldPlay && engineReady && remainingFrames > 0 {
            updateDeckVolumes()
            primaryDeck.playerNode.play()
            isPlaying = true
            smoothClock.start(highFrequencyForCrossfade: false)
        }
    }

    // MARK: - Real Dual-Deck Crossfade Engine

    private func startCrossfadeIfNeeded(remainingSeconds: Double) {
        guard crossfadeEnabled,
              !isCrossfading,
              isPlaying,
              duration > crossfadeDuration + 2.0,
              remainingSeconds <= crossfadeDuration,
              remainingSeconds > 0.15 else {
            return
        }

        guard let nextItem = onRequestNextTrackForCrossfade?(),
              let nextFile = try? AVAudioFile(forReading: nextItem.fileURL),
              nextFile.length > 0,
              nextFile.processingFormat.sampleRate > 0 else {
            return
        }

        secondaryDeck.playerNode.stop()
        secondaryDeck.resetDSPState()
        secondaryDeck.preparePlayerConnection(for: nextFile, in: engine)

        guard ensureEngineRunning() else { return }

        secondaryAudioFile = nextFile
        secondaryStartTimeOffset = 0
        crossfadingNextTrack = nextItem.track
        crossfadeStartWallTime = ProcessInfo.processInfo.systemUptime
        isCrossfading = true
        crossfadeProgress = 0.0

        secondaryDeck.playerNode.scheduleFile(nextFile, at: nil, completionHandler: nil)
        secondaryDeck.deckMixerNode.outputVolume = 0.0
        secondaryDeck.playerNode.play()
        smoothClock.setCrossfadeHighFrequency(true)
    }

    private func updateCrossfadeStep() {
        guard isCrossfading else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0.0, now - crossfadeStartWallTime)
        let effectiveFadeDuration = max(AppConfig.minCrossfadeDuration, min(AppConfig.maxCrossfadeDuration, crossfadeDuration))
        let progress = min(1.0, max(0.0, elapsed / effectiveFadeDuration))

        crossfadeProgress = progress
        updateDeckVolumes()

        if progress >= 1.0 {
            finalizeCrossfade()
        }
    }

    private func finalizeCrossfade() {
        guard isCrossfading, let promotedTrack = crossfadingNextTrack, let promotedFile = secondaryAudioFile else {
            cancelActiveCrossfade()
            return
        }

        // Останавливаем старый основной дек и меняем роли деков без остановки звука
        primaryDeck.playerNode.stop()
        primaryDeck.resetDSPState()
        activeDeckIsA.toggle()

        scheduleGeneration &+= 1
        didFireNaturalEndForCurrentGen = false

        primaryAudioFile = promotedFile
        primaryStartTimeOffset = 0
        secondaryAudioFile = nil
        crossfadingNextTrack = nil
        isCrossfading = false
        crossfadeProgress = 0.0
        smoothClock.setCrossfadeHighFrequency(false)

        activeTrack = promotedTrack
        let sr = promotedFile.processingFormat.sampleRate
        duration = sr > 0 ? Double(promotedFile.length) / sr : promotedTrack.duration
        accumulatedListenSeconds = 0
        hasCountedPlayForCurrentTrack = false

        updateDeckVolumes()
        let newTime = readHardwareTime(forPrimary: true)
        smoothClock.forceSetTime(newTime)
        currentTime = newTime

        onCrossfadeCompleted?(promotedTrack)
    }

    public func cancelActiveCrossfade() {
        guard isCrossfading else {
            crossfadeProgress = 0.0
            smoothClock.setCrossfadeHighFrequency(false)
            return
        }
        secondaryDeck.playerNode.stop()
        secondaryDeck.resetDSPState()
        secondaryAudioFile = nil
        crossfadingNextTrack = nil
        isCrossfading = false
        crossfadeProgress = 0.0
        smoothClock.setCrossfadeHighFrequency(false)
        updateDeckVolumes()
    }

    // MARK: - Gain & FX Management

    private func updateDeckVolumes() {
        let baseGain = Float(VolumeCurve.uiToGain(uiVolume))
        if isCrossfading {
            let fade = Float(HarmonoidMeshEngine.smoothstep(0.0, 1.0, crossfadeProgress))
            primaryDeck.deckMixerNode.outputVolume = baseGain * (1.0 - fade)
            secondaryDeck.deckMixerNode.outputVolume = baseGain * fade
        } else {
            primaryDeck.deckMixerNode.outputVolume = baseGain
            secondaryDeck.deckMixerNode.outputVolume = 0.0
        }
    }

    private func applyFXToBothDecks() {
        deckA.applyParameters(fxMode: audioFXMode, userPlaybackSpeed: playbackSpeed, bassBoostEnabled: bassBoostEnabled)
        deckB.applyParameters(fxMode: audioFXMode, userPlaybackSpeed: playbackSpeed, bassBoostEnabled: bassBoostEnabled)
    }

    private func readHardwareTime(forPrimary: Bool) -> Double {
        let deck = forPrimary ? primaryDeck : secondaryDeck
        let offsetSec = forPrimary ? primaryStartTimeOffset : secondaryStartTimeOffset

        if forPrimary {
            let now = ProcessInfo.processInfo.systemUptime
            if now < seekGraceUntilUptime {
                if isPlaying {
                    let elapsed = max(0.0, now - seekAnchorUptime)
                    return max(0.0, offsetSec + elapsed * Double(effectivePlaybackRate))
                } else {
                    return max(0.0, offsetSec)
                }
            }
        }

        guard engine.isRunning,
              let nodeTime = deck.playerNode.lastRenderTime,
              let playerTime = deck.playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else {
            return currentTime
        }
        let playedSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
        guard playedSeconds.isFinite && playedSeconds >= 0 else {
            return max(0.0, offsetSec)
        }
        return max(0.0, offsetSec + playedSeconds)
    }

    private func handleClockTick(_ time: Double) {
        currentTime = time
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0.0, min(0.6, now - lastTickWallTime))
        lastTickWallTime = now

        if isPlaying {
            accumulatedListenSeconds += dt
            if !hasCountedPlayForCurrentTrack,
               accumulatedListenSeconds >= AppConfig.playCountListenThresholdSeconds,
               let track = activeTrack {
                hasCountedPlayForCurrentTrack = true
                onPlayCountThresholdReached?(track)
            }
        }

        if isCrossfading {
            updateCrossfadeStep()
        } else if duration > 0 {
            let remaining = duration - time
            if remaining <= crossfadeDuration && crossfadeEnabled {
                startCrossfadeIfNeeded(remainingSeconds: remaining)
            }
            if remaining <= 0.12 && isPlaying && !didFireNaturalEndForCurrentGen {
                didFireNaturalEndForCurrentGen = true
                isPlaying = false
                smoothClock.stop()
                onTrackNaturallyEnded?()
            }
        }
    }

    // MARK: - iOS Audio Session Interruptions, Route & Hardware Configuration Changes

    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.needsGraphReconnect = true
                if self.isPlaying {
                    let resumePos = self.currentTime
                    self.rebuildEngineConnectionsIfNeeded()
                    self.seek(to: resumePos, forcePlayAfterSeek: true)
                }
            }
        }

        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch type {
                case .began:
                    self.pause()
                case .ended:
                    if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                        if options.contains(.shouldResume) {
                            self.play()
                        }
                    }
                @unknown default:
                    break
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch reason {
                case .oldDeviceUnavailable:
                    self.pause()
                case .newDeviceAvailable, .categoryChange:
                    self.needsGraphReconnect = true
                    if self.isPlaying {
                        let resumePos = self.currentTime
                        self.rebuildEngineConnectionsIfNeeded()
                        self.seek(to: resumePos, forcePlayAfterSeek: true)
                    }
                default:
                    break
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasPlaying = self.isPlaying
                let resumePos = self.currentTime
                self.needsGraphReconnect = true
                self.setupEngineGraph()
                if wasPlaying {
                    self.seek(to: resumePos, forcePlayAfterSeek: true)
                }
            }
        }
        #endif
    }
}
