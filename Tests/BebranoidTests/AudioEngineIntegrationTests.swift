import XCTest
import AVFoundation
@testable import Bebranoid

final class AudioEngineIntegrationTests: XCTestCase {

    // MARK: - Helpers: Real Audio File Generation (WAV, M4A AAC, M4A ALAC, FLAC)

    private func writePlayableWAV(to url: URL, frequencyHz: Double = 440.0, durationSeconds: Double = 4.0, sampleRate: Double = 44100.0) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            XCTFail("Не удалось создать формат WAV")
            return
        }
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Не удалось создать буфер PCM")
            return
        }
        buffer.frameLength = frameCount

        if let chData = buffer.int16ChannelData {
            for ch in 0..<2 {
                let ptr = chData[ch]
                let freq = frequencyHz * (ch == 0 ? 1.0 : 1.25)
                for i in 0..<Int(frameCount) {
                    let t = Double(i) / sampleRate
                    ptr[i] = Int16(sin(2.0 * .pi * freq * t) * 12000.0)
                }
            }
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: false)
        try audioFile.write(from: buffer)
    }

    private func writePlayableM4A_ALAC(to url: URL, durationSeconds: Double = 3.0, sampleRate: Double = 44100.0) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitDepthHintKey: 16
        ]
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let pcmFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        if let floatData = buffer.floatChannelData {
            for ch in 0..<2 {
                let ptr = floatData[ch]
                for i in 0..<Int(frameCount) {
                    let t = Double(i) / sampleRate
                    ptr[i] = Float(sin(2.0 * .pi * 330.0 * t) * 0.35)
                }
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    private func writePlayableM4A_AAC(to url: URL, durationSeconds: Double = 3.0, sampleRate: Double = 44100.0) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let pcmFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        if let floatData = buffer.floatChannelData {
            for ch in 0..<2 {
                let ptr = floatData[ch]
                for i in 0..<Int(frameCount) {
                    let t = Double(i) / sampleRate
                    ptr[i] = Float(sin(2.0 * .pi * 520.0 * t) * 0.35)
                }
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    private func writePlayableFLAC(to url: URL, durationSeconds: Double = 3.0, sampleRate: Double = 44100.0) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16
        ]
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let pcmFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
            XCTFail("Не удалось создать буфер PCM для FLAC")
            return
        }
        buffer.frameLength = frameCount
        if let floatData = buffer.floatChannelData {
            for ch in 0..<2 {
                let ptr = floatData[ch]
                let freq = ch == 0 ? 440.0 : 554.37
                for i in 0..<Int(frameCount) {
                    let t = Double(i) / sampleRate
                    ptr[i] = Float(sin(2.0 * .pi * freq * t) * 0.4)
                }
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    /// Генерирует настоящий воспроизводимый поток MPEG-1 Audio Layer III (44.1 кГц, 128 кбит/с, стерео,
    /// `main_data_begin = 0` без битового резервуара, гармонический тон 344.53 Гц) из самодостаточных фреймов.
    private func writePlayableMP3(to url: URL, durationSeconds: Double = 3.0) throws {
        let selfContainedMP3FrameBase64 =
            "//uSZAAP8XNhwILgUxAAAA0gAAABBc2HAguBTEAAADSAAAAE8D6yhgj/JOX/xD/5J/i3/i3/iI//+Kn+Kn//zP8p/iR/jD/X/X/T/CV/kX+PfV4H1ljBP+SEt/iE/yf/Fj/Fj/EX//8V/8V///n/5X/Ev/Gf+n+n+v+En/If8fetMQU1FMy4xMDEgKGJldGEgMykAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
        guard let singleFrame = Data(base64Encoded: selfContainedMP3FrameBase64), singleFrame.count == 418 else {
            XCTFail("Не удалось декодировать эталонный MPEG-1 Layer III фрейм")
            return
        }
        // Каждый фрейм MPEG-1 Layer III содержит 1152 сэмпла (1152 / 44100 ≈ 0.02612245 с)
        let frameCount = max(10, Int(round(durationSeconds * 44100.0 / 1152.0)))
        var mp3Data = Data(capacity: singleFrame.count * frameCount)
        for _ in 0..<frameCount {
            mp3Data.append(singleFrame)
        }
        try mp3Data.write(to: url, options: .atomic)
    }

    private func decodeAndComputeRMS(at url: URL, maxFrames: AVAudioFrameCount = 32_768) throws -> (framesDecoded: AVAudioFrameCount, rms: Float, sampleRate: Double, channels: AVAudioChannelCount) {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let framesToRead = min(maxFrames, AVAudioFrameCount(max(0, audioFile.length)))
        guard framesToRead > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
            return (0, 0.0, format.sampleRate, format.channelCount)
        }
        try audioFile.read(into: pcmBuffer, frameCount: framesToRead)
        guard pcmBuffer.frameLength > 0, let channelData = pcmBuffer.floatChannelData else {
            return (pcmBuffer.frameLength, 0.0, format.sampleRate, format.channelCount)
        }
        let samplesCount = Int(pcmBuffer.frameLength)
        var sumSquares: Double = 0.0
        for i in 0..<samplesCount {
            let s = Double(channelData[0][i])
            sumSquares += s * s
        }
        let rms = Float(sqrt(sumSquares / Double(max(1, samplesCount))))
        return (pcmBuffer.frameLength, rms, format.sampleRate, format.channelCount)
    }

    // MARK: - 1. Multi-Format Inspection & Decoding (WAV, M4A ALAC, M4A AAC, FLAC, MP3)

    @MainActor
    func testMultiFormatAudioInspectionAndDecoding() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("audio_formats_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1) WAV (PCM Lossless)
        let wavURL = tempDir.appendingPathComponent("test_pcm.wav")
        try writePlayableWAV(to: wavURL, durationSeconds: 3.0)
        let wavMeta = await AudioMetadataReader.inspectAudioFile(at: wavURL)
        XCTAssertEqual(wavMeta.duration, 3.0, accuracy: 0.15)
        XCTAssertTrue(wavMeta.formatInfo.lossless)
        let wavDecoded = try decodeAndComputeRMS(at: wavURL)
        XCTAssertGreaterThan(wavDecoded.framesDecoded, 10_000)
        XCTAssertGreaterThan(wavDecoded.rms, 0.1)

        // 2) M4A (ALAC Lossless)
        let alacURL = tempDir.appendingPathComponent("test_lossless.m4a")
        try writePlayableM4A_ALAC(to: alacURL, durationSeconds: 3.0)
        let alacMeta = await AudioMetadataReader.inspectAudioFile(at: alacURL)
        XCTAssertEqual(alacMeta.duration, 3.0, accuracy: 0.25)
        XCTAssertTrue(alacMeta.formatInfo.lossless)
        let alacDecoded = try decodeAndComputeRMS(at: alacURL)
        XCTAssertGreaterThan(alacDecoded.framesDecoded, 10_000)
        XCTAssertGreaterThan(alacDecoded.rms, 0.1)

        // 3) M4A (AAC)
        let aacURL = tempDir.appendingPathComponent("test_aac.m4a")
        try writePlayableM4A_AAC(to: aacURL, durationSeconds: 3.0)
        let aacMeta = await AudioMetadataReader.inspectAudioFile(at: aacURL)
        XCTAssertEqual(aacMeta.duration, 3.0, accuracy: 0.25)
        XCTAssertFalse(aacMeta.formatInfo.lossless)
        let aacDecoded = try decodeAndComputeRMS(at: aacURL)
        XCTAssertGreaterThan(aacDecoded.framesDecoded, 10_000)
        XCTAssertGreaterThan(aacDecoded.rms, 0.1)

        // 4) FLAC (Real Lossless Audio Encoding, Binary STREAMINFO Inspection, PCM Decoding & DualStreamAudioEngine Load)
        let flacURL = tempDir.appendingPathComponent("01_HiRes.flac")
        try writePlayableFLAC(to: flacURL, durationSeconds: 3.0, sampleRate: 44100.0)
        let flacMeta = await AudioMetadataReader.inspectAudioFile(at: flacURL)
        XCTAssertTrue(flacMeta.formatInfo.lossless)
        XCTAssertEqual(flacMeta.formatInfo.codec, "FLAC")
        XCTAssertEqual(flacMeta.formatInfo.sampleRateHz, 44100)
        XCTAssertEqual(flacMeta.duration, 3.0, accuracy: 0.25)

        let flacDecoded = try decodeAndComputeRMS(at: flacURL)
        XCTAssertGreaterThan(flacDecoded.framesDecoded, 10_000)
        XCTAssertGreaterThan(flacDecoded.rms, 0.15)
        XCTAssertEqual(flacDecoded.sampleRate, 44100.0, accuracy: 1.0)
        XCTAssertEqual(flacDecoded.channels, 2)

        let engine = DualStreamAudioEngine()
        let flacTrack = Track(id: "fmt:flac", title: "Real FLAC Decode", artist: "QA", album: "Lossless", duration: 3.0, filename: "01_HiRes.flac")
        await engine.loadAndPlay(track: flacTrack, fileURL: flacURL, startAt: 0.0, autoPlay: false)
        XCTAssertEqual(engine.duration, 3.0, accuracy: 0.25)
        XCTAssertEqual(engine.currentFormatInfo?.codec, "FLAC")
        XCTAssertEqual(engine.currentFormatInfo?.lossless, true)

        // 5) MP3 (Real MPEG-1 Layer III Audio Stream Inspection, PCM Decoding & DualStreamAudioEngine Load)
        let mp3URL = tempDir.appendingPathComponent("02_Song.mp3")
        try writePlayableMP3(to: mp3URL, durationSeconds: 3.0)
        let mp3Meta = await AudioMetadataReader.inspectAudioFile(at: mp3URL)
        XCTAssertFalse(mp3Meta.formatInfo.lossless)
        XCTAssertEqual(mp3Meta.formatInfo.codec, "MP3")
        XCTAssertEqual(mp3Meta.formatInfo.sampleRateHz, 44100)
        XCTAssertEqual(mp3Meta.duration, 3.0, accuracy: 0.25)

        let mp3Decoded = try decodeAndComputeRMS(at: mp3URL)
        XCTAssertGreaterThan(mp3Decoded.framesDecoded, 10_000)
        XCTAssertGreaterThan(mp3Decoded.rms, 0.02)
        XCTAssertEqual(mp3Decoded.sampleRate, 44100.0, accuracy: 1.0)
        XCTAssertEqual(mp3Decoded.channels, 2)

        let mp3Track = Track(id: "fmt:mp3", title: "Real MP3 Decode", artist: "QA", album: "MPEG", duration: 3.0, filename: "02_Song.mp3")
        await engine.loadAndPlay(track: mp3Track, fileURL: mp3URL, startAt: 0.0, autoPlay: false)
        XCTAssertEqual(engine.duration, 3.0, accuracy: 0.25)
        XCTAssertEqual(engine.currentFormatInfo?.codec, "MP3")
        XCTAssertEqual(engine.currentFormatInfo?.lossless, false)
        engine.pause()
    }

    // MARK: - 2. DualStreamAudioEngine Load, Play, Pause, Seek, VolumeCurve & Audio FX

    @MainActor
    func testDualStreamEnginePlaybackSeekAndAudioFX() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("engine_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wavURL = tempDir.appendingPathComponent("engine_track1.wav")
        try writePlayableWAV(to: wavURL, frequencyHz: 440.0, durationSeconds: 8.0)

        let track = Track(
            id: "engine:1",
            title: "Engine Test Track",
            artist: "QA Synth",
            album: "Integration Suite",
            duration: 8.0,
            filename: "engine_track1.wav"
        )

        let engine = DualStreamAudioEngine()
        await engine.loadAndPlay(track: track, fileURL: wavURL, startAt: 0.0, autoPlay: true)
        XCTAssertEqual(engine.duration, 8.0, accuracy: 0.2)
        XCTAssertNotNil(engine.currentFormatInfo)

        // Тест Seek
        engine.seek(to: 3.25)
        XCTAssertEqual(engine.currentTime, 3.25, accuracy: 0.1)

        // Тест Pause / Play
        engine.pause()
        XCTAssertFalse(engine.isPlaying)
        engine.play()
        XCTAssertTrue(engine.isPlaying)

        // Тест AudioFXMode: normal -> slowed -> slowedReverb -> speedup -> bassBoost
        engine.audioFXMode = .normal
        engine.playbackSpeed = 1.0
        XCTAssertEqual(engine.effectivePlaybackRate, 1.0, accuracy: 0.001)

        engine.audioFXMode = .slowed
        XCTAssertEqual(engine.effectivePlaybackRate, AudioFXMode.slowed.defaultRateMultiplier, accuracy: 0.001)

        engine.audioFXMode = .slowedReverb
        XCTAssertTrue(engine.audioFXMode.usesReverb)
        XCTAssertEqual(engine.effectivePlaybackRate, AudioFXMode.slowedReverb.defaultRateMultiplier, accuracy: 0.001)

        engine.audioFXMode = .speedup
        XCTAssertEqual(engine.effectivePlaybackRate, AudioFXMode.speedup.defaultRateMultiplier, accuracy: 0.001)

        engine.bassBoostEnabled = true
        let chain = DeckAudioFXChain()
        chain.applyParameters(fxMode: .slowedReverb, userPlaybackSpeed: 1.0, bassBoostEnabled: true)
        XCTAssertEqual(chain.eqUnit.bands[0].gain, 8.0, accuracy: 0.01)
        XCTAssertFalse(chain.eqUnit.bands[0].bypass)
        XCTAssertFalse(chain.eqUnit.bands[1].bypass)
        XCTAssertGreaterThan(chain.reverbUnit.wetDryMix, 20.0)

        // Проверяем синтетический 2.8s импульсный отклик
        let irBuffer = DeckAudioFXChain.generateSyntheticImpulseResponse(sampleRate: 44100.0, durationSeconds: 2.8)
        XCTAssertNotNil(irBuffer)
        XCTAssertEqual(irBuffer?.frameLength, AVAudioFrameCount(44100.0 * 2.8))

        // Проверяем VolumeCurve u^2.75
        XCTAssertEqual(VolumeCurve.uiToGain(0.0), 0.0, accuracy: 1e-6)
        XCTAssertEqual(VolumeCurve.uiToGain(1.0), 1.0, accuracy: 1e-6)
        XCTAssertEqual(VolumeCurve.uiToGain(0.5), pow(0.5, 2.75), accuracy: 1e-6)

        engine.pause()
    }

    // MARK: - 3. Queue Order, Next/Previous, Shuffle, Repeat & Lyrics Time Sync

    @MainActor
    func testAppStateQueueNavigationShuffleRepeatAndLyricsSync() async throws {
        let appState = BebranoidAppState()
        let t1 = Track(id: "q:1", title: "Track One", artist: "Artist A", album: "Album 1", duration: 120, filename: "t1.wav")
        let t2 = Track(id: "q:2", title: "Track Two", artist: "Artist B", album: "Album 1", duration: 140, filename: "t2.wav")
        let t3 = Track(id: "q:3", title: "Track Three", artist: "Artist C", album: "Album 2", duration: 160, filename: "t3.wav")

        // Засеиваем реальные WAV-файлы в кеш, чтобы старт треков не обращался в сеть
        for (i, t) in [t1, t2, t3].enumerated() {
            let url = appState.storage.cachedAudioFileURL(for: t)
            try writePlayableWAV(to: url, frequencyHz: 300.0 + Double(i) * 80.0, durationSeconds: 2.0)
            appState.cacheIndex.registerCachedFile(for: t, fileURL: url)
        }

        appState.libraryState.tracks = [t1, t2, t3]
        appState.isShuffleEnabled = false
        appState.repeatMode = .none
        appState.playTrack(t1, in: [t1, t2, t3])

        XCTAssertEqual(appState.currentTrack?.id, "q:1")
        XCTAssertEqual(appState.currentIndex, 0)

        // Next -> Track Two
        appState.skipToNext(isManualUserAction: true)
        XCTAssertEqual(appState.currentTrack?.id, "q:2")
        XCTAssertEqual(appState.currentIndex, 1)

        // Previous (при currentTime < 3.5s) -> Track One
        appState.currentTime = 1.0
        appState.skipToPrevious()
        XCTAssertEqual(appState.currentTrack?.id, "q:1")
        XCTAssertEqual(appState.currentIndex, 0)

        // Repeat cycling: .none -> .all -> .one -> .none
        XCTAssertEqual(appState.repeatMode, .none)
        appState.cycleRepeatMode()
        XCTAssertEqual(appState.repeatMode, .all)
        appState.cycleRepeatMode()
        XCTAssertEqual(appState.repeatMode, .one)
        appState.cycleRepeatMode()
        XCTAssertEqual(appState.repeatMode, .none)

        // Shuffle toggle сохраняет текущий трек на текущем индексе
        appState.toggleShuffle()
        XCTAssertTrue(appState.isShuffleEnabled)
        XCTAssertEqual(appState.queue[appState.currentIndex].id, "q:1")
        appState.toggleShuffle()
        XCTAssertFalse(appState.isShuffleEnabled)
        XCTAssertEqual(appState.queue.map(\.id), ["q:1", "q:2", "q:3"])

        // Синхронизация Lyrics по времени
        let lrcText = """
        [00:10.00] <00:10.00>First <00:12.00>synced <00:14.00>line
        [00:20.00] <00:20.00>Second <00:22.50>chorus <00:25.00>wave
        [00:30.00] <00:30.00>Third <00:32.00>outro <00:35.00>glow
        """
        let doc = LRCParser.parseLRC(lrcText)
        XCTAssertEqual(doc.lines.count, 3)
        XCTAssertEqual(LRCParser.findActiveLineIndex(lines: doc.lines, currentTime: 13.5), 0)
        XCTAssertEqual(LRCParser.findActiveLineIndex(lines: doc.lines, currentTime: 23.0), 1)
        XCTAssertEqual(LRCParser.findActiveLineIndex(lines: doc.lines, currentTime: 33.0), 2)
        if let firstWords = doc.lines[0].words {
            XCTAssertEqual(LRCParser.findActiveWordIndex(words: firstWords, currentTime: 12.5), 1)
        }

        appState.audioEngine.pause()
    }
}
