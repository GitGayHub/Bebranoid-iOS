import SwiftUI
#if canImport(UIKit)
import UIKit
import QuartzCore
#endif

/// Ключ сбора статических координат строк внутри контента `ScrollView` (`LyricsScrollContent`).
/// Так как система координат привязана к внутреннему `VStack`, фреймы строк не меняются во время скролла
/// и пересчитываются только при смене песни, размера шрифта или перевода — ноль нагрузки на 120 FPS скролл!
struct LyricNodeFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func reportLyricNodeFrame(id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: LyricNodeFramePreferenceKey.self,
                    value: [id: geo.frame(in: .named("LyricsScrollContent"))]
                )
            }
        )
    }
}

/// Однострочный раскладчик слогов/слов караоке (`1 строка` без переноса на второй ряд)
struct SingleLineSyllableRowLayout: Layout {
    var horizontalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0

        for (idx, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            totalWidth += size.width
            if idx > 0 {
                totalWidth += horizontalSpacing
            }
            maxHeight = max(maxHeight, size.height)
        }

        let maxAllowed = proposal.width ?? totalWidth
        return CGSize(width: min(maxAllowed, totalWidth), height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let y = bounds.minY + (bounds.height - size.height) * 0.5
            subview.place(
                at: CGPoint(x: currentX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + horizontalSpacing
        }
    }
}

/// Расчёт точного коэффициента масштабирования (`fitScale`), чтобы любая длинная строка гарантированно помещалась в **1 строку**
enum SingleLineLyricsFitHelper {
    static func fitScaleForSyllables(
        _ syllables: [BeautifulSyllableMetadata],
        baseFontSize: CGFloat,
        baseSpacing: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        guard !syllables.isEmpty, availableWidth > 40 else { return 1.0 }

        #if canImport(UIKit)
        let baseSysFont = UIFont.systemFont(ofSize: baseFontSize, weight: .bold)
        let roundedFont: UIFont = {
            if let desc = baseSysFont.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: desc, size: baseFontSize)
            }
            return baseSysFont
        }()
        let attrs: [NSAttributedString.Key: Any] = [.font: roundedFont]
        var measuredWordsWidth: CGFloat = 0
        for syl in syllables {
            measuredWordsWidth += ceil((syl.text as NSString).size(withAttributes: attrs).width)
        }
        let spacingsWidth = CGFloat(max(0, syllables.count - 1)) * baseSpacing
        let totalNaturalWidth = (measuredWordsWidth + spacingsWidth) * 1.045 + 4.0
        #else
        let totalChars = syllables.reduce(0) { $0 + $1.text.count }
        let spacingsWidth = CGFloat(max(0, syllables.count - 1)) * baseSpacing
        let totalNaturalWidth = CGFloat(totalChars) * baseFontSize * 0.58 + spacingsWidth + 6.0
        #endif

        if totalNaturalWidth <= availableWidth {
            return 1.0
        }
        return max(0.30, min(1.0, availableWidth / totalNaturalWidth))
    }
}

#if canImport(UIKit)
/// Нативный 120 Гц ProMotion-движок прокрутки `UIScrollView` на базе аналитической пружины `Spring`.
/// Исключает ступенчатые рывки `ScrollViewProxy.scrollTo`, сохраняет инерцию скорости при быстрых переходах строк
/// и мгновенно уступает управление пальцу пользователя при касании экрана.
struct LyricsSmoothScrollBridge: UIViewRepresentable {
    let targetNodeId: String?
    let nodeFrames: [String: CGRect]
    let documentSignature: String
    let syncTriggerToken: Int
    let isPlainLyrics: Bool
    @Binding var isUserBrowsing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isUserBrowsing: $isUserBrowsing)
    }

    func makeUIView(context: Context) -> UIView {
        let probeView = ScrollViewProbeUIView()
        probeView.isUserInteractionEnabled = false
        probeView.backgroundColor = .clear
        let coordinator = context.coordinator
        probeView.onMoveToWindowCallback = { [weak probeView, weak coordinator] in
            guard let probeView, let coordinator else { return }
            coordinator.attachIfNeeded(from: probeView)
        }
        return probeView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isUserBrowsingBinding = $isUserBrowsing
        coordinator.isPlainLyrics = isPlainLyrics
        coordinator.nodeFrames = nodeFrames
        coordinator.attachIfNeeded(from: uiView)

        let docChanged = coordinator.lastDocumentSignature != documentSignature
        if docChanged {
            coordinator.lastDocumentSignature = documentSignature
            coordinator.lastTargetNodeId = targetNodeId
            coordinator.lastSyncTriggerToken = syncTriggerToken
            coordinator.scrollToNode(id: targetNodeId, animated: false)
            return
        }

        if coordinator.lastSyncTriggerToken != syncTriggerToken {
            coordinator.lastSyncTriggerToken = syncTriggerToken
            coordinator.lastTargetNodeId = targetNodeId
            coordinator.scrollToNode(id: targetNodeId, animated: true)
            return
        }

        if coordinator.lastTargetNodeId != targetNodeId {
            coordinator.lastTargetNodeId = targetNodeId
            if !isUserBrowsing && !isPlainLyrics {
                coordinator.scrollToNode(id: targetNodeId, animated: true)
            }
        } else if !isUserBrowsing && !isPlainLyrics && !coordinator.hasPerformedInitialPositioning {
            coordinator.scrollToNode(id: targetNodeId, animated: false)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    private final class ScrollViewProbeUIView: UIView {
        var onMoveToWindowCallback: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                onMoveToWindowCallback?()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var isUserBrowsingBinding: Binding<Bool>
        var isPlainLyrics: Bool = false
        var nodeFrames: [String: CGRect] = [:]
        var lastDocumentSignature: String = ""
        var lastTargetNodeId: String? = nil
        var lastSyncTriggerToken: Int = 0
        var hasPerformedInitialPositioning: Bool = false

        private weak var scrollView: UIScrollView?
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var spring = Spring(initialValue: 0.0, dampingRatio: 0.96, frequency: 1.38)
        private var wasUserTouchingLastFrame: Bool = false
        private var autoResumeTask: Task<Void, Never>? = nil

        init(isUserBrowsing: Binding<Bool>) {
            self.isUserBrowsingBinding = isUserBrowsing
            super.init()
        }

        func attachIfNeeded(from view: UIView) {
            if let existing = scrollView, existing.window != nil {
                ensureDisplayLinkRunning()
                return
            }
            var cursor: UIView? = view.superview
            while let current = cursor {
                if let found = current as? UIScrollView {
                    scrollView = found
                    let currentY = Double(found.contentOffset.y)
                    spring.setGoal(currentY, replaceVelocity: true)
                    ensureDisplayLinkRunning()
                    if !hasPerformedInitialPositioning, let target = lastTargetNodeId {
                        scrollToNode(id: target, animated: false)
                    }
                    return
                }
                cursor = current.superview
            }
        }

        private func computeClampedOffsetY(for nodeId: String, in sv: UIScrollView) -> CGFloat? {
            guard let rect = nodeFrames[nodeId], sv.bounds.height > 20 else { return nil }
            let desiredY = rect.midY - sv.bounds.height * 0.34
            let minY = -sv.adjustedContentInset.top
            let maxY = max(minY, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
            return min(maxY, max(minY, desiredY))
        }

        func scrollToNode(id: String?, animated: Bool) {
            guard !isPlainLyrics, let id, let sv = scrollView else { return }
            guard let goalY = computeClampedOffsetY(for: id, in: sv) else { return }
            hasPerformedInitialPositioning = true

            if !animated {
                spring.setGoal(Double(goalY), replaceVelocity: true)
                sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: goalY), animated: false)
                return
            }

            // Сохраняем текущую инерцию `spring.velocity`, если скролл уже плавно скользит к предыдущей строке!
            if spring.sleeping {
                spring.position = Double(sv.contentOffset.y)
                spring.velocity = 0.0
            }
            spring.setGoal(Double(goalY), replaceVelocity: false)
            ensureDisplayLinkRunning()
        }

        private func ensureDisplayLinkRunning() {
            guard displayLink == nil else { return }
            let proxy = WeakDisplayLinkTarget(coordinator: self)
            let link = CADisplayLink(target: proxy, selector: #selector(WeakDisplayLinkTarget.step(_:)))
            if #available(iOS 15.0, *) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            }
            link.add(to: .main, forMode: .common)
            lastTimestamp = 0
            displayLink = link
        }

        fileprivate func handleFrame(_ link: CADisplayLink) {
            guard let sv = scrollView else { return }
            let now = link.timestamp
            let dt: Double = (lastTimestamp > 0) ? min(0.05, max(1.0 / 240.0, now - lastTimestamp)) : (1.0 / 120.0)
            lastTimestamp = now

            if isPlainLyrics {
                return
            }

            let userActive = sv.isTracking || sv.isDragging || sv.isDecelerating
            if userActive {
                wasUserTouchingLastFrame = true
                autoResumeTask?.cancel()
                spring.setGoal(Double(sv.contentOffset.y), replaceVelocity: true)
                if !isUserBrowsingBinding.wrappedValue {
                    isUserBrowsingBinding.wrappedValue = true
                }
                return
            }

            if wasUserTouchingLastFrame {
                wasUserTouchingLastFrame = false
                spring.setGoal(Double(sv.contentOffset.y), replaceVelocity: true)
                scheduleIdleAutoResume()
            }

            guard !isUserBrowsingBinding.wrappedValue else { return }

            // Подстраиваем цель на лету, если `contentSize` обновился после рендера перевода
            if let activeId = lastTargetNodeId, let updatedGoal = computeClampedOffsetY(for: activeId, in: sv) {
                if abs(Double(updatedGoal) - spring.finalPosition) > 0.5 {
                    spring.setGoal(Double(updatedGoal), replaceVelocity: false)
                }
            }

            guard !spring.sleeping else { return }
            let nextY = CGFloat(spring.update(deltaTime: dt))
            if abs(sv.contentOffset.y - nextY) > 0.08 {
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: nextY)
            }
        }

        private func scheduleIdleAutoResume() {
            autoResumeTask?.cancel()
            autoResumeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 4_200_000_000)
                guard !Task.isCancelled, let self else { return }
                if self.isUserBrowsingBinding.wrappedValue {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        self.isUserBrowsingBinding.wrappedValue = false
                    }
                    self.scrollToNode(id: self.lastTargetNodeId, animated: true)
                }
            }
        }

        func teardown() {
            autoResumeTask?.cancel()
            displayLink?.invalidate()
            displayLink = nil
            scrollView = nil
        }
    }

    private final class WeakDisplayLinkTarget: NSObject {
        weak var coordinator: Coordinator?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
        }

        @MainActor
        @objc func step(_ link: CADisplayLink) {
            coordinator?.handleFrame(link)
        }
    }
}
#endif
