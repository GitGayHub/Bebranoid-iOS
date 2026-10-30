import Foundation

/// Состояние одной из 3 точек проигрыша (`Interlude.js`)
public struct InterludeDotVisualState: Equatable, Sendable {
    public var scale: Double
    public var yOffset: Double
    public var glow: Double
    public var opacity: Double

    public init(scale: Double, yOffset: Double, glow: Double, opacity: Double) {
        self.scale = scale
        self.yOffset = yOffset
        self.glow = glow
        self.opacity = opacity
    }
}

/// Состояние всего индикатора инструментального проигрыша (3 точки с «marble roll» волной)
public struct InterludeFrameState: Equatable, Sendable {
    public var isVisible: Bool
    public var groupScale: Double
    public var groupOpacity: Double
    public var dots: [InterludeDotVisualState]
}

/// Точный 1:1 порт `src/beautiful-lyrics/Interlude.js`.
/// Рассчитывает фазы волны «marble roll» по 3 точкам во время инструментальных пауз.
public enum InterludeEngine {
    public static let dotCount: Int = 3
    public static let idealRollSec: Double = 2.2
    public static let finalRollPortion: Double = 0.22
    public static let minFinalRollSec: Double = 1.6
    public static let exitOverlapSec: Double = 0.75

    /// Рассчитывает целевое состояние каждой из 3 точек в момент времени `timestamp` для паузы `[startTime, endTime]`
    public static func evaluate(
        startTime: Double,
        endTime: Double,
        timestamp: Double
    ) -> InterludeFrameState {
        let totalDuration = max(0.5, endTime - startTime)
        let elapsed = timestamp - startTime

        if elapsed < -0.15 || elapsed > totalDuration + exitOverlapSec {
            return InterludeFrameState(
                isVisible: false,
                groupScale: 0.0,
                groupOpacity: 0.0,
                dots: Array(repeating: InterludeDotVisualState(scale: 0.75, yOffset: 0, glow: 0, opacity: 0.25), count: dotCount)
            )
        }

        // Вычисляем количество циклов волны (rolls) и длительность финального подъёма
        let finalRollDuration = max(minFinalRollSec, totalDuration * finalRollPortion)
        let regularTime = max(0.0, totalDuration - finalRollDuration)
        let rollCycles = max(1, Int(round(regularTime / idealRollSec)))
        let singleRollDuration = regularTime > 0 ? (regularTime / Double(rollCycles)) : totalDuration

        // Положение «гребня волны» (crest) в диапазоне [0 ... dotCount]
        let crest: Double
        if elapsed < 0 {
            crest = -1.0
        } else if elapsed < regularTime && singleRollDuration > 0.01 {
            let cycleProgress = (elapsed.truncatingRemainder(dividingBy: singleRollDuration)) / singleRollDuration
            crest = cycleProgress * Double(dotCount + 1) - 0.5
        } else {
            // Финальный подъём перед вступлением вокала
            let finalElapsed = max(0.0, elapsed - regularTime)
            let finalProgress = min(1.0, finalElapsed / max(0.1, finalRollDuration))
            crest = finalProgress * Double(dotCount)
        }

        // Фаза выхода (`exitOverlapSec` = 0.75 с)
        let exitProgress: Double
        if elapsed >= totalDuration {
            exitProgress = min(1.0, (elapsed - totalDuration) / exitOverlapSec)
        } else {
            exitProgress = 0.0
        }

        let groupScale = elapsed < 0 ? 0.6 : (1.0 - exitProgress * 0.45)
        let groupOpacity = elapsed < 0 ? 0.0 : (1.0 - exitProgress)

        var dotStates: [InterludeDotVisualState] = []
        for i in 0..<dotCount {
            let dotPos = Double(i)
            let dist = abs(dotPos - crest)
            let influence = max(0.0, 1.0 - dist / 1.15)
            let smooth = influence * influence * (3.0 - 2.0 * influence)

            // Во время финального раската уже пройденные точки остаются яркими
            let isInFinalPhase = elapsed >= regularTime
            let heldFactor: Double = (isInFinalPhase && dotPos <= crest) ? 0.85 : 0.0
            let effective = max(smooth, heldFactor)

            let scale = 0.82 + 0.36 * effective
            let yOffset = -5.5 * smooth
            let glow = effective
            let opacity = (0.32 + 0.68 * effective) * groupOpacity

            dotStates.append(
                InterludeDotVisualState(
                    scale: scale,
                    yOffset: yOffset,
                    glow: glow,
                    opacity: opacity
                )
            )
        }

        return InterludeFrameState(
            isVisible: groupOpacity > 0.01,
            groupScale: groupScale,
            groupOpacity: groupOpacity,
            dots: dotStates
        )
    }
}
