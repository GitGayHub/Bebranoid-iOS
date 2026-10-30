import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Нативный менеджер тактильного отклика iPhone (`UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator`, `UINotificationFeedbackGenerator`).
@MainActor
public final class HapticsManager {
    public static let shared = HapticsManager()
    public var isEnabled: Bool = true

    private init() {}

    public func lightTap() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    public func mediumImpact() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }

    public func softSelection() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    public func successNotification() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}
