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

    private var distanceBlurRadius: CGFloat {
        guard !isUserBrowsing, syncKind != .plain, activeLineIndex >= 0 else { return 0 }
        let dist = min(4, abs(group.lineIndex - activeLineIndex))
        if dist == 0 { return 0 }
        return CGFloat(Double(dist) * 0.85)
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
                                : Color.white.opacity(isLinePast ? 0.34 : 0.42)
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
            .scaleEffect(isLineActive ? 1.0 : 0.96, anchor: .leading)
            .blur(radius: distanceBlurRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isLineActive)
    }
}

private struct SyllableFlowLineView: View {
    let syllables: [BeautifulSyllableMetadata]
    let currentTime: Double
    let scaleFactor: CGFloat

    var body: some View {
        WrappingHStackView(syllables: syllables, currentTime: currentTime, scaleFactor: scaleFactor)
    }
}

private struct WrappingHStackView: View {
    let syllables: [BeautifulSyllableMetadata]
    let currentTime: Double
    let scaleFactor: CGFloat

    var body: some View {
        let hasActiveEmphasis = syllables.contains { $0.isEmphasized && currentTime >= $0.startTime && currentTime <= $0.endTime + 0.3 }

        if hasActiveEmphasis {
            HStack(spacing: 6) {
                ForEach(Array(syllables.enumerated()), id: \.element.id) { index, syl in
                    if syl.isEmphasized {
                        EmphasizedWordLettersView(syllable: syl, currentTime: currentTime, scaleFactor: scaleFactor)
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
        } else {
            Text(buildAttributedSyllableLine())
                .font(.system(size: 27 * scaleFactor, weight: .bold, design: .rounded))
                .shadow(color: Color.white.opacity(0.28), radius: 10, x: 0, y: 2)
        }
    }

    private func buildAttributedSyllableLine() -> AttributedString {
        var result = AttributedString()
        for (idx, syl) in syllables.enumerated() {
            let fadePeer = (idx + 2 < syllables.count) ? syllables[idx + 2] : nil
            let progress = HarmonoidMeshEngine.clamp((currentTime - syl.startTime) / syl.duration, 0.0, 1.0)
            let isSung = progress >= 1.0
            let isPeerFinished = fadePeer != nil && currentTime >= fadePeer!.endTime

            let alpha: Double
            if progress <= 0.0 {
                alpha = 0.38
            } else if !isSung {
                alpha = 0.45 + 0.55 * progress
            } else if isPeerFinished {
                alpha = 0.76
            } else {
                alpha = 1.0
            }

            var wordAttr = AttributedString(syl.text + (idx < syllables.count - 1 ? " " : ""))
            wordAttr.foregroundColor = Color.white.opacity(alpha)
            result.append(wordAttr)
        }
        return result
    }
}

private struct SyllableWordSpanView: View {
    let syllable: BeautifulSyllableMetadata
    let fadePeer: BeautifulSyllableMetadata?
    let currentTime: Double
    let scaleFactor: CGFloat

    var body: some View {
        let progress = HarmonoidMeshEngine.clamp((currentTime - syllable.startTime) / syllable.duration, 0.0, 1.0)
        let isActive = progress > 0.0 && progress < 1.0
        let yLift: CGFloat = isActive ? -3.0 * CGFloat(sin(progress * .pi)) : 0.0
        let alpha: Double = progress <= 0 ? 0.38 : (progress < 1.0 ? (0.48 + 0.52 * progress) : 0.92)

        Text(syllable.text)
            .font(.system(size: 27 * scaleFactor, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(alpha))
            .offset(y: yLift)
            .shadow(color: Color.white.opacity(isActive ? 0.45 : 0.0), radius: 8)
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

        HStack(spacing: 0.5) {
            ForEach(0..<chars.count, id: \.self) { charIdx in
                let charStart = Double(charIdx) / Double(count)
                let charEnd = Double(charIdx + 1) / Double(count)
                let charProgress = HarmonoidMeshEngine.clamp((overallProgress - charStart) / max(0.05, charEnd - charStart), 0.0, 1.0)
                let pulse = sin(charProgress * .pi)

                Text(String(chars[charIdx]))
                    .font(.system(size: 27 * scaleFactor, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.42 + 0.58 * charProgress))
                    .scaleEffect(CGFloat(1.0 + 0.12 * pulse))
                    .offset(y: CGFloat(-4.5 * pulse))
                    .shadow(color: Color.white.opacity(0.65 * pulse), radius: CGFloat(10.0 * pulse))
            }
        }
    }
}
