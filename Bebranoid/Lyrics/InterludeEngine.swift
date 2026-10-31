import Foundation

/// Состояние одной из 3 точек проигрыша (`src/beautiful-lyrics/Interlude.js`)
public struct InterludeDotVisualState: Equatable, Sendable {
    public var scale: Double
    public var yOffset: Double
    public var glow: Double
    public var opacity: Double
    public var isLit: Bool

    public init(scale: Double, yOffset: Double, glow: Double, opacity: Double, isLit: Bool = false) {
        self.scale = scale
        self.yOffset = yOffset
        self.glow = glow
        self.opacity = opacity
        self.isLit = isLit
    }
}

/// Состояние всего индикатора инструментального проигрыша (3 точки с «marble roll» волной)
public struct InterludeFrameState: Equatable, Sendable {
    public var isVisible: Bool
    public var expansionProgress: Double
    public var groupScale: Double
    public var groupOpacity: Double
    public var isCountdownPhase: Bool
    public var dots: [InterludeDotVisualState]

    public init(
        isVisible: Bool,
        expansionProgress: Double = 0.0,
        groupScale: Double,
        groupOpacity: Double,
        isCountdownPhase: Bool = false,
        dots: [InterludeDotVisualState]
    ) {
        self.isVisible = isVisible
        self.expansionProgress = expansionProgress
        self.groupScale = groupScale
        self.groupOpacity = groupOpacity
        self.isCountdownPhase = isCountdownPhase
        self.dots = dots
    }
}

/// Точный 1:1 порт `C:\VibeCoding\Bebranoid\src\beautiful-lyrics\Interlude.js`.
/// Непрерывный «шарик» (`marbleAt(i, crest)`) перекатывается точка 1 → 2 → 3 в цикле,
/// а в финальные `22%` паузы делает плавный завершающий раскат с остановкой на 3-й точке (`crest = 2.4`)
/// и мягким растворением (`smootherstep` за `0.75s`) прямо во вступление следующей строки вокала.
public enum InterludeEngine {
    public static let dotCount: Int = 3
    public static let idealRollSec: Double = 2.2
    public static let finalRollPortion: Double = 0.22
    public static let minFinalRollSec: Double = 1.6
    public static let exitOverlapSec: Double = 0.75

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    private static func smootherstep(_ t: Double) -> Double {
        let x = clamp(t, 0.0, 1.0)
        return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
    }

    private static func easeSinOut(_ t: Double) -> Double {
        let x = clamp(t, 0.0, 1.0)
        return sin((x * .pi) * 0.5)
    }

    /// Точная формула `marbleAt(i, crest)` из `src/beautiful-lyrics/Interlude.js` (строки 47–61)
    private static func marbleAt(index i: Int, crest: Double) -> InterludeDotVisualState {
        let idx = Double(i)
        let dist = abs(idx - crest)
        let raw = max(0.0, 1.0 - dist * 0.52)
        let e = raw * raw * (3.0 - 2.0 * raw)
        let passed: Double = (idx + 0.2 < crest)
            ? clamp(1.0 - (crest - idx - 0.2) * 0.55, 0.0, 0.62)
            : 0.0
        let intensity = max(passed, e)

        let scale = 0.68 + 0.52 * intensity
        // В десктопном CSS `translateY(calc(var(--dot-size, 8px) * y))` -> умножаем безразмерный сдвиг на 8 pt
        let yUnit = -0.24 * e + 0.03 * (1.0 - intensity)
        let glow = 0.05 + 0.95 * intensity
        let opacity = 0.20 + 0.80 * intensity
        let isLit = opacity > 0.62 && scale > 0.88

        return InterludeDotVisualState(
            scale: scale,
            yOffset: yUnit * 8.0,
            glow: glow,
            opacity: opacity,
            isLit: isLit
        )
    }

    private static func crestFromProgress(_ u: Double, isFinal: Bool) -> Double {
        let p = smootherstep(clamp(u, 0.0, 1.0))
        return isFinal ? (p * 2.45) : (p * 2.35)
    }

    /// Рассчитывает состояние каждой из 3 точек в момент времени `timestamp` для паузы `[startTime, endTime]`
    public static func evaluate(
        startTime: Double,
        endTime: Double,
        timestamp: Double
    ) -> InterludeFrameState {
        let duration = max(0.15, endTime - startTime)
        let relativeTime = timestamp - startTime
        let leadInWindow: Double = startTime <= 0.05 ? 0.0 : 0.28
        let collapseTailSec: Double = 0.32

        if relativeTime < -leadInWindow || relativeTime > duration + exitOverlapSec + collapseTailSec {
            return InterludeFrameState(
                isVisible: false,
                expansionProgress: 0.0,
                groupScale: 0.0,
                groupOpacity: 0.0,
                isCountdownPhase: false,
                dots: Array(
                    repeating: InterludeDotVisualState(scale: 0.70, yOffset: 0, glow: 0, opacity: 0.0, isLit: false),
                    count: dotCount
                )
            )
        }

        // Планирование циклов и финального раската (`_planTimeline` в `Interlude.js`, строки 104–137)
        var finalDur = max(minFinalRollSec, duration * finalRollPortion)
        if finalDur > duration * 0.5 {
            finalDur = max(1.1, duration * 0.38)
        }
        let isShort = duration < idealRollSec * 1.45

        let loopPeriod: Double
        let finalStart: Double
        let finalDuration: Double

        if isShort {
            loopPeriod = duration
            finalStart = 0.0
            finalDuration = duration
        } else {
            var loopDur = duration - finalDur
            var nCycles = max(1, Int(round(loopDur / idealRollSec)))
            var period = loopDur / Double(nCycles)
            if period < 1.5 {
                nCycles = max(1, Int(floor(loopDur / 1.5)))
                period = loopDur / Double(max(1, nCycles))
            } else if period > 3.0 {
                nCycles = max(1, Int(ceil(loopDur / 3.0)))
                period = loopDur / Double(nCycles)
            }
            loopDur = Double(nCycles) * period
            finalDur = max(0.9, duration - loopDur)
            loopPeriod = period
            finalStart = loopDur
            finalDuration = finalDur
        }

        let visualActive = relativeTime >= 0.0 && relativeTime <= duration
        let isExiting = relativeTime > duration && relativeTime <= duration + exitOverlapSec

        // Плавное раскрытие/схлопывание высоты контейнера без рывка соседних строк на 1 кадре
        let expansion: Double = {
            if relativeTime < 0.0 {
                guard leadInWindow > 0.01 else { return 1.0 }
                return smootherstep((relativeTime + leadInWindow) / leadInWindow)
            }
            if relativeTime <= duration + exitOverlapSec * 0.35 {
                return 1.0
            }
            let collapseSpan = exitOverlapSec * 0.65 + collapseTailSec
            let u = clamp((relativeTime - (duration + exitOverlapSec * 0.35)) / max(0.15, collapseSpan), 0.0, 1.0)
            return 1.0 - smootherstep(u)
        }()

        let t = clamp(relativeTime, 0.0, duration)
        var crest: Double = 0.0
        var phase = "idle"

        if visualActive {
            if isShort || t >= finalStart {
                phase = "final"
                let u = clamp((t - finalStart) / max(1e-4, finalDuration), 0.0, 1.0)
                crest = crestFromProgress(u, isFinal: true)
                if u > 0.88 {
                    crest = 2.35 + (u - 0.88) * 0.40
                }
            } else {
                phase = "loop"
                let animT = t / max(1e-4, loopPeriod)
                let u = animT - floor(animT + 1e-9)
                crest = crestFromProgress(u, isFinal: false)
                let toFinal = finalStart - t
                let blend = min(0.45, loopPeriod * 0.40)
                if blend > 0.0 && toFinal < blend && toFinal >= 0.0 {
                    let w = 1.0 - smootherstep(toFinal / blend)
                    crest = crest * (1.0 - w)
                    phase = "blend"
                }
            }
        } else if isExiting {
            phase = "exit"
            crest = 2.40
        }

        var mainScale: Double = 0.0
        var mainOpacity: Double = 0.0

        if relativeTime < 0.0 {
            let preIn = leadInWindow > 0.01 ? smootherstep((relativeTime + leadInWindow) / leadInWindow) : 0.0
            mainOpacity = 0.35 * preIn
            mainScale = 0.86 + 0.10 * preIn
        } else if visualActive {
            let edgeIn = min(0.40, duration * 0.09)
            let inA = smootherstep(clamp(t / max(0.05, edgeIn), 0.0, 1.0))
            mainOpacity = startTime <= 0.05 ? 1.0 : max(0.94, inA)
            mainScale = 0.96 + 0.08 * inA
            if phase == "loop" {
                let pulse = 0.5 + 0.5 * sin((t / max(0.1, loopPeriod)) * .pi * 2.0)
                mainScale *= (0.985 + 0.03 * pulse)
            }
        } else if isExiting {
            let u = clamp((relativeTime - duration) / max(0.12, exitOverlapSec), 0.0, 1.0)
            let fade = 1.0 - smootherstep(u)
            mainOpacity = fade
            mainScale = 0.98 * (0.88 + 0.12 * fade)
        }

        let effectiveGroupOpacity = easeSinOut(mainOpacity)
        let isCountdown = (phase == "final" || phase == "exit")

        var dotStates: [InterludeDotVisualState] = []
        dotStates.reserveCapacity(dotCount)

        for i in 0..<dotCount {
            if !visualActive && !isExiting && relativeTime >= 0.0 {
                dotStates.append(InterludeDotVisualState(scale: 0.70, yOffset: 0.0, glow: 0.0, opacity: 0.0, isLit: false))
            } else {
                var target = marbleAt(index: i, crest: crest)
                if isExiting {
                    let u = clamp((relativeTime - duration) / max(0.12, exitOverlapSec), 0.0, 1.0)
                    let sm = smootherstep(u)
                    let k = 1.0 - sm * 0.55
                    target.scale *= k
                    target.yOffset *= k
                    target.glow *= (1.0 - sm * 0.70)
                    target.opacity *= (0.50 + 0.50 * (1.0 - sm))
                }
                dotStates.append(target)
            }
        }

        return InterludeFrameState(
            isVisible: expansion > 0.005,
            expansionProgress: expansion,
            groupScale: mainScale,
            groupOpacity: effectiveGroupOpacity,
            isCountdownPhase: isCountdown,
            dots: dotStates
        )
    }
}
