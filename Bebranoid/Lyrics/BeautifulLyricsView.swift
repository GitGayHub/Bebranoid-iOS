import SwiftUI

/// Нативный 120 FPS SwiftUI-рендерер **Beautiful Lyrics** (`src/beautiful-lyrics/BeautifulLyrics.jsx`, `SyllableVocals.js`, `LyricsRenderer.js`).
/// Ключевые гарантии плавности и однострочной эстетики:
/// 1. Строго **1 строка** на каждую реплику (`SingleLineLyricsFitHelper` + `SingleLineSyllableRowLayout` и `.lineLimit(1)` + `.minimumScaleFactor(0.30)`): текст всегда целиком помещается в одну строку без переносов на второй ряд!
/// 2. Нативный 120 Гц пружинный движок прокрутки `LyricsSmoothScrollBridge` (`CADisplayLink` + `Spring`): непрерывное сливочное скольжение с сохранением скорости при смене строк и мгновенной отдачей под палец.
/// 3. Мягкое сливочное градиентное заполнение слогов слева направо без вертикальных подпрыгиваний.
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
    @State private var selectedPlainLineIndex: Int? = nil
    @State private var nodeFrames: [String: CGRect] = [:]
    @State private var syncTriggerToken: Int = 0

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

    private var documentSignature: String {
        "\(document.lines.count)|\(document.lines.first?.text ?? "")|\(fontSizePreset.rawValue)|\(showTranslation)"
    }

    private func targetNodeId(for lineIndex: Int) -> String? {
        guard document.kind != .plain else { return nil }
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
    }

    public var body: some View {
        GeometryReader { viewportGeo in
            let availableRowWidth = max(160.0, viewportGeo.size.width - 48.0)

            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ActiveLineIndexDriverView(
                        lines: document.lines,
                        isPlaying: isPlaying,
                        liveTimeProvider: liveTimeProvider,
                        activeLineIndex: $activeLineIndex
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            #if canImport(UIKit)
                            LyricsSmoothScrollBridge(
                                targetNodeId: targetNodeId(for: activeLineIndex),
                                nodeFrames: nodeFrames,
                                documentSignature: documentSignature,
                                syncTriggerToken: syncTriggerToken,
                                isPlainLyrics: document.kind == .plain,
                                isUserBrowsing: $isUserBrowsing
                            )
                            .frame(width: 0, height: 0)
                            #endif

                            VStack(alignment: .leading, spacing: 0) {
                                Spacer().frame(height: 36)

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
                                        .reportLyricNodeFrame(id: id)
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
                                            availableWidth: availableRowWidth,
                                            showTranslation: showTranslation,
                                            onTap: {
                                                if document.kind == .plain {
                                                    withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.38)) {
                                                        if selectedPlainLineIndex == group.lineIndex {
                                                            selectedPlainLineIndex = nil
                                                        } else {
                                                            selectedPlainLineIndex = group.lineIndex
                                                        }
                                                    }
                                                } else {
                                                    activeLineIndex = group.lineIndex
                                                    isUserBrowsing = false
                                                    syncTriggerToken &+= 1
                                                    onSeekToTime(group.startTime)
                                                    #if !canImport(UIKit)
                                                    withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.56)) {
                                                        proxy.scrollTo(group.id, anchor: UnitPoint(x: 0.5, y: 0.34))
                                                    }
                                                    #endif
                                                }
                                            }
                                        )
                                        .padding(.vertical, 12)
                                        .reportLyricNodeFrame(id: group.id)
                                        .id(group.id)
                                    }
                                }

                                Spacer().frame(height: 220)
                            }
                            .padding(.horizontal, 24)
                            .coordinateSpace(name: "LyricsScrollContent")
                        }
                    }
                    .onPreferenceChange(LyricNodeFramePreferenceKey.self) { updatedFrames in
                        nodeFrames = updatedFrames
                    }
                    .onAppear {
                        let initialIdx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                        activeLineIndex = initialIdx
                        #if !canImport(UIKit)
                        if let tid = targetNodeId(for: initialIdx) {
                            proxy.scrollTo(tid, anchor: UnitPoint(x: 0.5, y: 0.34))
                        }
                        #endif
                    }
                    .onChange(of: document.lines.count) { _, _ in
                        selectedPlainLineIndex = nil
                        isUserBrowsing = false
                        let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                        activeLineIndex = idx
                        #if !canImport(UIKit)
                        if let tid = targetNodeId(for: idx) {
                            proxy.scrollTo(tid, anchor: UnitPoint(x: 0.5, y: 0.34))
                        }
                        #endif
                    }
                    #if !canImport(UIKit)
                    .onChange(of: activeLineIndex) { _, newIdx in
                        guard !isUserBrowsing, let tid = targetNodeId(for: newIdx) else { return }
                        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.62)) {
                            proxy.scrollTo(tid, anchor: UnitPoint(x: 0.5, y: 0.34))
                        }
                    }
                    #endif

                    if isUserBrowsing && document.kind != .plain {
                        Button {
                            let currentIdx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                            activeLineIndex = currentIdx
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                isUserBrowsing = false
                            }
                            syncTriggerToken &+= 1
                            #if !canImport(UIKit)
                            if let tid = targetNodeId(for: currentIdx) {
                                withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.62)) {
                                    proxy.scrollTo(tid, anchor: UnitPoint(x: 0.5, y: 0.34))
                                }
                            }
                            #endif
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.and.down.circle.fill")
                                Text("Синхр.")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .liquidGlassCapsule(tint: accentColor, isProminent: false)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }
}

private struct ActiveLineIndexDriverView: View {
    let lines: [LyricLineItem]
    let isPlaying: Bool
    let liveTimeProvider: () -> Double
    @Binding var activeLineIndex: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 90.0, paused: !isPlaying)) { context in
            let _ = context.date
            let now = liveTimeProvider()
            let computed = LRCParser.findActiveLineIndex(lines: lines, currentTime: now)
            Color.clear
                .onChange(of: computed) { _, newValue in
                    if activeLineIndex != newValue {
                        withAnimation(.timingCurve(0.20, 0.96, 0.32, 1.0, duration: 0.54)) {
                            activeLineIndex = newValue
                        }
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
    let availableWidth: CGFloat
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

    /// Неактивные строки ВСЕГДА остаются мягкими серебристо-серыми (и при воспроизведении, и на паузе, и при прокрутке пальцем)
    private var nonActiveLineOpacity: Double {
        if syncKind == .plain {
            return 0.46
        }
        if activeLineIndex < 0 {
            let dist = min(4, group.lineIndex)
            return max(0.20, 0.32 - Double(dist) * 0.03)
        }
        let dist = min(4, abs(group.lineIndex - activeLineIndex))
        let base = isLinePast ? 0.38 : 0.29
        return max(0.20, base - Double(dist) * 0.025)
    }

    var body: some View {
        let effectiveLineWidth = (syncKind == .plain && isLineActive) ? max(120, availableWidth - 14) : availableWidth

        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                if syncKind == .plain && isLineActive {
                    Capsule()
                        .fill(accentColor)
                        .frame(width: 3.5)
                        .padding(.vertical, 3)
                        .transition(.opacity.combined(with: .scale))
                }

                VStack(alignment: .leading, spacing: 5) {
                    if !group.syllables.isEmpty && syncKind != .plain {
                        // Однострочная раскладка слогов с автоподбором размера под ширину экрана (никогда не переносится на 2 строки!)
                        if isLineActive {
                            TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !isPlaying)) { context in
                                let _ = context.date
                                SyllableSingleLineView(
                                    syllables: group.syllables,
                                    lineMode: .active(currentTime: liveTimeProvider(), isPlaying: isPlaying),
                                    scaleFactor: scaleFactor,
                                    availableWidth: effectiveLineWidth
                                )
                            }
                        } else {
                            SyllableSingleLineView(
                                syllables: group.syllables,
                                lineMode: .inactive(opacity: nonActiveLineOpacity),
                                scaleFactor: scaleFactor,
                                availableWidth: effectiveLineWidth
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.30)
                            .allowsTightening(true)
                            .shadow(
                                color: Color.white.opacity(isLineActive ? 0.18 : 0.0),
                                radius: 7,
                                x: 0,
                                y: 0
                            )
                    }

                    if let bg = group.backgroundText, !bg.isEmpty {
                        Text(bg)
                            .font(.system(size: 17 * scaleFactor, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(isLineActive ? 0.68 : 0.26))
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .allowsTightening(true)
                    }

                    if let romanized = group.romanizedText, !romanized.isEmpty {
                        Text(romanized)
                            .font(.system(size: 13.5 * scaleFactor, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(isLineActive ? 0.58 : 0.24))
                            .lineLimit(1)
                            .minimumScaleFactor(0.38)
                            .allowsTightening(true)
                    }

                    if showTranslation, let tr = group.translatedText, !tr.isEmpty {
                        Text(tr)
                            .font(.system(size: 15.5 * scaleFactor, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(isLineActive ? 0.80 : 0.30))
                            .padding(.top, 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .allowsTightening(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scaleEffect(isLineActive ? 1.0 : (syncKind == .plain ? 0.98 : 0.962), anchor: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.timingCurve(0.20, 0.96, 0.32, 1.0, duration: 0.54), value: isLineActive)
    }
}

private enum SyllableLineRenderMode: Equatable {
    case active(currentTime: Double, isPlaying: Bool)
    case inactive(opacity: Double)
}

private struct SyllableSingleLineView: View {
    let syllables: [BeautifulSyllableMetadata]
    let lineMode: SyllableLineRenderMode
    let scaleFactor: CGFloat
    let availableWidth: CGFloat

    var body: some View {
        let baseFontSize = 26.0 * scaleFactor
        let baseSpacing = 5.8 * scaleFactor
        let fitScale = SingleLineLyricsFitHelper.fitScaleForSyllables(
            syllables,
            baseFontSize: baseFontSize,
            baseSpacing: baseSpacing,
            availableWidth: availableWidth
        )
        let effectiveScale = scaleFactor * fitScale

        SingleLineSyllableRowLayout(horizontalSpacing: 5.8 * effectiveScale) {
            ForEach(Array(syllables.enumerated()), id: \.element.id) { index, syl in
                SyllableWordSpanView(
                    syllable: syl,
                    fadePeer: (index + 2 < syllables.count) ? syllables[index + 2] : nil,
                    lineMode: lineMode,
                    scaleFactor: effectiveScale
                )
            }
        }
    }
}

/// Эстетичное однострочное слово (`SyllableVocals.js` 1:1):
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .foregroundStyle(Color.white.opacity(opacity))

        case .active(let currentTime, let isPlaying):
            let dur = max(0.06, syllable.duration)
            let rawProgress = HarmonoidMeshEngine.clamp((currentTime - syllable.startTime) / dur, 0.0, 1.0)
            let smoothCubic = rawProgress * rawProgress * (3.0 - 2.0 * rawProgress)
            let progress = 0.45 * rawProgress + 0.55 * smoothCubic
            let isActive = rawProgress > 0.001 && rawProgress < 0.999
            let isPast = rawProgress >= 0.999
            // На паузе непропетые слова активной строки остаются светлыми (0.78), чтобы текущая строка всегда выделялась над серыми соседними!
            let unsungAlpha: Double = isPlaying ? 0.38 : 0.78

            let fadeAt = fadePeer?.startTime ?? (syllable.endTime + 0.50)
            let fadeOut = isPast ? HarmonoidMeshEngine.clamp((currentTime - fadeAt) / 0.75, 0.0, 1.0) : 0.0
            let restAlpha = 1.0 - 0.08 * fadeOut

            let p = HarmonoidMeshEngine.clamp(progress, 0.01, 0.99)
            let softHalf = 0.14
            let lead = max(0.002, min(0.96, p - softHalf))
            let trail = max(lead + 0.03, min(0.998, p + softHalf))

            let pulse = sin(rawProgress * .pi)
            let glowOpacity: Double = {
                if isActive {
                    return (syllable.isEmphasized ? 0.44 : 0.30) * pulse
                } else if isPast {
                    return 0.11 * (1.0 - fadeOut)
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
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
