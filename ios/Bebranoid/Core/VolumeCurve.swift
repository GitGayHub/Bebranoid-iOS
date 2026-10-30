import Foundation

/// Точный 1:1 порт `src/lib/volume.js`
public enum VolumeCurve {
    public static let exponent: Double = 2.75

    public static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return min(1.0, max(0.0, value))
    }

    /// Преобразует положение ползунка UI `[0, 1]` в линейный коэффициент усиления `[0, 1]` (`u^2.75`)
    public static func uiToGain(_ uiVolume: Double) -> Double {
        let clamped = clamp01(uiVolume)
        if clamped <= 0.0 { return 0.0 }
        if clamped >= 1.0 { return 1.0 }
        return pow(clamped, exponent)
    }

    /// Обратное преобразование линейного коэффициента усиления `[0, 1]` в положение ползунка UI `[0, 1]`
    public static func gainToUi(_ gain: Double) -> Double {
        let clamped = clamp01(gain)
        if clamped <= 0.0 { return 0.0 }
        if clamped >= 1.0 { return 1.0 }
        return pow(clamped, 1.0 / exponent)
    }
}
