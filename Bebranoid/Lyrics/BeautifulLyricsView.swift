import SwiftUI

/// Нативный 120 FPS SwiftUI-рендерер **Beautiful Lyrics** (`src/beautiful-lyrics/BeautifulLyrics.jsx`, `SyllableVocals.js`, `BeautifulLyrics.css`).
/// Ключевые гарантии плавности и эстетики:
/// 1. `VStack` вместо `LazyVStack`: высоты всех строк известны заранее, прокрутка `scrollTo` идёт без единого рывка.
/// 2. Единая вёрстка `SyllableWrappingFlowLayout` для прошлых, активной и будущих строк — строка НИКОГДА не перепрыгивает с 1 ряда на 2 во время пения.
/// 3. Никакой дёрганой «прыгающей» вертикальной анимации слов (`yOffset = 0`, как в десктопном `SyllableVocals.js`): только мягкое сливочное заполнение градиентом слева направо и деликатное свечение.
/// 4. Изоляция `TimelineView` (120 Гц) строго внутри активной строки и активного `Interlude` — неактивные строки не перерисовываются во время скролла.
public struct BeautifulLyricsView: View {
    public let document: ParsedLyricsDocument
    public let nodes: [BeautifulTimelineNode]
    public let currentTime: Double
    public let isPlaying: Bool
    public let liveTimeProvider: () -> Double
    public let accentColor: Color
    public let fontSizePreset: LyricsFontSizePreset
    public let showTranslation: Bool
    public let onSeekToTime: (Double) -> Void

    @State private var activeLineIndex: Int = -1
    @State private var isUserBrowsing: Bool = false
    @State private var autoResumeTask: Task<Void, Never>? = nil
    @State private var selectedPlainLineIndex: Int? = nil

    public init(
        document: ParsedLyricsDocument,
        nodes: [BeautifulTimelineNode],
        currentTime: Double,
        isPlaying: Bool = true,
        liveTimeProvider: (() -> Double)? = nil,
        accentColor: Color,
        fontSizePreset: LyricsFontSizePreset = .medium,
        showTranslation: Bool = false,
        onSeekToTime: @escaping (Double) -> Void
    ) {
        self.document = document
        self.nodes = nodes
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.liveTimeProvider = liveTimeProvider ?? { currentTime }
        self.accentColor = accentColor
        self.fontSizePreset = fontSizePreset
        self.showTranslation = showTranslation
        self.onSeekToTime = onSeekToTime
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                // Лёгкий трекер смены индекса активной строки: обновляет `ScrollView` только при реальном переходе на новую строку
                ActiveLineIndexDriverView(
                    lines: document.lines,
                    isPlaying: isPlaying,
                    liveTimeProvider: liveTimeProvider,
                    activeLineIndex: $activeLineIndex
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 32)

                        ForEach(nodes) { node in
                            switch node {
                            case .interlude(let id, let start, let end):
                                InterludeDotsLiveContainer(
                                    id: id,
                                    startTime: start,
                                    endTime: end,
                                    isPlaying: isPlaying,
                                    liveTimeProvider: liveTimeProvider
                                )
                                .id(id)

                            case .vocal(let group):
                                BeautifulVocalLineRow(
                                    group: group,
                                    activeLineIndex: activeLineIndex,
                                    selectedPlainLineIndex: selectedPlainLineIndex,
                                    syncKind: document.kind,
                                    isPlaying: isPlaying,
                                    liveTimeProvider: liveTimeProvider,
                                    accentColor: accentColor,
                                    scaleFactor: fontSizePreset.scaleFactor,
                                    showTranslation: showTranslation,
                                    onTap: {
                                        autoResumeTask?.cancel()
                                        if document.kind == .plain {
                                            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.38)) {
                                                if selectedPlainLineIndex == group.lineIndex {
                                                    selectedPlainLineIndex = nil
                                                } else {
                                                    selectedPlainLineIndex = group.lineIndex
                                                }
                                            }
                                        } else {
                                            isUserBrowsing = false
                                            onSeekToTime(group.startTime)
                                        }
                                    }
                                )
                                .padding(.vertical, 11)
                                .id(group.id)
                            }
                        }

                        Spacer().frame(height: 200)
                    }
                    .padding(.horizontal, 24)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            guard document.kind != .plain else { return }
                            if !isUserBrowsing {
                                isUserBrowsing = true
                            }
                            scheduleAutoResumeScroll()
                        }
                )
                .onAppear {
                    let initialIdx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                    activeLineIndex = initialIdx
                    scrollToActiveNode(proxy: proxy, lineIndex: initialIdx, animated: false)
                }
                .onChange(of: document.lines.count) { _, _ in
                    selectedPlainLineIndex = nil
                    let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                    activeLineIndex = idx
                    scrollToActiveNode(proxy: proxy, lineIndex: idx, animated: false)
                }
                .onChange(of: activeLineIndex) { _, newIdx in
                    guard !isUserBrowsing else { return }
                    scrollToActiveNode(proxy: proxy, lineIndex: newIdx, animated: true)
                }
                .onChange(of: isUserBrowsing) { _, browsing in
                    if !browsing {
                        let currentIdx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                        activeLineIndex = currentIdx
                        scrollToActiveNode(proxy: proxy, lineIndex: currentIdx, animated: true)
                    }
                }

                if isUserBrowsing && document.kind != .plain {
                    Button {
                        autoResumeTask?.cancel()
                        let currentIdx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                        activeLineIndex = currentIdx
                        isUserBrowsing = false
                        scrollToActiveNode(proxy: proxy, lineIndex: currentIdx, animated: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.and.down.circle.fill")
                            Text("Синхр.")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private func scheduleAutoResumeScroll() {
        autoResumeTask?.cancel()
        autoResumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.55)) {
                isUserBrowsing = false
            }
        }
    }

    private func scrollToActiveNode(proxy: ScrollViewProxy, lineIndex: Int, animated: Bool = true) {
        guard document.kind != .plain else { return }
        let targetId: String? = {
            if lineIndex < 0 {
                if let introNode = nodes.first(where: {
                    if case .interlude(let id, _, _) = $0 { return id == "interlude_intro" }
                    return false
                }) {
                    return introNode.id
                }
                return nodes.first?.id
            }
            if let activeVocal = nodes.first(where: {
                if case .vocal(let g) = $0 { return g.lineIndex == lineIndex }
                return false
            }) {
                return activeVocal.id
            }
            return nil
        }()

        guard let targetId else { return }
        if animated {
            // Точная кривая `cubic-bezier(0.22, 1, 0.36, 1)` из десктопного `BeautifulLyrics.css` — сливочное скольжение без подпрыгивания
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.68)) {
                proxy.scrollTo(targetId, anchor: UnitPoint(x: 0.5, y: 0.34))
            }
        } else {
            proxy.scrollTo(targetId, anchor: UnitPoint(x: 0.5, y: 0.34))
        }
    }
}

private struct ActiveLineIndexDriverView: View {
    let lines: [LyricLineItem]
    let isPlaying: Bool
    let liveTimeProvider: () -> Double
    @Binding var activeLineIndex: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { context in
            let _ = context.date
            let now = liveTimeProvider()
            let computed = LRCParser.findActiveLineIndex(lines: lines, currentTime: now)
            Color.clear
                .onChange(of: computed) { _, newValue in
                    if activeLineIndex != newValue {
                        activeLineIndex = newValue
                    }
                }
        }
    }
}

private struct InterludeDotsLiveContainer: View {
    let id: String
    let startTime: Double
    let endTime: Double
    let isPlaying: Bool
    let liveTimeProvider: () -> Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 90.0, paused: !isPlaying)) { context in
            let _ = context.date
            let now = liveTimeProvider()
            let state = InterludeEngine.evaluate(startTime: startTime, endTime: endTime, timestamp: now)
            if state.isVisible {
                HStack(spacing: 6.5) {
                    ForEach(0..<state.dots.count, id: \.self) { idx in
                        let dot = state.dots[idx]
                        let baseWhiteAlpha = dot.isLit ? 0.96 : 0.72
                        Circle()
                            .fill(Color.white.opacity(baseWhiteAlpha * dot.opacity))
                            .frame(width: 8.0, height: 8.0)
                            .scaleEffect(CGFloat(dot.scale))
                            .offset(y: CGFloat(dot.yOffset))
                            .shadow(
                                color: Color.white.opacity(dot.glow * 0.85 * state.groupOpacity),
                                radius: CGFloat(3.0 + 7.5 * dot.glow)
                            )
                    }
                }
                .scaleEffect(CGFloat(state.groupScale), anchor: .leading)
                .opacity(state.groupOpacity)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: CGFloat(34.0 * state.expansionProgress))
                .opacity(state.expansionProgress)
            }
        }
    }
}

private struct BeautifulVocalLineRow: View {
    let group: BeautifulVocalLineGroup
    let activeLineIndex: Int
    let selectedPlainLineIndex: Int?
    let syncKind: ParsedLyricsSyncKind
    let isPlaying: Bool
    let liveTimeProvider: () -> Double
    let accentColor: Color
    let scaleFactor: CGFloat
    let showTranslation: Bool
    let onTap: () -> Void

    private var isLineActive: Bool {
        if syncKind == .plain {
            return selectedPlainLineIndex == group.lineIndex
        }
        return group.lineIndex == activeLineIndex
    }

    private var isLinePast: Bool {
        guard syncKind != .plain, activeLineIndex >= 0 else { return false }
        return group.lineIndex < activeLineIndex
    }

    /// Неактивные строки ВСЕГДА остаются мягкими серенькими (даже на паузе, во вступлении `activeLineIndex == -1` и при прокрутке пальцем!)
    private var nonActiveLineOpacity: Double {
        if syncKind == .plain {
            return 0.46
        }
        if activeLineIndex < 0 {
            let dist = min(4, group.lineIndex)
            return max(0.18, 0.30 - Double(dist) * 0.03)
        }
        let dist = min(4, abs(group.lineIndex - activeLineIndex))
        let base = isLinePast ? 0.38 : 0.28
        return max(0.18, base - Double(dist) * 0.025)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                if syncKind == .plain && isLineActive {
                    Capsule()
                        .fill(accentColor)
                        .frame(width: 3.5)
                        .padding(.vertical, 3)
                        .transition(.opacity.combined(with: .scale))
                }

                VStack(alignment: .leading, spacing: 6) {
                    if !group.syllables.isEmpty && syncKind != .plain {
                        // ВАЖНО: Всегда рендерим одну и ту же раскладку `SyllableWrappingFlowLayout`
                        // для прошлых, активной и будущих строк — ноль переносов строк во время проигрывания!
                        if isLineActive {
                            TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !isPlaying)) { context in
                                let _ = context.date
                                SyllableFlowLineView(
                                    syllables: group.syllables,
                                    lineMode: .active(currentTime: liveTimeProvider(), isPlaying: isPlaying),
                                    scaleFactor: scaleFactor
                                )
                            }
                        } else {
                            SyllableFlowLineView(
                                syllables: group.syllables,
                                lineMode: .inactive(opacity: nonActiveLineOpacity),
                                scaleFactor: scaleFactor
                            )
                        }
                    } else {
                        Text(group.mainText)
                            .font(.system(size: 26 * scaleFactor, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                isLineActive
                                    ? Color.white
                                    : Color.white.opacity(nonActiveLineOpacity)
                            )
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let bg = group.backgroundText, !bg.isEmpty {
                        Text(bg)
                            .font(.system(size: 17.5 * scaleFactor, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(isLineActive ? 0.68 : 0.26))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let romanized = group.romanizedText, !romanized.isEmpty {
                        Text(romanized)
                            .font(.system(size: 13.5 * scaleFactor, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(isLineActive ? 0.58 : 0.24))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if showTranslation, let tr = group.translatedText, !tr.isEmpty {
                        Text(tr)
                            .font(.system(size: 15.5 * scaleFactor, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(isLineActive ? 0.78 : 0.30))
                            .padding(.top, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scaleEffect(isLineActive ? 1.0 : (syncKind == .plain ? 0.98 : 0.955), anchor: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.62), value: isLineActive)
    }
}

private enum SyllableLineRenderMode: Equatable {
    case active(currentTime: Double, isPlaying: Bool)
    case inactive(opacity: Double)
}

/// Поточный контейнер слов (`SyllableVocals.js`), гарантирующий идентичный перенос слов в любом состоянии строки.
private struct SyllableWrappingFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 340
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                usedWidth = max(usedWidth, currentX - horizontalSpacing)
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, min(maxWidth, currentX - horizontalSpacing))
        }

        return CGSize(width: max(usedWidth, min(maxWidth, currentX)), height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct SyllableFlowLineView: View {
    let syllables: [BeautifulSyllableMetadata]
    let lineMode: SyllableLineRenderMode
    let scaleFactor: CGFloat

    var body: some View {
        SyllableWrappingFlowLayout(
            horizontalSpacing: 6.2 * scaleFactor,
            verticalSpacing: 4.0 * scaleFactor
        ) {
            ForEach(Array(syllables.enumerated()), id: \.element.id) { index, syl in
                SyllableWordSpanView(
                    syllable: syl,
                    fadePeer: (index + 2 < syllables.count) ? syllables[index + 2] : nil,
                    lineMode: lineMode,
                    scaleFactor: scaleFactor
                )
            }
        }
    }
}

/// Эстетичное слово без вертикального «подпрыгивания» (`SyllableVocals.js` 1:1):
/// единый шрифт и ширина в любом состоянии + мягкий сливочный градиент заполнения слева направо + деликатное свечение.
private struct SyllableWordSpanView: View {
    let syllable: BeautifulSyllableMetadata
    let fadePeer: BeautifulSyllableMetadata?
    let lineMode: SyllableLineRenderMode
    let scaleFactor: CGFloat

    var body: some View {
        let font = Font.system(size: 26 * scaleFactor, weight: .bold, design: .rounded)

        switch lineMode {
        case .inactive(let opacity):
            Text(syllable.text)
                .font(font)
                .foregroundStyle(Color.white.opacity(opacity))

        case .active(let currentTime, let isPlaying):
            let dur = max(0.06, syllable.duration)
            let rawProgress = HarmonoidMeshEngine.clamp((currentTime - syllable.startTime) / dur, 0.0, 1.0)
            let smoothCubic = rawProgress * rawProgress * (3.0 - 2.0 * rawProgress)
            let progress = 0.45 * rawProgress + 0.55 * smoothCubic
            let isActive = rawProgress > 0.001 && rawProgress < 0.999
            let isPast = rawProgress >= 0.999
            // На паузе непропетые слова активной строки остаются светлыми (0.78), чтобы текущая строка всегда была ярче серых соседних!
            let unsungAlpha: Double = isPlaying ? 0.38 : 0.78

            let fadeAt = fadePeer?.startTime ?? (syllable.endTime + 0.50)
            let fadeOut = isPast ? HarmonoidMeshEngine.clamp((currentTime - fadeAt) / 0.75, 0.0, 1.0) : 0.0
            let restAlpha = 1.0 - 0.08 * fadeOut

            // Мягкая растушёвка границы заполнения слова (28% ширины слова)
            let p = HarmonoidMeshEngine.clamp(progress, 0.01, 0.99)
            let softHalf = 0.14
            let lead = max(0.002, min(0.96, p - softHalf))
            let trail = max(lead + 0.03, min(0.998, p + softHalf))

            let pulse = sin(rawProgress * .pi)
            let glowOpacity: Double = {
                if isActive {
                    return (syllable.isEmphasized ? 0.42 : 0.28) * pulse
                } else if isPast {
                    return 0.10 * (1.0 - fadeOut)
                }
                return 0.0
            }()

            let style: AnyShapeStyle = {
                if isPast {
                    return AnyShapeStyle(Color.white.opacity(restAlpha))
                } else if isActive {
                    return AnyShapeStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.0),
                                .init(color: .white, location: lead),
                                .init(color: .white.opacity(unsungAlpha), location: trail),
                                .init(color: .white.opacity(unsungAlpha), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                } else {
                    return AnyShapeStyle(Color.white.opacity(unsungAlpha))
                }
            }()

            Text(syllable.text)
                .font(font)
                .foregroundStyle(style)
                .shadow(
                    color: Color.white.opacity(glowOpacity),
                    radius: syllable.isEmphasized ? 8 : 5,
                    x: 0,
                    y: 0
                )
        }
    }
}
