import Foundation

/// Состояние одной из 3 точек инструментального проигрыша (`Interlude`)
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

/// Состояние индикатора инструментального проигрыша (3 точки ожидания и отсчёта 1–2–3)
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

/// Бесшовный C²-непрерывный математический движок 3 точек инструментальной паузы:
/// 1. При долгом ожидании (`remaining > 3.0 с`) — абсолютно ровная непрерывная волна с одинаковым таймингом между точками (без рывков сброса цикла).
/// 2. За `3.0 с` до вступления следующей строки — мягкая подкрутка и плавный отсчёт «раз – два – три – и идём» без скачков прозрачности или высоты.
public enum InterludeEngine {
    public static let dotCount: Int = 3
    public static let steadyWavePeriodSec: Double = 1.80
    public static let countdownWindowSec: Double = 3.0
    public static let leadInSec: Double = 0.26
    public static let exitDissolveSec: Double = 0.42

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    private static func smootherstep(_ t: Double) -> Double {
        let x = clamp(t, 0.0, 1.0)
        return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
    }

    private static func lerp(_ a: Double, _ b: Double, _ w: Double) -> Double {
        a + (b - a) * w
    }

    /// Непрерывная синусоидальная волна одинакового тайминга для длительного ожидания (0 разрывов производной)
    private static func steadyWaitingDot(index i: Int, time t: Double) -> InterludeDotVisualState {
        let omega = (2.0 * .pi) / steadyWavePeriodSec
        let phase = omega * t - Double(i) * ((2.0 * .pi) / 3.0)
        let rawWave = 0.5 + 0.5 * sin(phase)
        let smoothWave = pow(rawWave, 1.55)

        let scale = 0.78 + 0.28 * smoothWave
        let yOffset = -2.1 * smoothWave
        let glow = 0.10 + 0.54 * smoothWave
        let opacity = 0.36 + 0.50 * smoothWave

        return InterludeDotVisualState(
            scale: scale,
            yOffset: yOffset,
            glow: glow,
            opacity: opacity,
            isLit: opacity > 0.65
        )
    }

    /// Плавный 3-секундный отсчёт «раз – два – три» перед вступлением вокала (`u` от `0.0` до `1.0`)
    private static func countdownDot(index i: Int, progress u: Double) -> InterludeDotVisualState {
        let step = clamp(u, 0.0, 1.0) * 3.0
        let startBeat = Double(i) * 0.94
        let fill = smootherstep((step - startBeat) / 0.88)

        // Лёгкий импульс в момент загорания конкретного шага (1 -> 2 -> 3)
        let crestCenter = Double(i) * 0.94 + 0.62
        let distFromCrest = abs(step - crestCenter)
        let crestRaw = max(0.0, 1.0 - distFromCrest * 1.15)
        let crestPulse = crestRaw * crestRaw * (3.0 - 2.0 * crestRaw)

        // После загорания точки остаются наполненными по нарастающей (1 < 2 < 3), чтобы 3-я точка вела прямо в строку
        let settledOpacity = 0.78 + Double(i) * 0.10
        let settledScale = 0.96 + Double(i) * 0.06

        let opacity = lerp(0.28, settledOpacity, fill) + 0.08 * crestPulse * fill
        let scale = lerp(0.74, settledScale, fill) + 0.14 * crestPulse * fill
        let yOffset = (-1.4 * fill) + (-1.6 * crestPulse * fill)
        let glow = (0.24 + Double(i) * 0.14) * fill + 0.36 * crestPulse * fill

        return InterludeDotVisualState(
            scale: clamp(scale, 0.65, 1.28),
            yOffset: yOffset,
            glow: clamp(glow, 0.0, 1.0),
            opacity: clamp(opacity, 0.0, 1.0),
            isLit: fill > 0.55
        )
    }

    /// Рассчитывает состояние каждой из 3 точек в момент времени `timestamp` для паузы `[startTime, endTime]`
    public static func evaluate(
        startTime: Double,
        endTime: Double,
        timestamp: Double
    ) -> InterludeFrameState {
        let duration = max(0.20, endTime - startTime)
        let relativeTime = timestamp - startTime
        let effectiveLeadIn = startTime <= 0.05 ? 0.0 : leadInSec

        if relativeTime < -effectiveLeadIn || relativeTime > duration + exitDissolveSec {
            return InterludeFrameState(
                isVisible: false,
                expansionProgress: 0.0,
                groupScale: 0.0,
                groupOpacity: 0.0,
                isCountdownPhase: false,
                dots: Array(
                    repeating: InterludeDotVisualState(scale: 0.74, yOffset: 0, glow: 0, opacity: 0.0, isLit: false),
                    count: dotCount
                )
            )
        }

        // Раскрытие и схлопывание высоты контейнера только на краях паузы; в середине строго 1.0 (0 пересчётов VStack!)
        let expansion: Double = {
            if relativeTime < 0.0 {
                guard effectiveLeadIn > 0.01 else { return 1.0 }
                return smootherstep((relativeTime + effectiveLeadIn) / effectiveLeadIn)
            }
            if relativeTime <= duration {
                return 1.0
            }
            let exitU = clamp((relativeTime - duration) / exitDissolveSec, 0.0, 1.0)
            return 1.0 - smootherstep(exitU)
        }()

        let clampedT = clamp(relativeTime, 0.0, duration)
        let countdownSpan = min(countdownWindowSec, duration)
        let countdownStart = max(0.0, duration - countdownSpan)
        let isShortInterlude = duration <= countdownWindowSec + 0.25

        // Плавный вес перехода из ровного ожидания в 3-секундный отсчёт «раз-два-три»
        let countdownWeight: Double = {
            if isShortInterlude {
                return 1.0
            }
            let blendHalf = 0.28
            return smootherstep((clampedT - (countdownStart - blendHalf)) / (blendHalf * 2.0))
        }()

        let countdownProgress = clamp((clampedT - countdownStart) / max(0.08, countdownSpan), 0.0, 1.0)

        let envelope: Double = {
            if effectiveLeadIn <= 0.01 && relativeTime >= 0.0 && relativeTime <= duration {
                return smootherstep(clampedT / min(0.22, max(0.08, duration * 0.15)))
            }
            return expansion
        }()

        let groupOpacity = envelope
        let groupScale = 0.88 + 0.12 * envelope
        let exitFade: Double = relativeTime > duration ? expansion : 1.0

        var dotStates: [InterludeDotVisualState] = []
        dotStates.reserveCapacity(dotCount)

        for i in 0..<dotCount {
            let waitTime = min(relativeTime, duration)
            let waitDot = steadyWaitingDot(index: i, time: waitTime)
            let countDot = countdownDot(index: i, progress: countdownProgress)

            let blendedScale = lerp(waitDot.scale, countDot.scale, countdownWeight) * (0.86 + 0.14 * exitFade)
            let blendedY = lerp(waitDot.yOffset, countDot.yOffset, countdownWeight) * exitFade
            let blendedGlow = lerp(waitDot.glow, countDot.glow, countdownWeight) * exitFade
            let blendedOpacity = lerp(waitDot.opacity, countDot.opacity, countdownWeight) * exitFade

            dotStates.append(
                InterludeDotVisualState(
                    scale: blendedScale,
                    yOffset: blendedY,
                    glow: blendedGlow,
                    opacity: blendedOpacity,
                    isLit: blendedOpacity > 0.66
                )
            )
        }

        return InterludeFrameState(
            isVisible: expansion > 0.004,
            expansionProgress: expansion,
            groupScale: groupScale,
            groupOpacity: groupOpacity,
            isCountdownPhase: countdownWeight >= 0.5,
            dots: dotStates
        )
    }
}
