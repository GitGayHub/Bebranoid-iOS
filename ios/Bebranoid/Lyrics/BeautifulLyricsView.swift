import SwiftUI

/// Нативный SwiftUI-рендерер **Beautiful Lyrics** (`src/beautiful-lyrics/BeautifulLyrics.jsx`, `SyllableVocals.js`, `LineVocals.js`, `Interlude.js`, `LyricsScroller.js`).
public struct BeautifulLyricsView: View {
    public let document: ParsedLyricsDocument
    public let nodes: [BeautifulTimelineNode]
    public let currentTime: Double
    public let accentColor: Color
    public let fontSizePreset: LyricsFontSizePreset
    public let showTranslation: Bool
    public let onSeekToTime: (Double) -> Void

    @State private var isUserBrowsing: Bool = false
    @State private var lastUserScrollTime: Date = .distantPast

    public init(
        document: ParsedLyricsDocument,
        nodes: [BeautifulTimelineNode],
        currentTime: Double,
        accentColor: Color,
        fontSizePreset: LyricsFontSizePreset = .medium,
        showTranslation: Bool = false,
        onSeekToTime: @escaping (Double) -> Void
    ) {
        self.document = document
        self.nodes = nodes
        self.currentTime = currentTime
        self.accentColor = accentColor
        self.fontSizePreset = fontSizePreset
        self.showTranslation = showTranslation
        self.onSeekToTime = onSeekToTime
    }

    private var activeLineIndex: Int {
        LRCParser.findActiveLineIndex(lines: document.lines, currentTime: currentTime)
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        Spacer().frame(height: 28)

                        ForEach(nodes) { node in
                            switch node {
                            case .interlude(let id, let start, let end):
                                InterludeDotsRowView(
                                    id: id,
                                    startTime: start,
                                    endTime: end,
                                    currentTime: currentTime
                                )
                                .id(id)

                            case .vocal(let group):
                                BeautifulVocalLineRow(
                                    group: group,
                                    currentTime: currentTime,
                                    activeLineIndex: activeLineIndex,
                                    syncKind: document.kind,
                                    accentColor: accentColor,
                                    scaleFactor: fontSizePreset.scaleFactor,
                                    showTranslation: showTranslation,
                                    isUserBrowsing: isUserBrowsing,
                                    onTap: {
                                        isUserBrowsing = false
                                        onSeekToTime(group.startTime)
                                    }
                                )
                                .id(group.id)
                            }
                        }

                        Spacer().frame(height: 180)
                    }
                    .padding(.horizontal, 24)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            isUserBrowsing = true
                            lastUserScrollTime = Date()
                        }
                )
                .onChange(of: activeLineIndex) { _, newIdx in
                    guard !isUserBrowsing else { return }
                    scrollToActiveNode(proxy: proxy, lineIndex: newIdx)
                }
            }

            if isUserBrowsing {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isUserBrowsing = false
                    }
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

    private func scrollToActiveNode(proxy: ScrollViewProxy, lineIndex: Int) {
        if let activeVocal = nodes.first(where: {
            if case .vocal(let g) = $0 { return g.lineIndex == lineIndex }
            return false
        }) {
            withAnimation(.interpolatingSpring(stiffness: 110, damping: 18)) {
                proxy.scrollTo(activeVocal.id, anchor: UnitPoint(x: 0.5, y: 0.34))
            }
        }
    }
}

private struct InterludeDotsRowView: View {
    let id: String
    let startTime: Double
    let endTime: Double
    let currentTime: Double

    var body: some View {
        let state = InterludeEngine.evaluate(startTime: startTime, endTime: endTime, timestamp: currentTime)
        if state.isVisible {
            HStack(spacing: 10) {
                ForEach(0..<state.dots.count, id: \.self) { idx in
                    let dot = state.dots[idx]
                    Circle()
                        .fill(Color.white.opacity(dot.opacity))
                        .frame(width: 11, height: 11)
                        .scaleEffect(CGFloat(dot.scale))
                        .offset(y: CGFloat(dot.yOffset))
                        .shadow(color: Color.white.opacity(dot.glow * 0.65), radius: CGFloat(8.0 * dot.glow))
                }
            }
            .scaleEffect(CGFloat(state.groupScale), anchor: .leading)
            .opacity(state.groupOpacity)
            .padding(.vertical, 8)
            .animation(.easeOut(duration: 0.08), value: currentTime)
        }
    }
}

private struct BeautifulVocalLineRow: View {
    let group: BeautifulVocalLineGroup
    let currentTime: Double
    let activeLineIndex: Int
    let syncKind: ParsedLyricsSyncKind
    let accentColor: Color
    let scaleFactor: CGFloat
    let showTranslation: Bool
    let isUserBrowsing: Bool
    let onTap: () -> Void

    private var isLineActive: Bool {
        if syncKind == .plain { return true }
        return group.lineIndex == activeLineIndex
    }

    private var isLinePast: Bool {
        guard syncKind != .plain else { return false }
        return group.lineIndex < activeLineIndex
    }

    private var nonActiveLineOpacity: Double {
        guard syncKind != .plain, activeLineIndex >= 0 else { return 0.92 }
        if isUserBrowsing { return 0.72 }
        let dist = min(4, abs(group.lineIndex - activeLineIndex))
        let base = isLinePast ? 0.42 : 0.28
        return max(0.16, base - Double(dist) * 0.03)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                if !group.syllables.isEmpty && isLineActive {
                    SyllableFlowLineView(
                        syllables: group.syllables,
                        currentTime: currentTime,
                        scaleFactor: scaleFactor
                    )
                } else {
                    Text(group.mainText)
                        .font(.system(size: 27 * scaleFactor, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            isLineActive
                                ? Color.white
                                : Color.white.opacity(nonActiveLineOpacity)
                        )
                        .multilineTextAlignment(.leading)
                }

                if let bg = group.backgroundText, !bg.isEmpty {
                    Text(bg)
                        .font(.system(size: 18 * scaleFactor, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(isLineActive ? 0.68 : 0.28))
                }

                if let romanized = group.romanizedText, !romanized.isEmpty {
                    Text(romanized)
                        .font(.system(size: 14 * scaleFactor, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(isLineActive ? 0.62 : 0.26))
                }

                if showTranslation, let tr = group.translatedText, !tr.isEmpty {
                    Text(tr)
                        .font(.system(size: 16 * scaleFactor, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(isLineActive ? 0.78 : 0.32))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(isLineActive ? 1.0 : 0.94, anchor: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isLineActive)
    }
}

/// Поточный контейнер слов (`SyllableVocals.js`), автоматически переносящий слова по строкам
/// и отрисовывающий плавное слева-направо заполнение каждого слова при 120 FPS.
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
    let currentTime: Double
    let scaleFactor: CGFloat

    var body: some View {
        SyllableWrappingFlowLayout(
            horizontalSpacing: 7.0 * scaleFactor,
            verticalSpacing: 4.0 * scaleFactor
        ) {
            ForEach(Array(syllables.enumerated()), id: \.element.id) { index, syl in
                if syl.isEmphasized {
                    EmphasizedWordLettersView(
                        syllable: syl,
                        currentTime: currentTime,
                        scaleFactor: scaleFactor
                    )
                } else {
                    SyllableWordSpanView(
                        syllable: syl,
                        fadePeer: (index + 2 < syllables.count) ? syllables[index + 2] : nil,
                        currentTime: currentTime,
                        scaleFactor: scaleFactor
                    )
                }
            }
        }
    }
}

/// Одиночное слово с плавным горизонтальным заполнением слева направо (`--gradient-progress` + `20%` мягкий градиентный край из `SyllableVocals.js` и `BeautifulLyrics.css`).
private struct SyllableWordSpanView: View {
    let syllable: BeautifulSyllableMetadata
    let fadePeer: BeautifulSyllableMetadata?
    let currentTime: Double
    let scaleFactor: CGFloat

    var body: some View {
        let rawProgress = HarmonoidMeshEngine.clamp((currentTime - syllable.startTime) / syllable.duration, 0.0, 1.0)
        let smoothCubic = rawProgress * rawProgress * (3.0 - 2.0 * rawProgress)
        let progress = 0.35 * rawProgress + 0.65 * smoothCubic
        let isActive = rawProgress > 0.001 && rawProgress < 0.999
        let isPast = rawProgress >= 0.999

        let fadeAt = fadePeer?.startTime ?? (syllable.endTime + 0.45)
        let fadeOut = isPast ? HarmonoidMeshEngine.clamp((currentTime - fadeAt) / 0.70, 0.0, 1.0) : 0.0
        let restAlpha = 1.0 - 0.18 * fadeOut

        let wipeLead = -0.18 + 1.18 * progress
        let wipeTrail = wipeLead + 0.24
        let yLift: CGFloat = isActive ? -1.8 * CGFloat(sin(rawProgress * .pi)) : 0.0
        let glowAlpha: Double = isActive ? (0.42 * sin(rawProgress * .pi)) : (isPast ? 0.14 * (1.0 - fadeOut) : 0.0)
        let font = Font.system(size: 27 * scaleFactor, weight: .bold, design: .rounded)

        Text(syllable.text)
            .font(font)
            .foregroundStyle(Color.white.opacity(isPast ? restAlpha : 0.34))
            .overlay {
                if isActive {
                    Text(syllable.text)
                        .font(font)
                        .foregroundStyle(Color.white)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0.0),
                                    .init(color: .white, location: max(0.0, min(1.0, wipeLead))),
                                    .init(color: .clear, location: max(0.001, min(1.0, wipeTrail)))
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .offset(y: yLift)
            .shadow(color: Color.white.opacity(glowAlpha), radius: 7, x: 0, y: 0)
    }
}

private struct EmphasizedWordLettersView: View {
    let syllable: BeautifulSyllableMetadata
    let currentTime: Double
    let scaleFactor: CGFloat

    var body: some View {
        let chars = Array(syllable.text)
        let count = max(1, chars.count)
        let overallProgress = HarmonoidMeshEngine.clamp((currentTime - syllable.startTime) / syllable.duration, 0.0, 1.0)
        let font = Font.system(size: 27 * scaleFactor, weight: .heavy, design: .rounded)

        HStack(spacing: 0.4) {
            ForEach(0..<chars.count, id: \.self) { charIdx in
                let charStart = Double(charIdx) / Double(count)
                let charEnd = Double(charIdx + 1) / Double(count)
                let charProgress = HarmonoidMeshEngine.clamp((overallProgress - charStart) / max(0.05, charEnd - charStart), 0.0, 1.0)
                let pulse = sin(charProgress * .pi)
                let lead = -0.15 + 1.15 * charProgress
                let trail = lead + 0.30
                let chStr = String(chars[charIdx])

                Text(chStr)
                    .font(font)
                    .foregroundStyle(Color.white.opacity(charProgress >= 0.999 ? 1.0 : 0.34))
                    .overlay {
                        if charProgress > 0.001 && charProgress < 0.999 {
                            Text(chStr)
                                .font(font)
                                .foregroundStyle(Color.white)
                                .mask(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white, location: 0.0),
                                            .init(color: .white, location: max(0.0, min(1.0, lead))),
                                            .init(color: .clear, location: max(0.001, min(1.0, trail)))
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
                    .scaleEffect(CGFloat(1.0 + 0.09 * pulse))
                    .offset(y: CGFloat(-3.2 * pulse))
                    .shadow(color: Color.white.opacity(0.55 * pulse), radius: CGFloat(8.0 * pulse))
            }
        }
    }
}
