import Foundation

public enum QualityBadgeTier: String, Codable, Sendable {
    case hiRes = "hi-res"
    case lossless = "lossless"
    case hq = "hq"
    case standard = "standard"
}

public struct QualityBadgeInfo: Codable, Hashable, Sendable {
    public var tier: QualityBadgeTier
    public var label: String
    public var tooltipText: String
    public var hexColor: String

    public init(tier: QualityBadgeTier, label: String, tooltipText: String, hexColor: String) {
        self.tier = tier
        self.label = label
        self.tooltipText = tooltipText
        self.hexColor = hexColor
    }
}

/// Технические характеристики аудиофайла и расчёт плашки качества (`src/components/Player.jsx` 1:1)
public struct AudioFormatInfo: Codable, Hashable, Sendable {
    public var codec: String
    public var container: String?
    public var bitrateKbps: Int?
    public var sampleRateHz: Int?
    public var bitsPerSample: Int?
    public var channels: Int?
    public var lossless: Bool

    public init(
        codec: String,
        container: String? = nil,
        bitrateKbps: Int? = nil,
        sampleRateHz: Int? = nil,
        bitsPerSample: Int? = nil,
        channels: Int? = nil,
        lossless: Bool = false
    ) {
        self.codec = codec.uppercased()
        self.container = container?.uppercased()
        self.bitrateKbps = bitrateKbps
        self.sampleRateHz = sampleRateHz
        self.bitsPerSample = bitsPerSample
        self.channels = channels
        self.lossless = lossless
    }

    /// Точный аналог `formatTechTooltip(info)` из `src/components/Player.jsx`
    public var formattedTechnicalSummary: String {
        var parts: [String] = []
        if !codec.isEmpty {
            parts.append(codec)
        }
        if let sr = sampleRateHz, sr > 0 {
            let khz = Double(sr) / 1000.0
            let formattedKhz = khz.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f kHz", khz)
                : String(format: "%.1f kHz", khz)
            parts.append(formattedKhz)
        }
        if let bps = bitsPerSample, bps > 0 {
            parts.append("\(bps)-bit")
        }
        if let br = bitrateKbps, br > 0 {
            parts.append("\(br) kbps")
        }
        return parts.joined(separator: " • ")
    }

    /// Точный аналог `computeQualityInfo(formatInfo, currentTrack)` из `src/components/Player.jsx`
    public func computeQualityBadge() -> QualityBadgeInfo {
        let upperCodec = codec.uppercased()
        let isLosslessCodec = lossless || ["FLAC", "ALAC", "WAV", "PCM", "AIFF", "APE", "WV"].contains(where: { upperCodec.contains($0) })
        let isHiRes = isLosslessCodec && ((bitsPerSample ?? 0) > 16 || (sampleRateHz ?? 0) > 48000)

        let shortCodec: String = {
            if upperCodec.contains("FLAC") { return "FLAC" }
            if upperCodec.contains("ALAC") { return "ALAC" }
            if upperCodec.contains("WAV") || upperCodec.contains("PCM") { return "WAV" }
            if upperCodec.contains("OPUS") { return "OPUS" }
            if upperCodec.contains("AAC") || upperCodec.contains("M4A") || upperCodec.contains("MP4") { return "AAC" }
            if upperCodec.contains("MP3") || upperCodec.contains("MPEG") { return "MP3" }
            return upperCodec.isEmpty ? "AUDIO" : upperCodec
        }()

        let tooltip = formattedTechnicalSummary.isEmpty ? shortCodec : formattedTechnicalSummary

        if isHiRes {
            return QualityBadgeInfo(
                tier: .hiRes,
                label: "\(shortCodec) Hi-Res",
                tooltipText: tooltip,
                hexColor: "#ffc85a"
            )
        }

        if isLosslessCodec {
            return QualityBadgeInfo(
                tier: .lossless,
                label: "\(shortCodec) Lossless",
                tooltipText: tooltip,
                hexColor: "#d08bff"
            )
        }

        let isHighQualityLossy = ["OPUS", "AAC"].contains(shortCodec) || (shortCodec == "MP3" && (bitrateKbps ?? 0) >= 256)
        if isHighQualityLossy {
            let brLabel = (bitrateKbps ?? 0) > 0 ? "\(shortCodec) \(bitrateKbps!)k" : "\(shortCodec) HQ"
            return QualityBadgeInfo(
                tier: .hq,
                label: brLabel,
                tooltipText: tooltip,
                hexColor: "#60a5fa"
            )
        }

        let stdLabel = (bitrateKbps ?? 0) > 0 ? "\(shortCodec) \(bitrateKbps!)k" : shortCodec
        return QualityBadgeInfo(
            tier: .standard,
            label: stdLabel,
            tooltipText: tooltip,
            hexColor: "#9ca3af"
        )
    }

    /// Определение информации о формате по расширению файла, если файл ещё не скачан
    public static func fallbackFromFilename(_ filename: String, fileSize: Int64? = nil, duration: Double = 0) -> AudioFormatInfo {
        let ext = (filename as NSString).pathExtension.lowercased()
        let estimatedKbps: Int? = {
            guard let size = fileSize, size > 0, duration > 1 else { return nil }
            return Int(round((Double(size) * 8.0) / duration / 1000.0))
        }()

        switch ext {
        case "flac":
            return AudioFormatInfo(codec: "FLAC", container: "FLAC", bitrateKbps: estimatedKbps, sampleRateHz: 44100, bitsPerSample: 16, channels: 2, lossless: true)
        case "wav":
            return AudioFormatInfo(codec: "WAV", container: "WAV", bitrateKbps: estimatedKbps, sampleRateHz: 44100, bitsPerSample: 16, channels: 2, lossless: true)
        case "alac":
            return AudioFormatInfo(codec: "ALAC", container: "M4A", bitrateKbps: estimatedKbps, sampleRateHz: 44100, bitsPerSample: 16, channels: 2, lossless: true)
        case "opus", "ogg":
            return AudioFormatInfo(codec: "OPUS", container: "OGG", bitrateKbps: estimatedKbps ?? 160, sampleRateHz: 48000, channels: 2, lossless: false)
        case "m4a", "aac", "mp4":
            return AudioFormatInfo(codec: "AAC", container: "M4A", bitrateKbps: estimatedKbps ?? 256, sampleRateHz: 44100, channels: 2, lossless: false)
        case "mp3":
            return AudioFormatInfo(codec: "MP3", container: "MP3", bitrateKbps: estimatedKbps ?? 320, sampleRateHz: 44100, channels: 2, lossless: false)
        default:
            return AudioFormatInfo(codec: ext.isEmpty ? "AUDIO" : ext.uppercased(), bitrateKbps: estimatedKbps, lossless: false)
        }
    }
}
