import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

/// Нативный инспектор аудиофайлов (`electron/main.js` `getAudioMetadata` и `extractCoverFromAudio` 1:1).
/// Извлекает точные технические параметры (кодек, контейнер, частоту дискретизации, разрядность `bitsPerSample`,
/// битрейт, количество каналов), встроенные теги текста песни (`©lyr` / `USLT`) и встроенные бинарные обложки:
/// - FLAC `METADATA_BLOCK_PICTURE` (block type 6)
/// - MP3 `ID3v2 APIC` / `PIC` (v2.2 / v2.3 / v2.4)
/// - M4A / MP4 / ALAC `covr` atom (`moov -> udta -> meta -> ilst -> covr -> data`)
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

        if artworkData == nil {
            artworkData = extractEmbeddedArtworkSync(from: url)
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
            if durationSec <= 0 && wavInfo.duration > 0 {
                durationSec = wavInfo.duration
            }
        }

        // Точное чтение параметров CoreAudio `.caf` (например, ремукс YouTube Opus 48 kHz `itag 251`) через AVAudioFile
        if (sampleRate == nil || durationSec <= 0 || ext == "caf"),
           let avFile = try? AVAudioFile(forReading: url) {
            let asbd = avFile.fileFormat.streamDescription.pointee
            if asbd.mSampleRate > 0 {
                sampleRate = Int(round(asbd.mSampleRate))
            }
            if asbd.mChannelsPerFrame > 0 {
                channels = Int(asbd.mChannelsPerFrame)
            }
            if asbd.mFormatID == kAudioFormatOpus {
                codec = "OPUS"
                isLossless = false
            } else if asbd.mFormatID == kAudioFormatMPEG4AAC {
                codec = "AAC"
                isLossless = false
            }
            if durationSec <= 0 && avFile.processingFormat.sampleRate > 0 && avFile.length > 0 {
                durationSec = Double(avFile.length) / avFile.processingFormat.sampleRate
            }
        }

        let bitrateKbps: Int? = {
            guard let size = fileSize, size > 0, durationSec > 0.05 else { return nil }
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

    // MARK: - Binary Embedded Artwork Parsers (FLAC, MP3 ID3v2 APIC, MP4/M4A/ALAC covr)

    /// Синхронное извлечение встроенной обложки из локального аудиофайла (`.flac`, `.mp3`, `.m4a`, `.mp4`, `.alac`, `.wav`)
    public static func extractEmbeddedArtworkSync(from url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let ext = url.pathExtension.lowercased()

        // Читаем первые 8 МБ файла (встроенные обложки находятся в метаданных заголовка/контейнера)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let headData = try? handle.read(upToCount: 8 * 1024 * 1024), !headData.isEmpty else {
            return nil
        }

        if let parsed = extractEmbeddedArtwork(from: headData, pathExtension: ext) {
            return parsed
        }

        // Если MP4 moov атом расположен в конце файла, читаем файл целиком (если размер <= 64 МБ)
        if ["m4a", "mp4", "alac", "aac"].contains(ext),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64,
           size > Int64(headData.count) && size <= 64 * 1024 * 1024,
           let fullData = try? Data(contentsOf: url, options: .mappedIfSafe) {
            return extractMP4CovrAtom(from: fullData)
        }

        return nil
    }

    /// Извлекает встроенную обложку из бинарного буфера аудиофайла по сигнатуре или расширению
    public static func extractEmbeddedArtwork(from data: Data, pathExtension: String? = nil) -> Data? {
        guard data.count >= 12 else { return nil }
        let ext = (pathExtension ?? "").lowercased()

        // 1. FLAC ("fLaC" = 0x66 0x4C 0x61 0x43)
        if ext == "flac" || (data[0] == 0x66 && data[1] == 0x4C && data[2] == 0x61 && data[3] == 0x43) {
            if let pic = extractFLACPicture(from: data) {
                return pic
            }
        }

        // 2. MP3 / ID3v2 ("ID3" = 0x49 0x44 0x33)
        if ext == "mp3" || (data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) {
            if let apic = extractID3v2APIC(from: data) {
                return apic
            }
        }

        // 3. MP4 / M4A / ALAC ("ftyp" на смещении 4..8)
        if ["m4a", "mp4", "alac", "aac"].contains(ext) ||
            (data.count >= 8 && data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70) {
            if let covr = extractMP4CovrAtom(from: data) {
                return covr
            }
        }

        return nil
    }

    /// Парсинг `METADATA_BLOCK_PICTURE` (block type 6) из FLAC-контейнера согласно спецификации RFC 9639
    public static func extractFLACPicture(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8,
              bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 else {
            return nil
        }

        var offset = 4
        while offset + 4 <= bytes.count {
            let headerByte = bytes[offset]
            let isLast = (headerByte & 0x80) != 0
            let blockType = headerByte & 0x7F
            let blockLength = (Int(bytes[offset + 1]) << 16) | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            offset += 4

            guard blockLength >= 0, offset + blockLength <= bytes.count else {
                break
            }

            if blockType == 6 {
                // METADATA_BLOCK_PICTURE:
                // [0..4] pictureType
                // [4..8] mimeLength -> mime bytes
                // [..]   descLength -> desc bytes
                // [..]   width (4), height (4), depth (4), colors (4)
                // [..]   dataLength (4) -> picture bytes
                var p = offset
                let blockEnd = offset + blockLength
                guard p + 8 <= blockEnd else { break }
                p += 4 // pictureType
                let mimeLen = readUInt32BE(bytes, at: p)
                p += 4 + mimeLen
                guard p + 4 <= blockEnd else { break }
                let descLen = readUInt32BE(bytes, at: p)
                p += 4 + descLen
                guard p + 20 <= blockEnd else { break }
                p += 16 // width, height, colorDepth, indexedColors
                let picLen = readUInt32BE(bytes, at: p)
                p += 4
                guard picLen > 0, p + picLen <= blockEnd else { break }
                return Data(bytes[p..<(p + picLen)])
            }

            offset += blockLength
            if isLast { break }
        }
        return nil
    }

    /// Парсинг тега `ID3v2` (`APIC` в v2.3/v2.4 и `PIC` в v2.2) из MP3-файлов
    public static func extractID3v2APIC(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 10,
              bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else {
            return nil
        }

        let versionMajor = bytes[3]
        let flags = bytes[5]
        let tagSize = readSynchsafeUInt32(bytes, at: 6)
        let tagEnd = min(bytes.count, 10 + tagSize)
        var offset = 10

        // Пропускаем Extended Header, если установлен бит 0x40
        if (flags & 0x40) != 0, offset + 4 <= tagEnd {
            let extSize = versionMajor == 4 ? readSynchsafeUInt32(bytes, at: offset) : readUInt32BE(bytes, at: offset)
            offset += (versionMajor == 4 ? extSize : (extSize + 4))
        }

        if versionMajor == 2 {
            // ID3v2.2: 3-байтный ID фрейма ("PIC") + 3-байтный размер
            while offset + 6 <= tagEnd {
                if bytes[offset] == 0 { break }
                let id0 = bytes[offset], id1 = bytes[offset + 1], id2 = bytes[offset + 2]
                let fSize = (Int(bytes[offset + 3]) << 16) | (Int(bytes[offset + 4]) << 8) | Int(bytes[offset + 5])
                offset += 6
                guard fSize > 0, offset + fSize <= tagEnd else { break }
                if id0 == 0x50 && id1 == 0x49 && id2 == 0x43 { // "PIC"
                    if let img = extractImagePayloadFromAPICFrame(Array(bytes[offset..<(offset + fSize)]), isV22: true) {
                        return img
                    }
                }
                offset += fSize
            }
        } else {
            // ID3v2.3 / ID3v2.4: 4-байтный ID ("APIC") + 4-байтный размер + 2 байта флагов
            while offset + 10 <= tagEnd {
                if bytes[offset] == 0 { break }
                let isAPIC = bytes[offset] == 0x41 && bytes[offset + 1] == 0x50 && bytes[offset + 2] == 0x49 && bytes[offset + 3] == 0x43
                let fSize: Int = {
                    if versionMajor == 4 {
                        let synch = readSynchsafeUInt32(bytes, at: offset + 4)
                        if synch > 0 && offset + 10 + synch <= tagEnd { return synch }
                    }
                    return readUInt32BE(bytes, at: offset + 4)
                }()
                let fFlags2 = bytes[offset + 9]
                offset += 10
                guard fSize > 0, offset + fSize <= tagEnd else { break }

                if isAPIC {
                    var frameSlice = Array(bytes[offset..<(offset + fSize)])
                    // Если установлен Data Length Indicator (бит 0x01 во втором байте флагов v2.4), пропускаем 4 байта
                    if versionMajor == 4 && (fFlags2 & 0x01) != 0 && frameSlice.count > 4 {
                        frameSlice.removeFirst(4)
                    }
                    if let img = extractImagePayloadFromAPICFrame(frameSlice, isV22: false) {
                        return img
                    }
                }
                offset += fSize
            }
        }
        return nil
    }

    private static func extractImagePayloadFromAPICFrame(_ frame: [UInt8], isV22: Bool) -> Data? {
        guard frame.count > 8 else { return nil }
        let encoding = frame[0]
        var idx = 1

        if isV22 {
            // 3-байтный формат ("JPG" / "PNG")
            idx += 3
        } else {
            // Null-terminated MIME string (например "image/jpeg\0")
            while idx < frame.count && frame[idx] != 0 {
                idx += 1
            }
            idx += 1 // пропускаем 0x00
        }

        guard idx < frame.count else { return nil }
        idx += 1 // пропускаем pictureType (1 байт)

        // Пропускаем текстовое описание (null-terminated в зависимости от encoding: 0/3 -> 1 байт 0x00, 1/2 -> 2 байта 0x00 0x00)
        if encoding == 1 || encoding == 2 {
            while idx + 1 < frame.count {
                if frame[idx] == 0 && frame[idx + 1] == 0 {
                    idx += 2
                    break
                }
                idx += 2
            }
        } else {
            while idx < frame.count && frame[idx] != 0 {
                idx += 1
            }
            idx += 1
        }

        if idx < frame.count {
            let candidate = Array(frame[idx...])
            if isLikelyImageHeader(candidate) {
                return Data(candidate)
            }
        }

        // Резервный поиск сигнатуры JPEG (FF D8 FF) или PNG (89 50 4E 47) внутри APIC фрейма
        return scanForEmbeddedImageSignature(in: frame)
    }

    /// Парсинг атома `covr` (`moov -> udta -> meta -> ilst -> covr -> data`) из MP4 / M4A / ALAC файлов
    public static func extractMP4CovrAtom(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        if let found = searchMP4BoxesForCovr(bytes, start: 0, end: bytes.count) {
            return found
        }
        return nil
    }

    private static func searchMP4BoxesForCovr(_ bytes: [UInt8], start: Int, end: Int) -> Data? {
        var offset = start
        let containerTypes: Set<String> = ["moov", "udta", "meta", "ilst", "covr"]

        while offset + 8 <= end {
            var boxSize = readUInt32BE(bytes, at: offset)
            let typeBytes = [bytes[offset + 4], bytes[offset + 5], bytes[offset + 6], bytes[offset + 7]]
            let boxType = String(bytes: typeBytes, encoding: .isoLatin1) ?? ""
            var headerSize = 8

            if boxSize == 1 {
                guard offset + 16 <= end else { break }
                let high = UInt64(readUInt32BE(bytes, at: offset + 8))
                let low = UInt64(readUInt32BE(bytes, at: offset + 12))
                let size64 = (high << 32) | low
                guard size64 <= UInt64(end - offset) else { break }
                boxSize = Int(size64)
                headerSize = 16
            } else if boxSize == 0 {
                boxSize = end - offset
            }

            guard boxSize >= headerSize, offset + boxSize <= end else {
                break
            }

            let boxEnd = offset + boxSize
            if boxType == "covr" {
                if let img = extractDataBoxInsideCovr(bytes, start: offset + headerSize, end: boxEnd) {
                    return img
                }
            } else if containerTypes.contains(boxType) {
                let childStart = (boxType == "meta") ? min(boxEnd, offset + headerSize + 4) : (offset + headerSize)
                if let found = searchMP4BoxesForCovr(bytes, start: childStart, end: boxEnd) {
                    return found
                }
            }

            offset = boxEnd
        }
        return nil
    }

    private static func extractDataBoxInsideCovr(_ bytes: [UInt8], start: Int, end: Int) -> Data? {
        var offset = start
        while offset + 16 <= end {
            let boxSize = readUInt32BE(bytes, at: offset)
            let typeBytes = [bytes[offset + 4], bytes[offset + 5], bytes[offset + 6], bytes[offset + 7]]
            let boxType = String(bytes: typeBytes, encoding: .isoLatin1) ?? ""
            guard boxSize >= 16, offset + boxSize <= end else { break }
            if boxType == "data" {
                // Внутри атома `data` первые 8 байт после заголовка — type indicator (4) + locale (4), далее идут байты изображения
                let payloadStart = offset + 16
                let payloadEnd = offset + boxSize
                if payloadStart < payloadEnd {
                    return Data(bytes[payloadStart..<payloadEnd])
                }
            }
            offset += boxSize
        }
        if start < end {
            let slice = Array(bytes[start..<end])
            if let scanned = scanForEmbeddedImageSignature(in: slice) {
                return scanned
            }
        }
        return nil
    }

    private static func isLikelyImageHeader(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 4 else { return false }
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF { return true }
        // PNG: 89 50 4E 47
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 { return true }
        // WebP: "RIFF"...."WEBP"
        if bytes.count >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
            bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return true
        }
        return false
    }

    private static func scanForEmbeddedImageSignature(in bytes: [UInt8]) -> Data? {
        guard bytes.count > 12 else { return nil }
        for i in 0..<(bytes.count - 4) {
            if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) ||
               (bytes[i] == 0x89 && bytes[i + 1] == 0x50 && bytes[i + 2] == 0x4E && bytes[i + 3] == 0x47) {
                return Data(bytes[i...])
            }
        }
        return nil
    }

    private static func readUInt32BE(_ bytes: [UInt8], at offset: Int) -> Int {
        guard offset + 4 <= bytes.count else { return 0 }
        return (Int(bytes[offset]) << 24) |
               (Int(bytes[offset + 1]) << 16) |
               (Int(bytes[offset + 2]) << 8) |
               Int(bytes[offset + 3])
    }

    private static func readSynchsafeUInt32(_ bytes: [UInt8], at offset: Int) -> Int {
        guard offset + 4 <= bytes.count else { return 0 }
        return (Int(bytes[offset] & 0x7F) << 21) |
               (Int(bytes[offset + 1] & 0x7F) << 14) |
               (Int(bytes[offset + 2] & 0x7F) << 7) |
               Int(bytes[offset + 3] & 0x7F)
    }

    // MARK: - Binary Audio Stream Header Parsers (FLAC / WAV)

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

    /// Парсинг блока `fmt ` и размера данных из заголовка `.wav` файла
    public static func parseWavHeader(at url: URL) -> (sampleRate: Int, channels: Int, bitsPerSample: Int, duration: Double)? {
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
        let byteRate = Int(UInt32(bytes[28]) | (UInt32(bytes[29]) << 8) | (UInt32(bytes[30]) << 16) | (UInt32(bytes[31]) << 24))
        let bps = Int(UInt16(bytes[34]) | (UInt16(bytes[35]) << 8))
        let dataChunkSize = Int(UInt32(bytes[40]) | (UInt32(bytes[41]) << 8) | (UInt32(bytes[42]) << 16) | (UInt32(bytes[43]) << 24))
        guard sampleRate > 0, channels > 0 else { return nil }
        let duration = byteRate > 0 ? Double(max(0, dataChunkSize)) / Double(byteRate) : 0.0
        return (sampleRate, channels, bps > 0 ? bps : 16, duration)
    }
}
