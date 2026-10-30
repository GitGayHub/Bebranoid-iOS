import Foundation
import AVFoundation
import Combine

/// Двухпоточный аудио-движок Bebranoid (`src/App.jsx` 1:1).
/// Реализует:
/// - Два независимых дека (`Deck A` и `Deck B`) на базе `AVAudioEngine`
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

    public let smoothClock = SmoothClock()

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

    private func setupEngineGraph() {
        let format = engine.outputNode.outputFormat(forBus: 0)
        let validFormat = (format.sampleRate > 0 && format.channelCount > 0)
            ? format
            : AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)

        deckA.attachAndConnect(to: engine, format: validFormat)
        deckB.attachAndConnect(to: engine, format: validFormat)
        applyFXToBothDecks()
        updateDeckVolumes()
    }

    public func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true)
        } catch {
            // AudioSession может быть недоступна в headless CI окружении
        }
        #endif
    }

    private func ensureEngineRunning() {
        configureAudioSession()
        if !engine.isRunning {
            try? engine.start()
        }
    }

    // MARK: - Playback Controls

    /// Загружает и запускает трек на основном деке. Если шёл кроссфейд — выполняет мгновенный hard-cut.
    public func loadAndPlay(track: Track, fileURL: URL, startAt timeSec: Double = 0, autoPlay: Bool = true) async {
        cancelActiveCrossfade()
        scheduleGeneration &+= 1
        let currentGen = scheduleGeneration

        let inspected = await AudioMetadataReader.inspectAudioFile(at: fileURL)
        guard currentGen == scheduleGeneration else { return }

        activeTrack = track
        currentFormatInfo = inspected.formatInfo
        accumulatedListenSeconds = 0
        hasCountedPlayForCurrentTrack = false
        lastTickWallTime = ProcessInfo.processInfo.systemUptime

        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            primaryAudioFile = audioFile
            let sr = audioFile.processingFormat.sampleRate
            let totalFrames = audioFile.length
            let computedDuration = sr > 0 ? Double(totalFrames) / sr : inspected.duration
            duration = computedDuration > 0.5 ? computedDuration : max(computedDuration, track.duration)

            ensureEngineRunning()
            primaryDeck.deckMixerNode.outputVolume = 0.0
            primaryDeck.playerNode.stop()
            primaryDeck.resetDSPState()

            let clampedStart = max(0.0, min(timeSec, max(0.0, duration - 0.05)))
            let startFrame = AVAudioFramePosition(clampedStart * sr)
            primaryStartTimeOffset = clampedStart
            let remainingFrames = AVAudioFrameCount(max(0, totalFrames - startFrame))

            if remainingFrames > 0 {
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
                              self.isPlaying,
                              !self.isCrossfading else { return }
                        if self.duration > 0 && (self.duration - self.currentTime) < max(4.0, self.duration * 0.08) {
                            self.isPlaying = false
                            self.onTrackNaturallyEnded?()
                        }
                    }
                }
            }

            applyFXToBothDecks()
            updateDeckVolumes()
            smoothClock.forceSetTime(clampedStart)

            if autoPlay {
                primaryDeck.playerNode.play()
                isPlaying = true
                smoothClock.start()
            } else {
                isPlaying = false
            }
        } catch {
            isPlaying = false
        }
    }

    public func play() {
        guard primaryAudioFile != nil else { return }
        ensureEngineRunning()
        updateDeckVolumes()
        if !primaryDeck.playerNode.isPlaying {
            primaryDeck.playerNode.play()
        }
        lastTickWallTime = ProcessInfo.processInfo.systemUptime
        isPlaying = true
        smoothClock.start()
    }

    /// Пауза. Мгновенно глушит микшер и сбрасывает буферы реверберации (`resetDSPState`), чтобы в `Slowed + Reverb` не звучало эхо после паузы.
    public func pause() {
        if isCrossfading {
            cancelActiveCrossfade()
        }
        primaryDeck.deckMixerNode.outputVolume = 0.0
        secondaryDeck.deckMixerNode.outputVolume = 0.0
        primaryDeck.playerNode.pause()
        secondaryDeck.playerNode.stop()
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

    public func seek(to targetSeconds: Double) {
        guard let audioFile = primaryAudioFile else { return }
        if isCrossfading {
            cancelActiveCrossfade()
        }

        let sr = audioFile.processingFormat.sampleRate
        guard sr > 0 else { return }
        let clamped = max(0.0, min(targetSeconds, max(0.0, duration - 0.05)))
        let startFrame = AVAudioFramePosition(clamped * sr)
        let remainingFrames = AVAudioFrameCount(max(0, audioFile.length - startFrame))

        let wasPlaying = isPlaying
        scheduleGeneration &+= 1
        let currentGen = scheduleGeneration
        primaryDeck.deckMixerNode.outputVolume = 0.0
        primaryDeck.playerNode.stop()
        primaryDeck.resetDSPState()
        primaryStartTimeOffset = clamped

        if remainingFrames > 0 {
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
                          self.isPlaying,
                          !self.isCrossfading else { return }
                    if self.duration > 0 && (self.duration - self.currentTime) < max(4.0, self.duration * 0.08) {
                        self.isPlaying = false
                        self.onTrackNaturallyEnded?()
                    }
                }
            }
        }

        smoothClock.forceSetTime(clamped)
        currentTime = clamped

        if wasPlaying {
            ensureEngineRunning()
            updateDeckVolumes()
            primaryDeck.playerNode.play()
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
              nextFile.length > 0 else {
            return
        }

        secondaryAudioFile = nextFile
        secondaryStartTimeOffset = 0
        crossfadingNextTrack = nextItem.track
        crossfadeStartWallTime = ProcessInfo.processInfo.systemUptime
        isCrossfading = true
        crossfadeProgress = 0.0

        ensureEngineRunning()
        secondaryDeck.playerNode.stop()
        secondaryDeck.playerNode.scheduleFile(nextFile, at: nil, completionHandler: nil)
        secondaryDeck.deckMixerNode.outputVolume = 0.0
        secondaryDeck.playerNode.play()
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
        activeDeckIsA.toggle()

        primaryAudioFile = promotedFile
        primaryStartTimeOffset = 0
        secondaryAudioFile = nil
        crossfadingNextTrack = nil
        isCrossfading = false
        crossfadeProgress = 0.0

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
            return
        }
        secondaryDeck.playerNode.stop()
        secondaryAudioFile = nil
        crossfadingNextTrack = nil
        isCrossfading = false
        crossfadeProgress = 0.0
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

        guard let nodeTime = deck.playerNode.lastRenderTime,
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
        let dt = max(0.0, min(0.5, now - lastTickWallTime))
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
            if remaining <= 0.08 && isPlaying {
                isPlaying = false
                onTrackNaturallyEnded?()
            }
        }
    }

    // MARK: - iOS Audio Session Interruptions & Route Changes

    private func setupAudioSessionNotifications() {
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
            if reason == .oldDeviceUnavailable {
                Task { @MainActor [weak self] in
                    self?.pause()
                }
            }
        }
        #endif
    }
}
