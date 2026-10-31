import SwiftUI
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

/// Менеджер 3D-наклона обложки в полноэкранном плеере по данным гироскопа и акселерометра (`CMMotionManager`).
/// Работает строго тогда, когда открыт полноэкранный плеер и включена настройка «3D-вращение обложки гироскопом»,
/// не расходуя заряд батареи в фоне. Автоматически адаптирует нейтральный угол удержания телефона (сидя, стоя или лёжа).
@MainActor
public final class GyroscopeMotionManager: ObservableObject {
    @Published public private(set) var tiltXDegrees: Double = 0.0
    @Published public private(set) var tiltYDegrees: Double = 0.0
    @Published public private(set) var specularUnitOffset: CGSize = .zero

    #if canImport(CoreMotion) && os(iOS)
    private let motionManager = CMMotionManager()
    #endif
    private var isActive: Bool = false
    private var hasCalibratedBaseline: Bool = false
    private var baselinePitch: Double = 0.0
    private var baselineRoll: Double = 0.0

    /// Максимальная амплитуда 3D-поворота обложки (в градусах)
    private let maxTiltDegrees: Double = 20.0

    public init() {}

    public func setActive(_ active: Bool) {
        if active {
            startIfNeeded()
        } else {
            stop()
        }
    }

    public func recalibrateCenter() {
        hasCalibratedBaseline = false
    }

    private func startIfNeeded() {
        guard !isActive else { return }
        isActive = true
        hasCalibratedBaseline = false

        #if canImport(CoreMotion) && os(iOS)
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.processDeviceMotion(
                pitchRad: motion.attitude.pitch,
                rollRad: motion.attitude.roll,
                rotX: motion.rotationRate.x,
                rotY: motion.rotationRate.y
            )
        }
        #endif
    }

    public func stop() {
        guard isActive || abs(tiltXDegrees) > 0.01 || abs(tiltYDegrees) > 0.01 else { return }
        isActive = false
        hasCalibratedBaseline = false
        #if canImport(CoreMotion) && os(iOS)
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        #endif
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            tiltXDegrees = 0.0
            tiltYDegrees = 0.0
            specularUnitOffset = .zero
        }
    }

    private func processDeviceMotion(pitchRad: Double, rollRad: Double, rotX: Double, rotY: Double) {
        if !hasCalibratedBaseline {
            baselinePitch = pitchRad
            baselineRoll = rollRad
            hasCalibratedBaseline = true
        }

        // Медленная адаптация нейтрального угла удержания, чтобы 3D-эффект одинаково удобно работал сидя, стоя и лёжа
        let deltaPitchRad = Self.shortestAngleDelta(from: baselinePitch, to: pitchRad)
        let deltaRollRad = Self.shortestAngleDelta(from: baselineRoll, to: rollRad)
        baselinePitch += deltaPitchRad * 0.008
        baselineRoll += deltaRollRad * 0.008

        // Переводим отклонение + угловую скорость гироскопа в отзывчивый 3D-угол с мягким ограничением tanh
        let rawDegX = -(deltaPitchRad * 180.0 / .pi) * 0.72 - (rotX * 2.4)
        let rawDegY = (deltaRollRad * 180.0 / .pi) * 0.72 + (rotY * 2.4)

        let targetX = tanh(rawDegX / maxTiltDegrees) * maxTiltDegrees
        let targetY = tanh(rawDegY / maxTiltDegrees) * maxTiltDegrees

        let smoothing = 0.22
        let nextX = tiltXDegrees + (targetX - tiltXDegrees) * smoothing
        let nextY = tiltYDegrees + (targetY - tiltYDegrees) * smoothing

        if abs(nextX - tiltXDegrees) > 0.015 || abs(nextY - tiltYDegrees) > 0.015 {
            tiltXDegrees = nextX
            tiltYDegrees = nextY
            specularUnitOffset = CGSize(
                width: nextY / maxTiltDegrees,
                height: -nextX / maxTiltDegrees
            )
        }
    }

    private static func shortestAngleDelta(from a: Double, to b: Double) -> Double {
        var diff = (b - a).truncatingRemainder(dividingBy: 2.0 * .pi)
        if diff > .pi { diff -= 2.0 * .pi }
        if diff < -.pi { diff += 2.0 * .pi }
        return diff
    }
}
