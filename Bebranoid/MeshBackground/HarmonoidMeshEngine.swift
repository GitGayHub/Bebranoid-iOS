import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct MeshRGB: Codable, Equatable, Hashable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int
    public var score: Double

    public init(_ r: Int, _ g: Int, _ b: Int, score: Double = 0.0) {
        self.r = max(0, min(255, r))
        self.g = max(0, min(255, g))
        self.b = max(0, min(255, b))
        self.score = score
    }

    public var cssString: String {
        "rgb(\(r), \(g), \(b))"
    }

    public var hexString: String {
        String(format: "#%02x%02x%02x", r, g, b)
    }

    public var normalizedDouble: (r: Double, g: Double, b: Double) {
        (Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0)
    }

    public func isRGBEqual(to other: MeshRGB) -> Bool {
        r == other.r && g == other.g && b == other.b
    }
}

public struct MeshHSV: Equatable, Sendable {
    /// Оттенок в градусах `[0, 360)` (1:1 с `rgbToHsv` в `HarmonoidMeshBackground.jsx`)
    public var h: Double
    public var s: Double
    public var v: Double

    public init(h: Double, s: Double, v: Double) {
        self.h = h
        self.s = s
        self.v = v
    }
}

public struct MeshControlPointSpec: Equatable, Sendable {
    public let bx: Double
    public let by: Double
    public let ax: Double
    public let ay: Double
    public let sx: Double
    public let sy: Double
    public let p: Double
}

public struct MeshBlobPoint: Equatable, Sendable {
    public var index: Int
    public var x: Double
    public var y: Double
    public var radius: Double
    public var color: MeshRGB
    public var isSourceOver: Bool
}

/// Точный 1:1 математический порт `src/components/HarmonoidMeshBackground.jsx`.
///
/// Все константы и функции соответствуют исходнику Windows:
/// - Анализ обложки `64×64` (`analysisDimension = 64`)
/// - Фильтрация: `a < 32` отбрасывается; `lum < 0.025 || lum > 0.985` отбрасывается; `sat < 0.035` отбрасывается
/// - Корзины оттенков по `10°`: `key = Int(floor(hue / 10.0))`
/// - Скоринг корзины: `pastelBoost = (lum > 0.55 && sat >= 0.04 && sat < 0.4) ? 1.35 : 1.0`, `satScore = max(0.12, sat)`,
///   `score += satScore * (0.45 + (1.0 - abs(lum - 0.42))) * pastelBoost`
/// - Отбор топ-8 цветов (`maxColors = 8`), при пустом результате — усреднение каждого 4-го пикселя (`i += 16`)
/// - Преобразование в 4 тёмных Mesh-тона через `toMeshTint(c, depth = 0.22 + i * 0.04)`
/// - Выбор UI акцента через `pickAccentFromPalette` + `ensureReadableAccent` (`luminance >= 0.42`)
/// - Движение 4 пятен (`speed = 0.45`), динамический радиус `max(w, h) * (0.55 + 0.08 * sin(t * 0.35 + i))`
/// - Пятно `0` рисуется в `source-over`, пятна `1..3` — в `lighter` (`plusLighter`)
/// - Переход между палитрами: по умолчанию `1650 ms`, минимум `1400 ms` (`smoothstep`)
public enum HarmonoidMeshEngine {
    public static let analysisDimension: Int = 64
    public static let maxExtractedPaletteColors: Int = 8
    public static let defaultTransitionMs: Double = 1650.0
    public static let minTransitionMs: Double = 1400.0
    public static let motionSpeed: Double = 0.45
    public static let offscreenScaleFactor: Double = 0.32

    public static let canvasDarkeningAlpha: Double = 0.12
    public static let topVignetteAlpha: Double = 0.22
    public static let bottomVignetteAlpha: Double = 0.28
    public static let ambientOverlayAlpha: Double = 0.18

    /// Палитра по умолчанию из `mapPaletteToMeshColors([])` в `HarmonoidMeshBackground.jsx`
    public static let defaultPalette: [MeshRGB] = [
        MeshRGB(20, 30, 50),
        MeshRGB(30, 22, 48),
        MeshRGB(18, 36, 44),
        MeshRGB(24, 20, 40)
    ]

    /// Fallback палитра при первом монтировании (`fallbackColors` в `HarmonoidMeshBackground.jsx`)
    public static let bootFallbackColors: [MeshRGB] = [
        MeshRGB(18, 22, 48),
        MeshRGB(28, 18, 42),
        MeshRGB(12, 32, 40),
        MeshRGB(22, 16, 36)
    ]

    /// Акцент по умолчанию (`DEFAULT_UI_ACCENT` в `HarmonoidMeshBackground.jsx`)
    public static let defaultAccent = MeshRGB(96, 165, 250)

    /// 4 контрольные точки из `MeshCanvas` (`HarmonoidMeshBackground.jsx` строки 455–460)
    public static let controlPoints: [MeshControlPointSpec] = [
        MeshControlPointSpec(bx: 0.15, by: 0.20, ax: 0.18, ay: 0.16, sx: 0.70, sy: 0.90, p: 0.0),
        MeshControlPointSpec(bx: 0.85, by: 0.18, ax: 0.16, ay: 0.20, sx: 0.85, sy: 1.10, p: 1.3),
        MeshControlPointSpec(bx: 0.20, by: 0.82, ax: 0.20, ay: 0.15, sx: 1.05, sy: 0.75, p: 2.1),
        MeshControlPointSpec(bx: 0.82, by: 0.85, ax: 0.17, ay: 0.18, sx: 0.95, sy: 1.00, p: 3.4)
    ]

    // MARK: - Math & Color Primitives (1:1 with HarmonoidMeshBackground.jsx)

    public static func clamp(_ value: Double, _ minVal: Double, _ maxVal: Double) -> Double {
        min(maxVal, max(minVal, value))
    }

    /// `Math.round` в JavaScript округляет `.5` вверх к `+Infinity` (`Math.floor(x + 0.5)`).
    public static func jsRound(_ value: Double) -> Int {
        Int(floor(value + 0.5))
    }

    /// `luminance(r, g, b)` (строки 15–20 `HarmonoidMeshBackground.jsx`)
    public static func luminance(_ r: Int, _ g: Int, _ b: Int) -> Double {
        let rs = Double(r) / 255.0
        let gs = Double(g) / 255.0
        let bs = Double(b) / 255.0
        return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs
    }

    public static func luminance(_ color: MeshRGB) -> Double {
        luminance(color.r, color.g, color.b)
    }

    /// `chroma(r, g, b)` (строки 102–106 `HarmonoidMeshBackground.jsx`)
    public static func chroma(_ r: Int, _ g: Int, _ b: Int) -> Double {
        let maxC = Double(max(r, g, b))
        let minC = Double(min(r, g, b))
        return maxC == 0.0 ? 0.0 : (maxC - minC) / maxC
    }

    /// `hueOfRgb(r255, g255, b255)` (строки 27–37 `HarmonoidMeshBackground.jsx`)
    public static func hueOfRgb(_ r255: Int, _ g255: Int, _ b255: Int) -> Double {
        let r = Double(r255) / 255.0
        let g = Double(g255) / 255.0
        let b = Double(b255) / 255.0
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        if maxC == minC { return 0.0 }
        let d = maxC - minC
        let h: Double
        if maxC == r {
            h = ((g - b) / d + (g < b ? 6.0 : 0.0)) / 6.0
        } else if maxC == g {
            h = ((b - r) / d + 2.0) / 6.0
        } else {
            h = ((r - g) / d + 4.0) / 6.0
        }
        return h * 360.0
    }

    /// Кратчайший путь поворота оттенка по цветовому кругу (`setAccentHue`, строки 48–63)
    public static func unwrapShortestAccentHue(currentHue: Double?, targetHueDeg: Double) -> Int {
        let target = ((targetHueDeg.truncatingRemainder(dividingBy: 360.0)) + 360.0).truncatingRemainder(dividingBy: 360.0)
        guard let current = currentHue, current.isFinite else {
            return jsRound(target)
        }
        let currentNorm = ((current.truncatingRemainder(dividingBy: 360.0)) + 360.0).truncatingRemainder(dividingBy: 360.0)
        var delta = target - currentNorm
        if delta > 180.0 { delta -= 360.0 }
        if delta < -180.0 { delta += 360.0 }
        return jsRound(current + delta)
    }

    /// `rgbToHsv(r, g, b)` -> `[h * 360, s, v]` (строки 65–81 `HarmonoidMeshBackground.jsx`)
    public static func rgbToHsv(_ r255: Int, _ g255: Int, _ b255: Int) -> MeshHSV {
        let r = Double(r255) / 255.0
        let g = Double(g255) / 255.0
        let b = Double(b255) / 255.0
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let d = maxC - minC
        var h = 0.0
        let s = maxC == 0.0 ? 0.0 : d / maxC
        let v = maxC
        if d != 0.0 {
            if maxC == r {
                h = ((g - b) / d + (g < b ? 6.0 : 0.0)) / 6.0
            } else if maxC == g {
                h = ((b - r) / d + 2.0) / 6.0
            } else {
                h = ((r - g) / d + 4.0) / 6.0
            }
        }
        return MeshHSV(h: h * 360.0, s: s, v: v)
    }

    /// `hsvToRgb(h, s, v)` где `h` в градусах `[0, 360)` (строки 83–100 `HarmonoidMeshBackground.jsx`)
    public static func hsvToRgb(_ h: Double, _ s: Double, _ v: Double, score: Double = 0.0) -> MeshRGB {
        let hh = ((h.truncatingRemainder(dividingBy: 360.0)) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let c = v * s
        let sector = (hh / 60.0).truncatingRemainder(dividingBy: 2.0)
        let x = c * (1.0 - abs(sector - 1.0))
        let m = v - c

        let (rp, gp, bp): (Double, Double, Double)
        if hh < 60.0 {
            (rp, gp, bp) = (c, x, 0.0)
        } else if hh < 120.0 {
            (rp, gp, bp) = (x, c, 0.0)
        } else if hh < 180.0 {
            (rp, gp, bp) = (0.0, c, x)
        } else if hh < 240.0 {
            (rp, gp, bp) = (0.0, x, c)
        } else if hh < 300.0 {
            (rp, gp, bp) = (x, 0.0, c)
        } else {
            (rp, gp, bp) = (c, 0.0, x)
        }

        return MeshRGB(
            jsRound((rp + m) * 255.0),
            jsRound((gp + m) * 255.0),
            jsRound((bp + m) * 255.0),
            score: score
        )
    }

    // MARK: - Step 1: Quantization & Cover Palette Extraction (64x64, 10° buckets, maxColors = 8)

    private struct HueBucket {
        var r: Int = 0
        var g: Int = 0
        var b: Int = 0
        var n: Int = 0
        var score: Double = 0.0
        var insertionOrder: Int
    }

    /// Точный порт `quantizeFromImageData(data, maxColors = 8)` (строки 113–152 `HarmonoidMeshBackground.jsx`)
    public static func quantizeFromImageData(_ data: [UInt8], maxColors: Int = maxExtractedPaletteColors) -> [MeshRGB] {
        guard data.count >= 4 else { return [] }

        var buckets: [Int: HueBucket] = [:]
        var nextOrder = 0

        var i = 0
        while i + 3 < data.count {
            let r = Int(data[i])
            let g = Int(data[i + 1])
            let b = Int(data[i + 2])
            let a = Int(data[i + 3])
            i += 4

            if a < 32 { continue }
            let lum = luminance(r, g, b)
            // Only pure paper-white / pure black out
            if lum < 0.025 || lum > 0.985 { continue }
            let sat = chroma(r, g, b)
            // True gray (no hue) — drop; soft pastel pink sat~0.08–0.25 must stay
            if sat < 0.035 { continue }

            let hsv = rgbToHsv(r, g, b)
            let key = Int(floor(hsv.h / 10.0))

            var prev = buckets[key] ?? HueBucket(insertionOrder: nextOrder)
            if buckets[key] == nil {
                nextOrder += 1
            }
            prev.r += r
            prev.g += g
            prev.b += b
            prev.n += 1

            let pastelBoost = (lum > 0.55 && sat >= 0.04 && sat < 0.4) ? 1.35 : 1.0
            let satScore = max(0.12, sat)
            prev.score += satScore * (0.45 + (1.0 - abs(lum - 0.42))) * pastelBoost
            buckets[key] = prev
        }

        let mapped = buckets.values.sorted { a, b in
            if abs(b.score - a.score) > 1e-12 {
                return a.score > b.score
            }
            return a.insertionOrder < b.insertionOrder
        }.prefix(maxColors).map { v in
            MeshRGB(
                jsRound(Double(v.r) / Double(v.n)),
                jsRound(Double(v.g) / Double(v.n)),
                jsRound(Double(v.b) / Double(v.n)),
                score: v.score
            )
        }

        return Array(mapped)
    }

    /// Точный порт `extractCoverPalette(imageData, maxColors = 8)` (строки 154–213 `HarmonoidMeshBackground.jsx`),
    /// включая фолбэк усреднения каждого 4-го пикселя (`i += 16`) для монохромных/чёрно-белых обложек.
    public static func extractCoverPalette(fromRGBA data: [UInt8], maxColors: Int = maxExtractedPaletteColors) -> [MeshRGB] {
        guard data.count >= 4 else { return [] }
        let colors = quantizeFromImageData(data, maxColors: maxColors)
        if !colors.isEmpty {
            return colors
        }

        // If empty, average whole image every 4th pixel (`i += 16`) as one color with `score: 1`
        var rSum = 0
        var gSum = 0
        var bSum = 0
        var n = 0
        var i = 0
        while i + 3 < data.count {
            if Int(data[i + 3]) < 32 {
                i += 16
                continue
            }
            rSum += Int(data[i])
            gSum += Int(data[i + 1])
            bSum += Int(data[i + 2])
            n += 1
            i += 16
        }
        if n > 0 {
            return [
                MeshRGB(
                    jsRound(Double(rSum) / Double(n)),
                    jsRound(Double(gSum) / Double(n)),
                    jsRound(Double(bSum) / Double(n)),
                    score: 1.0
                )
            ]
        }
        return []
    }

    // MARK: - Step 2: Dark Mesh Tones (`toMeshTint` & `mapPaletteToMeshColors`)

    /// Точный порт `toMeshTint(c, depth = 0.28)` (строки 220–228 `HarmonoidMeshBackground.jsx`)
    public static func toMeshTint(_ c: MeshRGB, depth: Double = 0.28) -> MeshRGB {
        let hsv = rgbToHsv(c.r, c.g, c.b)
        let h = hsv.h
        let s = hsv.s
        let v = hsv.v
        let pastel = v > 0.6 && s > 0.04 && s < 0.28
        let ns = pastel
            ? min(0.55, max(0.32, s * 2.2 + 0.14))
            : min(0.85, max(0.15, s))
        let nv = min(depth + 0.08, max(0.14, pastel ? 0.26 : (v > 0.5 ? depth : v * 0.65)))
        return hsvToRgb(h, ns, nv)
    }

    /// Точный порт `mapPaletteToMeshColors(palette)` (строки 234–254 `HarmonoidMeshBackground.jsx`)
    public static func mapPaletteToMeshColors(_ palette: [MeshRGB]) -> [MeshRGB] {
        if palette.isEmpty {
            return defaultPalette
        }
        let list = palette.enumerated().sorted { a, b in
            if abs(b.element.score - a.element.score) > 1e-12 {
                return a.element.score > b.element.score
            }
            return a.offset < b.offset
        }.map { $0.element }

        var picks: [MeshRGB] = list.prefix(4).enumerated().map { idx, color in
            toMeshTint(color, depth: 0.22 + Double(idx) * 0.04)
        }
        while picks.count < 4 {
            picks.append(toMeshTint(list[0], depth: 0.2 + Double(picks.count) * 0.05))
        }
        return [picks[0], picks[1], picks[2], picks[3]]
    }

    // MARK: - Step 3: UI Accent Selection (`pickAccentFromPalette` & `ensureReadableAccent`)

    /// Точный порт `ensureReadableAccent(c)` (строки 260–276 `HarmonoidMeshBackground.jsx`)
    public static func ensureReadableAccent(_ c: MeshRGB?) -> MeshRGB {
        guard let c else { return defaultAccent }
        let hsv = rgbToHsv(c.r, c.g, c.b)
        let h = hsv.h
        var s = hsv.s
        var v = hsv.v

        s = min(0.82, max(0.38, s < 0.12 ? 0.55 : s))
        v = max(0.58, min(0.82, v))
        var out = hsvToRgb(h, s, v)
        var guardCount = 0
        while luminance(out.r, out.g, out.b) < 0.42 && guardCount < 8 {
            v = min(0.9, v + 0.06)
            out = hsvToRgb(h, s, v)
            guardCount += 1
        }
        return out
    }

    /// Точный порт `pickAccentFromPalette(palette)` (строки 282–321 `HarmonoidMeshBackground.jsx`)
    public static func pickAccentFromPalette(_ palette: [MeshRGB]) -> MeshRGB {
        if palette.isEmpty {
            return defaultAccent
        }
        let list = palette.enumerated().sorted { a, b in
            if abs(b.element.score - a.element.score) > 1e-12 {
                return a.element.score > b.element.score
            }
            return a.offset < b.offset
        }.map { $0.element }

        func scoreOf(_ c: MeshRGB) -> Double {
            let hsv = rgbToHsv(c.r, c.g, c.b)
            let h = hsv.h
            let s = hsv.s
            let v = hsv.v
            let ch = chroma(c.r, c.g, c.b)
            let baseScore = c.score != 0.0 ? c.score : 1.0
            if v < 0.12 || (s < 0.08 && v < 0.45) {
                return baseScore * 0.05
            }
            var sc = baseScore * (0.4 + ch * 1.55)
            // Gold / amber / yellow (black+gold covers)
            if h >= 28.0 && h <= 72.0 && s > 0.18 {
                sc *= 2.0
            }
            // Warm red / orange / magenta — common album leads
            if (h < 30.0 || h > 330.0) && s > 0.28 && v > 0.18 {
                sc *= 1.65
            }
            if h >= 300.0 && h <= 350.0 && s > 0.25 {
                sc *= 1.25
            }
            return sc
        }

        var best = list[0]
        var bestSc = scoreOf(best)
        for c in list.prefix(8) {
            let sc = scoreOf(c)
            if sc > bestSc {
                best = c
                bestSc = sc
            }
        }

        let bestHsv = rgbToHsv(best.r, best.g, best.b)
        let h = bestHsv.h
        let s = bestHsv.s
        let v = bestHsv.v
        let pastel = v > 0.65 && s < 0.28
        let goldish = h >= 28.0 && h <= 72.0

        let raw: MeshRGB
        if pastel {
            raw = hsvToRgb(h, min(0.55, max(0.32, s * 1.8 + 0.12)), 0.7)
        } else if goldish {
            raw = hsvToRgb(h, min(0.72, max(0.4, s * 1.1)), min(0.78, max(0.55, v * 1.05)))
        } else {
            raw = hsvToRgb(h, min(0.78, max(0.32, s)), min(0.78, max(0.58, v)))
        }
        return ensureReadableAccent(raw)
    }

    // MARK: - Step 4: Base Fill, 4 Control Points, Dynamic Radius & Smoothstep Interpolation

    /// Точный порт `fillBase` (строки 370–378 `HarmonoidMeshBackground.jsx`):
    /// `r = max(4, floor(c0.r * 0.35))`, `g = max(4, floor(c0.g * 0.35))`, `b = max(6, floor(c0.b * 0.4))`
    public static func computeBaseFillColor(from meshColors: [MeshRGB]) -> MeshRGB {
        let c0 = meshColors.first ?? MeshRGB(12, 14, 28)
        let r = max(4, Int(floor(Double(c0.r) * 0.35)))
        let g = max(4, Int(floor(Double(c0.g) * 0.35)))
        let b = max(6, Int(floor(Double(c0.b) * 0.40)))
        return MeshRGB(r, g, b)
    }

    /// Точный порт `colorsNearlyEqual(a, b)` (строки 602–608 `HarmonoidMeshBackground.jsx`)
    public static func colorsNearlyEqual(_ a: [MeshRGB]?, _ b: [MeshRGB]?) -> Bool {
        guard let a, let b, a.count == b.count else { return false }
        for i in 0..<a.count {
            let c = a[i]
            let o = b[i]
            if abs(c.r - o.r) >= 10 || abs(c.g - o.g) >= 10 || abs(c.b - o.b) >= 10 {
                return false
            }
        }
        return true
    }

    public static func smoothstep(_ edge0: Double = 0.0, _ edge1: Double = 1.0, _ x: Double) -> Double {
        let denom = edge1 - edge0
        guard abs(denom) > 1e-12 else { return 0.0 }
        let p = clamp((x - edge0) / denom, 0.0, 1.0)
        return p * p * (3.0 - 2.0 * p)
    }

    public static func lerpColor(_ a: MeshRGB, _ b: MeshRGB, t: Double) -> MeshRGB {
        let clamped = clamp(t, 0.0, 1.0)
        let r = jsRound(Double(a.r) + (Double(b.r) - Double(a.r)) * clamped)
        let g = jsRound(Double(a.g) + (Double(b.g) - Double(a.g)) * clamped)
        let bVal = jsRound(Double(a.b) + (Double(b.b) - Double(a.b)) * clamped)
        return MeshRGB(r, g, bVal)
    }

    /// Интерполяция 4 цветов палитры по `smoothstep` (`e = p * p * (3 - 2 * p)`, строки 742–744)
    public static func lerpPalette(_ from: [MeshRGB], _ to: [MeshRGB], progress p: Double) -> [MeshRGB] {
        let e = smoothstep(0.0, 1.0, p)
        return (0..<4).map { idx in
            let cA = idx < from.count ? from[idx] : defaultPalette[idx]
            let cB = idx < to.count ? to[idx] : cA
            return lerpColor(cA, cB, t: e)
        }
    }

    /// Нейтральная графитово-серебристая палитра для чёрно-белых / монохромных обложек (без паразитного жёлтого или фиолетового оттенка JPEG-шума)
    public static let monochromePalette: [MeshRGB] = [
        MeshRGB(28, 28, 32),
        MeshRGB(48, 48, 54),
        MeshRGB(18, 18, 22),
        MeshRGB(38, 38, 43)
    ]

    public static let monochromeAccent = MeshRGB(234, 236, 242)

    /// Определяет, является ли обложка чёрно-белой / монохромной (отсекает артефакты сжатия JPEG `sat ~ 0.04..0.09`, сохраняя обложки с реальным цветным акцентом)
    public static func isPredominantlyMonochrome(rgba: [UInt8]) -> Bool {
        var validCount = 0
        var colorfulCount = 0
        var vividAccentCount = 0
        var chromaSum = 0.0

        var idx = 0
        while idx + 3 < rgba.count {
            let a = Int(rgba[idx + 3])
            if a >= 32 {
                let r = Int(rgba[idx])
                let g = Int(rgba[idx + 1])
                let b = Int(rgba[idx + 2])
                let lum = luminance(r, g, b)
                if lum >= 0.025 && lum <= 0.985 {
                    validCount += 1
                    let sat = chroma(r, g, b)
                    chromaSum += sat
                    if sat >= 0.115 {
                        colorfulCount += 1
                    }
                    if sat >= 0.24 && lum >= 0.08 && lum <= 0.92 {
                        vividAccentCount += 1
                    }
                }
            }
            idx += 4
        }

        guard validCount > 0 else { return true }
        let colorfulRatio = Double(colorfulCount) / Double(validCount)
        let vividRatio = Double(vividAccentCount) / Double(validCount)
        let meanChroma = chromaSum / Double(validCount)

        return vividRatio < 0.012 && colorfulRatio < 0.045 && meanChroma < 0.058
    }

    /// Точный расчёт координат и динамических радиусов 4 пятен в момент `timeSec` (строки 478–494 `HarmonoidMeshBackground.jsx`):
    /// - `x = (p.bx + sin(t * speed * p.sx + p.p) * p.ax) * w`
    /// - `y = (p.by + cos(t * speed * p.sy + p.p * 0.8) * p.ay) * h`
    /// - `radius = max(w, h) * (0.55 + 0.08 * sin(t * 0.35 + i))`
    /// - `isSourceOver = (i == 0)` (пятно 0 рисуется как `source-over`, пятна 1..3 — как `lighter`)
    public static func blobCenters(
        at timeSec: Double,
        width: Double,
        height: Double,
        meshColors: [MeshRGB]
    ) -> [MeshBlobPoint] {
        let cols = meshColors.count >= 4 ? meshColors : defaultPalette
        let maxDim = max(width, height)

        return (0..<4).map { i in
            let p = controlPoints[i]
            let x = (p.bx + sin(timeSec * motionSpeed * p.sx + p.p) * p.ax) * width
            let y = (p.by + cos(timeSec * motionSpeed * p.sy + p.p * 0.8) * p.ay) * height
            let radius = maxDim * (0.55 + 0.08 * sin(timeSec * 0.35 + Double(i)))
            return MeshBlobPoint(
                index: i,
                x: x,
                y: y,
                radius: radius,
                color: cols[i],
                isSourceOver: i == 0
            )
        }
    }

    /// Адаптация той же самой 4-точечной синусоидальной логики Harmonoid под компактный экран iPhone:
    /// чуть более выраженная амплитуда дрейфа и дыхания пятен, чтобы живое движение фона было деликатно заметно на узком дисплее телефона.
    public static func mobileBlobCenters(
        at timeSec: Double,
        width: Double,
        height: Double,
        meshColors: [MeshRGB]
    ) -> [MeshBlobPoint] {
        let cols = meshColors.count >= 4 ? meshColors : defaultPalette
        let maxDim = max(width, height)
        let mobileSpeed = motionSpeed * 1.36
        let ampBoost = 1.42

        return (0..<4).map { i in
            let p = controlPoints[i]
            let x = (p.bx + sin(timeSec * mobileSpeed * p.sx + p.p) * (p.ax * ampBoost)) * width
            let y = (p.by + cos(timeSec * mobileSpeed * p.sy + p.p * 0.8) * (p.ay * ampBoost)) * height
            let radius = maxDim * (0.52 + 0.12 * sin(timeSec * 0.48 + Double(i)))
            return MeshBlobPoint(
                index: i,
                x: x,
                y: y,
                radius: radius,
                color: cols[i],
                isSourceOver: i == 0
            )
        }
    }

    #if canImport(CoreGraphics)
    /// Полный конвейер для `CGImage`: downscale до `64×64` RGBA -> детекция Ч/Б монохрома -> `extractCoverPalette` -> `(palette, meshColors, uiAccent)`
    public static func analyzeCoverImage(_ cgImage: CGImage) -> (palette: [MeshRGB], meshColors: [MeshRGB], uiAccent: MeshRGB) {
        let dim = analysisDimension
        var pixels = [UInt8](repeating: 0, count: dim * dim * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: dim,
            height: dim,
            bitsPerComponent: 8,
            bytesPerRow: dim * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return ([], defaultPalette, defaultAccent)
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: dim, height: dim))

        if isPredominantlyMonochrome(rgba: pixels) {
            return (monochromePalette, monochromePalette, monochromeAccent)
        }

        let palette = extractCoverPalette(fromRGBA: pixels, maxColors: maxExtractedPaletteColors)
        if palette.isEmpty || palette.allSatisfy({ chroma($0.r, $0.g, $0.b) < 0.095 }) {
            return (monochromePalette, monochromePalette, monochromeAccent)
        }
        let mesh = mapPaletteToMeshColors(palette)
        let accent = pickAccentFromPalette(palette)
        return (palette, mesh, accent)
    }

    public static func extractPalette(from cgImage: CGImage) -> [MeshRGB] {
        analyzeCoverImage(cgImage).meshColors
    }
    #endif
}
