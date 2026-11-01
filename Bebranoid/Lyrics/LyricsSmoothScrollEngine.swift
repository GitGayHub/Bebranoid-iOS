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

/// Расчёт и потокобезопасное кэширование точного коэффициента масштабирования (`fitScale`),
/// чтобы любая длинная строка гарантированно помещалась в **1 строку** без повторных замеров `NSString.size` на каждом кадре!
enum SingleLineLyricsFitHelper {
    private static let cacheLock = NSLock()
    private static var scaleCache: [String: CGFloat] = [:]

    static func fitScaleForText(
        _ text: String,
        baseFontSize: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty, availableWidth > 40 else { return 1.0 }
        let cacheKey = "txt|\(text)|\(Int(baseFontSize * 10))|\(Int(availableWidth))"
        cacheLock.lock()
        if let hit = scaleCache[cacheKey] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        #if canImport(UIKit)
        let baseSysFont = UIFont.systemFont(ofSize: baseFontSize, weight: .bold)
        let roundedFont: UIFont = {
            if let desc = baseSysFont.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: desc, size: baseFontSize)
            }
            return baseSysFont
        }()
        let measured = ceil((text as NSString).size(withAttributes: [.font: roundedFont]).width) * 1.045 + 4.0
        #else
        let measured = CGFloat(text.count) * baseFontSize * 0.58 + 6.0
        #endif

        let result: CGFloat = (measured <= availableWidth) ? 1.0 : max(0.30, min(1.0, availableWidth / measured))
        cacheLock.lock()
        if scaleCache.count > 2500 {
            scaleCache.removeAll(keepingCapacity: true)
        }
        scaleCache[cacheKey] = result
        cacheLock.unlock()
        return result
    }

    static func fitScaleForSyllables(
        _ syllables: [BeautifulSyllableMetadata],
        baseFontSize: CGFloat,
        baseSpacing: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        guard !syllables.isEmpty, availableWidth > 40 else { return 1.0 }
        let cacheKey = "syl|\(syllables.first?.id ?? "")|\(syllables.count)|\(Int(baseFontSize * 10))|\(Int(availableWidth))"
        cacheLock.lock()
        if let hit = scaleCache[cacheKey] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

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

        let result: CGFloat = (totalNaturalWidth <= availableWidth)
            ? 1.0
            : max(0.30, min(1.0, availableWidth / totalNaturalWidth))

        cacheLock.lock()
        if scaleCache.count > 2500 {
            scaleCache.removeAll(keepingCapacity: true)
        }
        scaleCache[cacheKey] = result
        cacheLock.unlock()
        return result
    }
}

#if canImport(UIKit)
/// Нативный ProMotion-движок прокрутки `UIScrollView` на базе аналитической пружины `Spring`.
/// Автоматически усыпляет `CADisplayLink` (`isPaused = true`) между переходами строк (0% расхода CPU в покое),
/// обеспечивает сливочное перетекание между строками и 100% безотказный возврат по кнопке «Синхр.».
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
        let framesCountChanged = coordinator.nodeFrames.count != nodeFrames.count
        coordinator.nodeFrames = nodeFrames
        coordinator.attachIfNeeded(from: uiView)

        let docChanged = coordinator.lastDocumentSignature != documentSignature
        if docChanged {
            coordinator.lastDocumentSignature = documentSignature
            coordinator.lastTargetNodeId = targetNodeId
            coordinator.lastSyncTriggerToken = syncTriggerToken
            coordinator.hasPerformedInitialPositioning = false
            coordinator.scrollToNode(id: targetNodeId, animated: false)
            return
        }

        if coordinator.lastSyncTriggerToken != syncTriggerToken {
            coordinator.lastSyncTriggerToken = syncTriggerToken
            coordinator.lastTargetNodeId = targetNodeId
            coordinator.forceResync(to: targetNodeId)
            return
        }

        if coordinator.lastTargetNodeId != targetNodeId {
            coordinator.lastTargetNodeId = targetNodeId
            if !isUserBrowsing && !isPlainLyrics {
                coordinator.scrollToNode(id: targetNodeId, animated: true)
            }
        } else if !isUserBrowsing && !isPlainLyrics && (!coordinator.hasPerformedInitialPositioning || framesCountChanged) {
            coordinator.scrollToNode(id: targetNodeId, animated: coordinator.hasPerformedInitialPositioning)
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
        private var hasAttachedPanTarget: Bool = false
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        // Мягкая сливочная пружина Apple Music (`dampingRatio: 0.98`, `frequency: 1.08`) без резких рывков
        private var spring = Spring(initialValue: 0.0, dampingRatio: 0.98, frequency: 1.08)
        private var wasUserTouchingLastFrame: Bool = false
        private var ignoreResidualDecelerationUntil: CFTimeInterval = 0
        private var autoResumeTask: Task<Void, Never>? = nil

        init(isUserBrowsing: Binding<Bool>) {
            self.isUserBrowsingBinding = isUserBrowsing
            super.init()
        }

        func attachIfNeeded(from view: UIView) {
            if let existing = scrollView, existing.window != nil {
                ensureDisplayLinkCreated()
                return
            }
            var cursor: UIView? = view.superview
            while let current = cursor {
                if let found = current as? UIScrollView {
                    if scrollView !== found {
                        hasAttachedPanTarget = false
                    }
                    scrollView = found
                    if !hasAttachedPanTarget {
                        found.panGestureRecognizer.addTarget(self, action: #selector(handleScrollPanGesture(_:)))
                        hasAttachedPanTarget = true
                    }
                    let currentY = Double(found.contentOffset.y)
                    spring.setGoal(currentY, replaceVelocity: true)
                    ensureDisplayLinkCreated()
                    if !hasPerformedInitialPositioning {
                        scrollToNode(id: lastTargetNodeId, animated: false)
                    }
                    return
                }
                cursor = current.superview
            }
        }

        @objc private func handleScrollPanGesture(_ gesture: UIPanGestureRecognizer) {
            guard !isPlainLyrics else { return }
            switch gesture.state {
            case .began, .changed:
                ignoreResidualDecelerationUntil = 0
                autoResumeTask?.cancel()
                if !isUserBrowsingBinding.wrappedValue {
                    isUserBrowsingBinding.wrappedValue = true
                }
                wakeDisplayLink()
            default:
                wakeDisplayLink()
            }
        }

        private func computeClampedOffsetY(for nodeId: String?, in sv: UIScrollView) -> CGFloat? {
            guard sv.bounds.height > 20 else { return nil }
            let minY = -sv.adjustedContentInset.top
            let maxY = max(minY, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)

            if let nodeId, let rect = nodeFrames[nodeId] {
                let desiredY = rect.midY - sv.bounds.height * 0.34
                return min(maxY, max(minY, desiredY))
            }
            if nodeId == nil && !nodeFrames.isEmpty {
                return minY
            }
            return nil
        }

        /// Гарантированный возврат к активной строке по кнопке «Синхр.»:
        /// мгновенно гасит остаточную инерцию `UIScrollView`, блокирует ложный `isDecelerating` и плавно доводит пружину до цели!
        func forceResync(to id: String?) {
            guard !isPlainLyrics, let sv = scrollView else { return }
            autoResumeTask?.cancel()
            wasUserTouchingLastFrame = false
            ignoreResidualDecelerationUntil = CACurrentMediaTime() + 0.65

            // Мгновенно останавливаем нативную инерцию UIScrollView в текущей точке
            let frozenOffset = sv.contentOffset
            sv.setContentOffset(frozenOffset, animated: false)

            if isUserBrowsingBinding.wrappedValue {
                isUserBrowsingBinding.wrappedValue = false
            }

            let minY = -sv.adjustedContentInset.top
            let maxY = max(minY, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
            let goalY: CGFloat = {
                if let resolved = computeClampedOffsetY(for: id, in: sv) {
                    return resolved
                }
                if let earliest = nodeFrames.values.min(by: { $0.minY < $1.minY }) {
                    return min(maxY, max(minY, earliest.midY - sv.bounds.height * 0.34))
                }
                return minY
            }()

            hasPerformedInitialPositioning = true
            spring.position = Double(frozenOffset.y)
            spring.velocity = 0.0
            spring.setGoal(Double(goalY), replaceVelocity: false)
            wakeDisplayLink()
        }

        func scrollToNode(id: String?, animated: Bool) {
            guard !isPlainLyrics, let sv = scrollView else { return }
            guard let goalY = computeClampedOffsetY(for: id, in: sv) else { return }
            hasPerformedInitialPositioning = true

            if !animated {
                spring.setGoal(Double(goalY), replaceVelocity: true)
                sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: goalY), animated: false)
                return
            }

            if spring.sleeping {
                spring.position = Double(sv.contentOffset.y)
                spring.velocity = 0.0
            }
            spring.setGoal(Double(goalY), replaceVelocity: false)
            wakeDisplayLink()
        }

        private func ensureDisplayLinkCreated() {
            guard displayLink == nil else { return }
            let proxy = WeakDisplayLinkTarget(coordinator: self)
            let link = CADisplayLink(target: proxy, selector: #selector(WeakDisplayLinkTarget.step(_:)))
            if #available(iOS 15.0, *) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            }
            link.isPaused = false
            link.add(to: .main, forMode: .common)
            lastTimestamp = 0
            displayLink = link
        }

        private func wakeDisplayLink() {
            ensureDisplayLinkCreated()
            if displayLink?.isPaused == true {
                lastTimestamp = 0
                displayLink?.isPaused = false
            }
        }

        fileprivate func handleFrame(_ link: CADisplayLink) {
            guard let sv = scrollView else {
                link.isPaused = true
                return
            }
            if isPlainLyrics {
                link.isPaused = true
                return
            }

            let now = link.timestamp
            let dt: Double = (lastTimestamp > 0) ? min(0.05, max(1.0 / 240.0, now - lastTimestamp)) : (1.0 / 120.0)
            lastTimestamp = now

            let effectiveDecelerating = sv.isDecelerating && (CACurrentMediaTime() >= ignoreResidualDecelerationUntil)
            let userActive = sv.isTracking || sv.isDragging || effectiveDecelerating

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

            if isUserBrowsingBinding.wrappedValue {
                // В режиме ручного просмотра пальцем (после остановки инерции) усыпляем CADisplayLink до авто-возврата или нажатия «Синхр.»!
                link.isPaused = true
                lastTimestamp = 0
                return
            }

            if let updatedGoal = computeClampedOffsetY(for: lastTargetNodeId, in: sv) {
                if abs(Double(updatedGoal) - spring.finalPosition) > 0.5 {
                    spring.setGoal(Double(updatedGoal), replaceVelocity: false)
                }
            }

            if spring.sleeping {
                link.isPaused = true
                lastTimestamp = 0
                return
            }

            let nextY = CGFloat(spring.update(deltaTime: dt))
            if abs(sv.contentOffset.y - nextY) > 0.06 {
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: nextY)
            }
        }

        private func scheduleIdleAutoResume() {
            autoResumeTask?.cancel()
            autoResumeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 4_200_000_000)
                guard !Task.isCancelled, let self else { return }
                if self.isUserBrowsingBinding.wrappedValue {
                    self.forceResync(to: self.lastTargetNodeId)
                }
            }
        }

        func teardown() {
            autoResumeTask?.cancel()
            if let sv = scrollView, hasAttachedPanTarget {
                sv.panGestureRecognizer.removeTarget(self, action: #selector(handleScrollPanGesture(_:)))
            }
            hasAttachedPanTarget = false
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
