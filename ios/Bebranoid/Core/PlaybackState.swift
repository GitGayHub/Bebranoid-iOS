import Foundation

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case none
    case all
    case one
}

public enum AudioFXMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case normal = "normal"
    case slowed = "slowed"
    case slowedReverb = "slowed_reverb"
    case speedup = "speedup"
    case speedupReverb = "speedup_reverb"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: return "Обычный"
        case .slowed: return "Slowed"
        case .slowedReverb: return "Slowed + Reverb"
        case .speedup: return "Speed Up"
        case .speedupReverb: return "Speed Up + Reverb"
        }
    }

    public var shortBadgeName: String {
        switch self {
        case .normal: return "FX"
        case .slowed: return "Slowed"
        case .slowedReverb: return "Slowed+Rev"
        case .speedup: return "SpeedUp"
        case .speedupReverb: return "Speed+Rev"
        }
    }

    /// Встроенный множитель скорости из `src/App.jsx` (`AUDIO_FX_MODES`)
    public var defaultRateMultiplier: Float {
        switch self {
        case .normal: return 1.0
        case .slowed, .slowedReverb: return 0.85
        case .speedup, .speedupReverb: return 1.15
        }
    }

    /// Использует ли режим сдвиг высоты тона вместе со скоростью (`preservesPitch = false`)
    public var shiftsPitchWithRate: Bool {
        self != .normal
    }

    /// Включена ли пространственная реверберация
    public var usesReverb: Bool {
        self == .slowedReverb || self == .speedupReverb
    }

    /// Параметры баланса Dry / Wet из `src/App.jsx` (`applyAudioFxMode`)
    public var dryGain: Float {
        switch self {
        case .normal, .slowed, .speedup: return 1.0
        case .slowedReverb: return 0.78
        case .speedupReverb: return 0.82
        }
    }

    public var wetGain: Float {
        switch self {
        case .normal, .slowed, .speedup: return 0.0
        case .slowedReverb: return 0.42
        case .speedupReverb: return 0.30
        }
    }
}

public enum LyricsEngineKind: String, Codable, CaseIterable, Sendable {
    case beautiful = "beautiful"
    case classic = "classic"

    public var displayName: String {
        switch self {
        case .beautiful: return "Beautiful Lyrics (Apple Music)"
        case .classic: return "Классическое караоке"
        }
    }
}

public enum LyricsFontSizePreset: String, Codable, CaseIterable, Sendable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    public var displayName: String {
        switch self {
        case .small: return "Компактный"
        case .medium: return "Средний"
        case .large: return "Крупный"
        }
    }

    public var scaleFactor: CGFloat {
        switch self {
        case .small: return 0.88
        case .medium: return 1.0
        case .large: return 1.16
        }
    }
}

public enum TrackSortField: String, Codable, CaseIterable, Sendable {
    case recent = "recent"
    case title = "title"
    case artist = "artist"
    case album = "album"
    case year = "year"
    case plays = "plays"

    public var displayName: String {
        switch self {
        case .recent: return "По дате добавления"
        case .title: return "По названию"
        case .artist: return "По исполнителю"
        case .album: return "По альбому"
        case .year: return "По году"
        case .plays: return "По прослушиваниям"
        }
    }
}
