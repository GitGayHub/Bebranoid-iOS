import Foundation
import AVFAudio

/// Граф DSP-эффектов для одного дека (`src/App.jsx` `ensureFxGraph`, `applyAudioFxMode`, `createImpulseResponse`).
/// Включает:
/// - `AVAudioUnitVarispeed`: натуральный сдвиг высоты тона при изменении скорости (`slowed`, `speedup`, как `preservesPitch = false`)
/// - `AVAudioUnitTimePitch`: независимое изменение скорости без изменения высоты тона в режиме `normal`
/// - `AVAudioUnitEQ`:
///   - Полоса 0: `lowShelf` `180 Hz`, `+8.0 dB`, `Q = 0.707` для Bass Boost
///   - Полоса 1: `lowPass` `6500 Hz` для сглаживания высоких частот хвоста реверберации в режиме `slowed_reverb` / `speedup_reverb`
/// - `AVAudioUnitReverb`: пространственная реверберация (`largeHall2` / синтетический 2.8s эквивалент)
public final class DeckAudioFXChain {
    public let playerNode = AVAudioPlayerNode()
    public let varispeedUnit = AVAudioUnitVarispeed()
    public let timePitchUnit = AVAudioUnitTimePitch()
    public let eqUnit = AVAudioUnitEQ(numberOfBands: 2)
    public let reverbUnit = AVAudioUnitReverb()
    public let deckMixerNode = AVAudioMixerNode()

    public init() {
        configureInitialNodes()
    }

    private func configureInitialNodes() {
        // Настраиваем полосу 0: Bass Boost (LowShelf 180 Hz, +8 dB)
        if eqUnit.bands.count >= 2 {
            let bassBand = eqUnit.bands[0]
            bassBand.filterType = .lowShelf
            bassBand.frequency = 180.0
            bassBand.bandwidth = 0.707
            bassBand.gain = 0.0
            bassBand.bypass = true

            // Полоса 1: LowPass 6500 Hz для тёплой атмосферной реверберации (`biquadFilter` 6500Hz в `App.jsx`)
            let lpBand = eqUnit.bands[1]
            lpBand.filterType = .lowPass
            lpBand.frequency = 6500.0
            lpBand.bandwidth = 0.707
            lpBand.bypass = true
        }

        reverbUnit.loadFactoryPreset(.largeHall2)
        reverbUnit.wetDryMix = 0.0
    }

    /// Прикрепляет узлы дека к `AVAudioEngine` и соединяет их в единую цепочку
    public func attachAndConnect(to engine: AVAudioEngine, format: AVAudioFormat?) {
        engine.attach(playerNode)
        engine.attach(varispeedUnit)
        engine.attach(timePitchUnit)
        engine.attach(eqUnit)
        engine.attach(reverbUnit)
        engine.attach(deckMixerNode)

        engine.connect(playerNode, to: varispeedUnit, format: format)
        engine.connect(varispeedUnit, to: timePitchUnit, format: format)
        engine.connect(timePitchUnit, to: eqUnit, format: format)
        engine.connect(eqUnit, to: reverbUnit, format: format)
        engine.connect(reverbUnit, to: deckMixerNode, format: format)
        engine.connect(deckMixerNode, to: engine.mainMixerNode, format: format)
    }

    /// Применяет текущие настройки AudioFXMode, пользовательской скорости и Bass Boost
    public func applyParameters(
        fxMode: AudioFXMode,
        userPlaybackSpeed: Float,
        bassBoostEnabled: Bool
    ) {
        let clampedSpeed = min(2.0, max(0.5, userPlaybackSpeed))

        if fxMode.shiftsPitchWithRate {
            // Режимы slowed / slowed_reverb / speedup / speedup_reverb сдвигают питч вместе со скоростью
            let targetRate = fxMode.defaultRateMultiplier * clampedSpeed
            varispeedUnit.rate = min(4.0, max(0.25, targetRate))
            timePitchUnit.rate = 1.0
            timePitchUnit.pitch = 0.0
        } else {
            // Обычный режим: скорость меняется без изменения тональности
            varispeedUnit.rate = 1.0
            timePitchUnit.rate = clampedSpeed
            timePitchUnit.pitch = 0.0
        }

        // Bass Boost (180 Hz, +8 dB)
        if eqUnit.bands.count >= 1 {
            let bassBand = eqUnit.bands[0]
            bassBand.gain = bassBoostEnabled ? 8.0 : 0.0
            bassBand.bypass = !bassBoostEnabled
        }

        // Реверберация и НЧ-фильтрация (6500 Hz)
        if eqUnit.bands.count >= 2 {
            let lpBand = eqUnit.bands[1]
            lpBand.bypass = !fxMode.usesReverb
        }

        if fxMode.usesReverb {
            let total = fxMode.dryGain + fxMode.wetGain
            let wetPercent = total > 0 ? (fxMode.wetGain / total) * 100.0 : 0.0
            reverbUnit.wetDryMix = min(100.0, max(0.0, wetPercent))
        } else {
            reverbUnit.wetDryMix = 0.0
        }
    }

    /// Генератор буфера стерео импульсного отклика 2.8s (1:1 порт `createImpulseResponse` из `src/App.jsx`)
    public static func generateSyntheticImpulseResponse(
        sampleRate: Double = 44100.0,
        durationSeconds: Double = 2.8,
        decay: Double = 2.6
    ) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(max(1, Int(sampleRate * durationSeconds)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return buffer }
        var rngState: UInt64 = 0xBEEF_CAFE_1234_5678

        func nextRandomSigned() -> Float {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            let unit = Float((rngState >> 33) & 0x7FFF_FFFF) / Float(0x7FFF_FFFF)
            return unit * 2.0 - 1.0
        }

        for ch in 0..<2 {
            let ptr = channelData[ch]
            for i in 0..<Int(frameCount) {
                let norm = Double(i) / Double(frameCount)
                let envelope = pow(1.0 - norm, decay)
                ptr[i] = Float(Double(nextRandomSigned()) * envelope * 0.65)
            }
        }
        return buffer
    }
}
