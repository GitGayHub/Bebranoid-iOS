import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

/// Нативный инспектор аудиофайлов (`electron/main.js` `getAudioMetadata` 1:1).
/// Извлекает точные технические параметры (кодек, контейнер, частоту дискретизации, разрядность `bitsPerSample`,
/// битрейт, количество каналов) и встроенные теги текста песни (`©lyr` / `USLT`) или обложки.
public enum AudioMetadataReader {
    public struct ExtractedFileMetadata: Sendable {
        public var title: String?
        public var artist: String?
        public var album: String?
        public var year: Int?
        public var duration: Double
        public var embeddedLyrics: String?
        public var artworkData: Data?
        public var formatInfo: AudioFormatInfo
    }

    /// Асинхронное чтение полных метаданных локального аудиофайла
    public static func inspectAudioFile(at url: URL) async -> ExtractedFileMetadata {
        let asset = AVURLAsset(url: url)
        let ext = url.pathExtension.lowercased()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil

        var durationSec: Double = 0
        if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            if seconds.isFinite && seconds > 0 {
                durationSec = seconds
            }
        }

        var title: String?
        var artist: String?
        var album: String?
        var year: Int?
        var embeddedLyrics: String?
        var artworkData: Data?

        if let metadataItems = try? await asset.load(.commonMetadata) {
            for item in metadataItems {
                guard let commonKey = item.commonKey else { continue }
                switch commonKey {
                case .commonKeyTitle:
                    title = try? await item.load(.stringValue)
                case .commonKeyArtist, .commonKeyAuthor:
                    artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName:
                    album = try? await item.load(.stringValue)
                case .commonKeyCreationDate:
                    if let dateStr = try? await item.load(.stringValue),
                       let parsedYear = Int(dateStr.prefix(4)) {
                        year = parsedYear
                    }
                case .commonKeyArtwork:
                    artworkData = try? await item.load(.dataValue)
                default:
                    break
                }
            }
        }

        if let assetLyrics = try? await asset.load(.lyrics), !assetLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            embeddedLyrics = assetLyrics
        }

        // Технические параметры аудиодорожки из CMAudioFormatDescription + бинарный заголовок FLAC/WAV
        var codec = ext.uppercased()
        var sampleRate: Int?
        var bitsPerSample: Int?
        var channels: Int?
        var isLossless = ["flac", "wav", "alac", "aiff", "ape"].contains(ext)

        if let tracks = try? await asset.loadTracks(withMediaType: .audio),
           let audioTrack = tracks.first,
           let descriptions = try? await audioTrack.load(.formatDescriptions),
           let firstDesc = descriptions.first {
            let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(firstDesc)
            if let asbd = asbdPtr?.pointee {
                if asbd.mSampleRate > 0 {
                    sampleRate = Int(round(asbd.mSampleRate))
                }
                if asbd.mChannelsPerFrame > 0 {
                    channels = Int(asbd.mChannelsPerFrame)
                }
                if asbd.mBitsPerChannel > 0 {
                    bitsPerSample = Int(asbd.mBitsPerChannel)
                }

                let formatID = asbd.mFormatID
                switch formatID {
                case kAudioFormatFLAC:
                    codec = "FLAC"
                    isLossless = true
                case kAudioFormatAppleLossless:
                    codec = "ALAC"
                    isLossless = true
                case kAudioFormatLinearPCM:
                    codec = ext == "aiff" ? "AIFF" : "WAV"
                    isLossless = true
                case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2:
                    codec = "AAC"
                    isLossless = false
                case kAudioFormatMPEGLayer3:
                    codec = "MP3"
                    isLossless = false
                case kAudioFormatOpus:
                    codec = "OPUS"
                    isLossless = false
                default:
                    break
                }
            }
        }

        // Дополнительный бинарный парсинг заголовка FLAC / WAV для гарантированного определения 24-bit / 96kHz Hi-Res
        if ext == "flac", let headerInfo = parseFlacStreamInfo(at: url) {
            codec = "FLAC"
            isLossless = true
            sampleRate = headerInfo.sampleRate
            bitsPerSample = headerInfo.bitsPerSample
            channels = headerInfo.channels
            if durationSec <= 0 && headerInfo.duration > 0 {
                durationSec = headerInfo.duration
            }
        } else if ext == "wav", let wavInfo = parseWavHeader(at: url) {
            codec = "WAV"
            isLossless = true
            sampleRate = wavInfo.sampleRate
            bitsPerSample = wavInfo.bitsPerSample
            channels = wavInfo.channels
        }

        let bitrateKbps: Int? = {
            guard let size = fileSize, size > 0, durationSec > 0.5 else { return nil }
            return Int(round((Double(size) * 8.0) / durationSec / 1000.0))
        }()

        let formatInfo = AudioFormatInfo(
            codec: codec,
            container: ext.uppercased(),
            bitrateKbps: bitrateKbps,
            sampleRateHz: sampleRate,
            bitsPerSample: bitsPerSample,
            channels: channels,
            lossless: isLossless
        )

        return ExtractedFileMetadata(
            title: title,
            artist: artist,
            album: album,
            year: year,
            duration: durationSec,
            embeddedLyrics: embeddedLyrics,
            artworkData: artworkData,
            formatInfo: formatInfo
        )
    }

    /// Парсинг блока `STREAMINFO` из заголовка `.flac` файла (согласно спецификации FLAC)
    public static func parseFlacStreamInfo(at url: URL) -> (sampleRate: Int, channels: Int, bitsPerSample: Int, duration: Double)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 42), data.count >= 42 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 else { return nil }

        let b18 = UInt32(bytes[18])
        let b19 = UInt32(bytes[19])
        let b20 = UInt32(bytes[20])
        let b21 = UInt32(bytes[21])

        let sampleRate = Int((b18 << 12) | (b19 << 4) | (b20 >> 4))
        let channels = Int(((b20 >> 1) & 0x07) + 1)
        let bps = Int((((b20 & 0x01) << 4) | (b21 >> 4)) + 1)

        let totalSamplesHigh = UInt64(b21 & 0x0F) << 32
        let totalSamplesLow = (UInt64(bytes[22]) << 24) | (UInt64(bytes[23]) << 16) | (UInt64(bytes[24]) << 8) | UInt64(bytes[25])
        let totalSamples = totalSamplesHigh | totalSamplesLow
        let duration = sampleRate > 0 ? Double(totalSamples) / Double(sampleRate) : 0.0

        guard sampleRate > 0 else { return nil }
        return (sampleRate, channels, bps, duration)
    }

    /// Парсинг блока `fmt ` из заголовка `.wav` файла
    public static func parseWavHeader(at url: URL) -> (sampleRate: Int, channels: Int, bitsPerSample: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 44), data.count >= 44 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
              bytes[8] == 0x57, bytes[9] == 0x41, bytes[10] == 0x56, bytes[11] == 0x45 else {
            return nil
        }

        let channels = Int(UInt16(bytes[22]) | (UInt16(bytes[23]) << 8))
        let sampleRate = Int(UInt32(bytes[24]) | (UInt32(bytes[25]) << 8) | (UInt32(bytes[26]) << 16) | (UInt32(bytes[27]) << 24))
        let bps = Int(UInt16(bytes[34]) | (UInt16(bytes[35]) << 8))
        guard sampleRate > 0, channels > 0 else { return nil }
        return (sampleRate, channels, bps > 0 ? bps : 16)
    }
}
