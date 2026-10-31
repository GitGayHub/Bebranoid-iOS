import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Беспотерьный (bit-exact, 0% перекодирования) ремуксер контейнера YouTube `audio/webm; codecs="opus"` (`itag 251` 48 kHz)
/// в нативный контейнер Apple CoreAudio `.caf` (`kAudioFormatOpus`), напрямую поддерживаемый `AVAudioFile` и `AVAudioEngine`.
public enum WebMOpusRemuxer {
    public struct DemuxedOpusStream: Sendable {
        public let channels: Int
        public let preSkip: Int
        public let packets: [Data]
        public let packetFrameCounts: [Int]
        public let totalSamples48k: Int
    }

    /// Извлекает сырые RFC 6716 Opus-пакеты и параметры `OpusHead` из WebM/Matroska буфера (`itag 251` / `250` / `249`)
    public static func demuxWebMOpus(_ webmData: Data) throws -> DemuxedOpusStream {
        let bytes = [UInt8](webmData)
        guard bytes.count > 64 else {
            throw NSError(domain: "WebMOpusRemuxer", code: 400, userInfo: [NSLocalizedDescriptionKey: "Буфер WebM слишком мал"])
        }
        // Сигнатура EBML Header: 0x1A 0x45 0xDF 0xA3
        guard bytes[0] == 0x1A, bytes[1] == 0x45, bytes[2] == 0xDF, bytes[3] == 0xA3 else {
            throw NSError(domain: "WebMOpusRemuxer", code: 415, userInfo: [NSLocalizedDescriptionKey: "Файл не является валидным WebM/EBML контейнером"])
        }

        var channels = 2
        var preSkip = 312
        if let ohOffset = findOpusHeadOffset(in: bytes) {
            let ch = Int(bytes[ohOffset + 9])
            if ch >= 1 && ch <= 2 {
                channels = ch
            }
            let skipLE = UInt16(bytes[ohOffset + 10]) | (UInt16(bytes[ohOffset + 11]) << 8)
            preSkip = Int(skipLE)
        }

        var packets: [Data] = []
        var frameCounts: [Int] = []
        packets.reserveCapacity(max(256, bytes.count / 320))
        frameCounts.reserveCapacity(max(256, bytes.count / 320))
        var totalSamples = 0

        let masterElementIDs: Set<UInt32> = [
            0x18538067, // Segment
            0x1F43B675, // Cluster
            0xA0        // BlockGroup
        ]

        var pos = 0
        let count = bytes.count
        while pos + 2 < count {
            guard let (elemId, afterId) = readEBMLId(bytes, at: pos),
                  let (elemSize, afterSize) = readEBMLSize(bytes, at: afterId) else {
                break
            }

            if masterElementIDs.contains(elemId) {
                pos = afterSize
                continue
            }

            guard elemSize >= 0, afterSize + elemSize <= count else {
                break
            }

            // SimpleBlock (0xA3) или Block (0xA1)
            if (elemId == 0xA3 || elemId == 0xA1) && elemSize > 4 {
                parseMatroskaBlock(
                    bytes: bytes,
                    start: afterSize,
                    end: afterSize + elemSize,
                    packets: &packets,
                    frameCounts: &frameCounts,
                    totalSamples: &totalSamples
                )
            }

            pos = afterSize + elemSize
        }

        guard !packets.isEmpty, totalSamples > 0 else {
            throw NSError(domain: "WebMOpusRemuxer", code: 422, userInfo: [NSLocalizedDescriptionKey: "В WebM-потоке не найдены аудиопакеты Opus"])
        }

        return DemuxedOpusStream(
            channels: channels,
            preSkip: preSkip,
            packets: packets,
            packetFrameCounts: frameCounts,
            totalSamples48k: totalSamples
        )
    }

    /// Собирает бинарный контейнер Apple `.caf` (`caff` + `desc` `'opus'` 48000 Hz + `pakt` + `data`) без перекодирования
    public static func buildAppleOpusCAF(from stream: DemuxedOpusStream) -> Data {
        let firstFrames = stream.packetFrameCounts.first ?? 960
        let isConstantFrames = stream.packetFrameCounts.allSatisfy { $0 == firstFrames }
        let framesPerPacketField: UInt32 = isConstantFrames ? UInt32(firstFrames) : 0

        var paktTable = Data()
        paktTable.reserveCapacity(stream.packets.count * (isConstantFrames ? 2 : 4) + 24)

        // CAFPacketTableHeader (24 bytes)
        appendInt64BE(&paktTable, Int64(stream.packets.count))
        appendInt64BE(&paktTable, Int64(max(0, stream.totalSamples48k - stream.preSkip)))
        appendInt32BE(&paktTable, Int32(stream.preSkip))
        appendInt32BE(&paktTable, 0)

        var totalAudioBytes = 0
        for i in 0..<stream.packets.count {
            let byteLen = stream.packets[i].count
            totalAudioBytes += byteLen
            appendCAFVarUInt(&paktTable, UInt64(byteLen))
            if !isConstantFrames {
                appendCAFVarUInt(&paktTable, UInt64(stream.packetFrameCounts[i]))
            }
        }

        var caf = Data()
        caf.reserveCapacity(64 + paktTable.count + totalAudioBytes)

        // 1. CAFFileHeader (8 bytes): 'caff', version=1, flags=0
        caf.append(contentsOf: [0x63, 0x61, 0x66, 0x66, 0x00, 0x01, 0x00, 0x00])

        // 2. 'desc' chunk (12 header + 32 CAFAudioDescription)
        caf.append(contentsOf: [0x64, 0x65, 0x73, 0x63]) // 'desc'
        appendInt64BE(&caf, 32)
        appendUInt64BE(&caf, 48000.0.bitPattern)        // mSampleRate = 48000.0 Hz
        caf.append(contentsOf: [0x6F, 0x70, 0x75, 0x73]) // mFormatID = 'opus' (kAudioFormatOpus)
        appendUInt32BE(&caf, 0)                         // mFormatFlags = 0
        appendUInt32BE(&caf, 0)                         // mBytesPerPacket = 0 (VBR)
        appendUInt32BE(&caf, framesPerPacketField)      // mFramesPerPacket (960 or 0)
        appendUInt32BE(&caf, UInt32(stream.channels))   // mChannelsPerFrame
        appendUInt32BE(&caf, 0)                         // mBitsPerChannel = 0

        // 3. 'pakt' chunk
        caf.append(contentsOf: [0x70, 0x61, 0x6B, 0x74]) // 'pakt'
        appendInt64BE(&caf, Int64(paktTable.count))
        caf.append(paktTable)

        // 4. 'data' chunk (4 bytes mEditCount + raw Opus packets)
        caf.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // 'data'
        appendInt64BE(&caf, Int64(4 + totalAudioBytes))
        appendUInt32BE(&caf, 0) // mEditCount = 0
        for pkt in stream.packets {
            caf.append(pkt)
        }

        return caf
    }

    /// Ремуксит скачанный WebM-файл в `.caf` и проверяет открытие через системный `AVAudioFile(forReading:)`
    public static func remuxWebMFileToVerifiedCAF(webmURL: URL, cafDestinationURL: URL) throws {
        let webmData = try Data(contentsOf: webmURL, options: .mappedIfSafe)
        let stream = try demuxWebMOpus(webmData)
        let cafData = buildAppleOpusCAF(from: stream)

        let fm = FileManager.default
        try? fm.removeItem(at: cafDestinationURL)
        try cafData.write(to: cafDestinationURL, options: .atomic)

        #if canImport(AVFoundation)
        let verifyFile = try AVAudioFile(forReading: cafDestinationURL)
        guard verifyFile.length > 0 else {
            try? fm.removeItem(at: cafDestinationURL)
            throw NSError(domain: "WebMOpusRemuxer", code: 500, userInfo: [NSLocalizedDescriptionKey: "AVAudioFile вернул нулевую длину для CAF Opus"])
        }
        #endif
    }

    // MARK: - RFC 6716 Opus Packet Frame Duration Calculation

    /// Точное вычисление количества семплов (при 48 kHz) в одном RFC 6716 пакете Opus по байту TOC
    public static func opusPacketSamples48kHz(_ bytes: [UInt8], offset: Int, length: Int) -> Int {
        guard length >= 1, offset + length <= bytes.count else { return 960 }
        let toc = bytes[offset]
        let config = Int(toc >> 3)
        let singleFrameSamples: Int
        switch config {
        case 16, 20, 24, 28:
            singleFrameSamples = 120   // 2.5 ms
        case 17, 21, 25, 29:
            singleFrameSamples = 240   // 5 ms
        case 0, 4, 8, 12, 14, 18, 22, 26, 30:
            singleFrameSamples = 480   // 10 ms
        case 2, 6, 10:
            singleFrameSamples = 1920  // 40 ms
        case 3, 7, 11:
            singleFrameSamples = 2880  // 60 ms
        default:
            singleFrameSamples = 960   // 20 ms
        }

        let frameCountCode = toc & 0x03
        let numFrames: Int
        switch frameCountCode {
        case 0:
            numFrames = 1
        case 1, 2:
            numFrames = 2
        default:
            numFrames = length >= 2 ? max(1, Int(bytes[offset + 1] & 0x3F)) : 1
        }
        return singleFrameSamples * numFrames
    }

    // MARK: - Internal EBML / Matroska Helpers

    private static func findOpusHeadOffset(in bytes: [UInt8]) -> Int? {
        let searchLimit = min(bytes.count - 19, 16_384)
        guard searchLimit > 0 else { return nil }
        for i in 0..<searchLimit {
            if bytes[i] == 0x4F && bytes[i + 1] == 0x70 && bytes[i + 2] == 0x75 && bytes[i + 3] == 0x73 &&
                bytes[i + 4] == 0x48 && bytes[i + 5] == 0x65 && bytes[i + 6] == 0x61 && bytes[i + 7] == 0x64 {
                return i
            }
        }
        return nil
    }

    private static func readEBMLId(_ bytes: [UInt8], at index: Int) -> (UInt32, Int)? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]
        guard first != 0 else { return nil }
        var len = 1
        while len <= 4 && (first & (0x80 >> (len - 1))) == 0 {
            len += 1
        }
        guard len <= 4, index + len <= bytes.count else { return nil }
        var val: UInt32 = 0
        for i in 0..<len {
            val = (val << 8) | UInt32(bytes[index + i])
        }
        return (val, index + len)
    }

    private static func readEBMLSize(_ bytes: [UInt8], at index: Int) -> (Int, Int)? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]
        guard first != 0 else { return nil }
        var len = 1
        while len <= 8 && (first & (0x80 >> (len - 1))) == 0 {
            len += 1
        }
        guard len <= 8, index + len <= bytes.count else { return nil }
        let mask: UInt8 = len == 8 ? 0 : ((1 << (8 - len)) - 1)
        var val = UInt64(first & mask)
        for i in 1..<len {
            val = (val << 8) | UInt64(bytes[index + i])
        }
        let allOnes: UInt64 = (len == 8) ? 0x00FF_FFFF_FFFF_FFFF : ((1 << (7 * len)) - 1)
        if val == allOnes {
            return (-1, index + len) // Unknown / streaming master element size
        }
        return (Int(val), index + len)
    }

    private static func parseMatroskaBlock(
        bytes: [UInt8],
        start: Int,
        end: Int,
        packets: inout [Data],
        frameCounts: inout [Int],
        totalSamples: inout Int
    ) {
        guard let (trackNum, afterTrack) = readEBMLSize(bytes, at: start),
              trackNum >= 1,
              afterTrack + 3 <= end else {
            return
        }
        let flags = bytes[afterTrack + 2]
        let lacing = (flags >> 1) & 0x03
        var p = afterTrack + 3
        guard p < end else { return }

        if lacing == 0 {
            let len = end - p
            guard len > 0 else { return }
            let samples = opusPacketSamples48kHz(bytes, offset: p, length: len)
            packets.append(Data(bytes[p..<end]))
            frameCounts.append(samples)
            totalSamples += samples
            return
        }

        // Laced frames (Xiph = 1, Fixed = 3, EBML = 2)
        guard p + 1 < end else { return }
        let laceFrameCount = Int(bytes[p]) + 1
        p += 1
        var sizes: [Int] = []
        sizes.reserveCapacity(laceFrameCount)

        if lacing == 3 {
            let remaining = end - p
            guard remaining >= laceFrameCount, remaining % laceFrameCount == 0 else { return }
            let each = remaining / laceFrameCount
            sizes = Array(repeating: each, count: laceFrameCount)
        } else if lacing == 1 {
            var used = 0
            for _ in 0..<(laceFrameCount - 1) {
                var fSize = 0
                while p < end {
                    let b = Int(bytes[p])
                    p += 1
                    fSize += b
                    if b < 255 { break }
                }
                sizes.append(fSize)
                used += fSize
            }
            let lastSize = (end - p) - used
            guard lastSize > 0 else { return }
            sizes.append(lastSize)
        } else if lacing == 2 {
            guard let (firstSize, nextP) = readEBMLSize(bytes, at: p), firstSize > 0 else { return }
            p = nextP
            var prevSize = firstSize
            var used = firstSize
            sizes.append(firstSize)
            for _ in 1..<(laceFrameCount - 1) {
                guard let (rawVal, pAfter) = readEBMLSizeWithLen(bytes, at: p) else { return }
                let bias = (1 << (7 * rawVal.len - 1)) - 1
                let delta = rawVal.val - bias
                let currentSize = prevSize + delta
                guard currentSize > 0 else { return }
                sizes.append(currentSize)
                used += currentSize
                prevSize = currentSize
                p = pAfter
            }
            let lastSize = (end - p) - used
            guard lastSize > 0 else { return }
            sizes.append(lastSize)
        }

        for sz in sizes {
            guard sz > 0, p + sz <= end else { break }
            let samples = opusPacketSamples48kHz(bytes, offset: p, length: sz)
            packets.append(Data(bytes[p..<(p + sz)]))
            frameCounts.append(samples)
            totalSamples += samples
            p += sz
        }
    }

    private static func readEBMLSizeWithLen(_ bytes: [UInt8], at index: Int) -> ((val: Int, len: Int), Int)? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]
        guard first != 0 else { return nil }
        var len = 1
        while len <= 8 && (first & (0x80 >> (len - 1))) == 0 {
            len += 1
        }
        guard len <= 7, index + len <= bytes.count else { return nil }
        let mask: UInt8 = (1 << (8 - len)) - 1
        var val = Int(first & mask)
        for i in 1..<len {
            val = (val << 8) | Int(bytes[index + i])
        }
        return ((val, len), index + len)
    }

    private static func appendCAFVarUInt(_ data: inout Data, _ value: UInt64) {
        if value < 128 {
            data.append(UInt8(value))
            return
        }
        var chunks: [UInt8] = []
        var v = value
        chunks.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            chunks.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        for b in chunks.reversed() {
            data.append(b)
        }
    }

    private static func appendUInt32BE(_ data: inout Data, _ v: UInt32) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    private static func appendInt32BE(_ data: inout Data, _ v: Int32) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    private static func appendUInt64BE(_ data: inout Data, _ v: UInt64) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    private static func appendInt64BE(_ data: inout Data, _ v: Int64) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }
}
