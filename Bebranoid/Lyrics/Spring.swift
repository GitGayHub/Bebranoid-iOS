import Foundation

/// Точный 1:1 математический порт `src/beautiful-lyrics/spring.js`.
/// Решает дифференциальное уравнение пружины для всех трёх режимов затухания:
/// - критическое (`dampingRatio == 1`)
/// - колебательное (`dampingRatio < 1`)
/// - апериодическое (`dampingRatio > 1`)
public struct Spring: Sendable {
    public static let sleepEpsilon: Double = 5e-4
    public static let sleepVelocityEpsilon: Double = 5e-3

    public var position: Double
    public var velocity: Double
    public var finalPosition: Double
    public var dampingRatio: Double
    public var frequency: Double
    public var sleeping: Bool

    public init(
        initialValue: Double = 0.0,
        dampingRatio: Double = 1.0,
        frequency: Double = 1.0
    ) {
        self.position = initialValue
        self.velocity = 0.0
        self.finalPosition = initialValue
        self.dampingRatio = dampingRatio
        self.frequency = frequency
        self.sleeping = true
    }

    public mutating func setGoal(_ goal: Double, replaceVelocity: Bool = false) {
        if replaceVelocity {
            self.position = goal
            self.velocity = 0.0
            self.finalPosition = goal
            self.sleeping = true
            return
        }
        if abs(self.finalPosition - goal) > 1e-9 {
            self.finalPosition = goal
            self.sleeping = false
        }
    }

    public mutating func setPosition(_ value: Double) {
        self.position = value
        self.velocity = 0.0
        self.sleeping = abs(self.finalPosition - value) <= Self.sleepEpsilon
    }

    /// Обновляет состояние пружины на шаг `deltaTime` (в секундах) и возвращает новую позицию
    @discardableResult
    public mutating func update(deltaTime dt: Double) -> Double {
        if sleeping || dt <= 0.0 {
            return position
        }

        let radialFrequency = frequency * 2.0 * Double.pi
        let offset = position - finalPosition
        let v0 = velocity
        let d = dampingRatio

        var newOffset: Double = 0.0
        var newVelocity: Double = 0.0

        if abs(d - 1.0) < 1e-7 {
            // Critically damped (d == 1)
            let expTerm = exp(-radialFrequency * dt)
            let c1 = offset
            let c2 = v0 + radialFrequency * offset
            newOffset = (c1 + c2 * dt) * expTerm
            newVelocity = (c2 - radialFrequency * (c1 + c2 * dt)) * expTerm
        } else if d < 1.0 {
            // Underdamped (d < 1)
            let dampedFreq = radialFrequency * sqrt(1.0 - d * d)
            let expTerm = exp(-d * radialFrequency * dt)
            let cosTerm = cos(dampedFreq * dt)
            let sinTerm = sin(dampedFreq * dt)

            let c1 = offset
            let c2 = (v0 + d * radialFrequency * offset) / dampedFreq

            newOffset = expTerm * (c1 * cosTerm + c2 * sinTerm)
            newVelocity = expTerm * (
                (c2 * dampedFreq - c1 * d * radialFrequency) * cosTerm -
                (c1 * dampedFreq + c2 * d * radialFrequency) * sinTerm
            )
        } else {
            // Overdamped (d > 1)
            let rootTerm = radialFrequency * sqrt(d * d - 1.0)
            let r1 = -d * radialFrequency + rootTerm
            let r2 = -d * radialFrequency - rootTerm

            let denom = r1 - r2
            let c2 = (v0 - r1 * offset) / denom
            let c1 = offset - c2

            let exp1 = exp(r1 * dt)
            let exp2 = exp(r2 * dt)

            newOffset = c1 * exp1 + c2 * exp2
            newVelocity = c1 * r1 * exp1 + c2 * r2 * exp2
        }

        position = finalPosition + newOffset
        velocity = newVelocity

        if abs(position - finalPosition) <= Self.sleepEpsilon && abs(velocity) <= Self.sleepVelocityEpsilon {
            position = finalPosition
            velocity = 0.0
            sleeping = true
        }

        return position
    }
}
