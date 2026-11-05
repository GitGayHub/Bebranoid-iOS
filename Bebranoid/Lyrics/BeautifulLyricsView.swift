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
    @State private var activeInterludeId: String? = nil
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
        "\(document.lines.count)|\(document.lines.first?.text ?? "")"
    }

    private func targetNodeId(for lineIndex: Int, interludeId: String?) -> String? {
        guard document.kind != .plain else { return nil }
        if lineIndex < 0 {
            if let interludeId {
                return interludeId
            }
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
        if let interludeId {
            return interludeId
        }
        return nodes.first?.id
    }

    public var body: some View {
        GeometryReader { viewportGeo in
            let availableRowWidth = max(160.0, viewportGeo.size.width - 48.0)

            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ActiveLineIndexDriverView(
                        lines: document.lines,
                        nodes: nodes,
                        isPlaying: isPlaying,
                        liveTimeProvider: liveTimeProvider,
                        activeLineIndex: $activeLineIndex,
                        activeInterludeId: $activeInterludeId
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            #if canImport(UIKit)
                            LyricsSmoothScrollBridge(
                                targetNodeId: targetNodeId(for: activeLineIndex, interludeId: activeInterludeId),
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
                                        if activeInterludeId == id {
                                            InterludeDotsLiveContainer(
                                                id: id,
                                                startTime: start,
                                                endTime: end,
                                                isPlaying: isPlaying,
                                                liveTimeProvider: liveTimeProvider
                                            )
                                            .reportLyricNodeFrame(id: id)
                                            .id(id)
                                            .transition(.opacity.combined(with: .scale(scale: 0.84, anchor: .leading)))
                                        }

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
                                                    HapticsManager.shared.lightTap()
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
                        var didMeaningfullyChange = (nodeFrames.count != updatedFrames.count)
                        if !didMeaningfullyChange {
                            for (key, rect) in updatedFrames {
                                guard let old = nodeFrames[key] else {
                                    didMeaningfullyChange = true
                                    break
                                }
                                if abs(old.midY - rect.midY) > 1.5 || abs(old.height - rect.height) > 1.5 {
                                    didMeaningfullyChange = true
                                    break
                                }
                            }
                        }
                        if didMeaningfullyChange {
                            nodeFrames = updatedFrames
                        }
                    }
                    .onAppear {
                        let now = liveTimeProvider()
                        let initialIdx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: now)
                        activeLineIndex = initialIdx
                        activeInterludeId = ActiveLineIndexDriverView.findVisibleInterludeId(in: nodes, timestamp: now)
                        #if !canImport(UIKit)
                        if let tid = targetNodeId(for: initialIdx, interludeId: activeInterludeId) {
                            proxy.scrollTo(tid, anchor: UnitPoint(x: 0.5, y: 0.34))
                        }
                        #endif
                    }
                    .onChange(of: document.lines.count) { _, _ in
                        selectedPlainLineIndex = nil
                        isUserBrowsing = false
                        let now = liveTimeProvider()
                        let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: now)
                        activeLineIndex = idx
                        activeInterludeId = ActiveLineIndexDriverView.findVisibleInterludeId(in: nodes, timestamp: now)
                        #if !canImport(UIKit)
                        if let tid = targetNodeId(for: idx, interludeId: activeInterludeId) {
                            proxy.scrollTo(tid, anchor: UnitPoint(x: 0.5, y: 0.34))
                        }
                        #endif
                    }
                    #if !canImport(UIKit)
                    .onChange(of: activeLineIndex) { _, newIdx in
                        guard !isUserBrowsing, let tid = targetNodeId(for: newIdx, interludeId: activeInterludeId) else { return }
                        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.62)) {
                            proxy.scrollTo(tid, anchor: UnitPoint(x: 0.5, y: 0.34))
                        }
                    }
                    #endif

                    if isUserBrowsing && document.kind != .plain {
                        Button {
                            HapticsManager.shared.lightTap()
                            let now = liveTimeProvider()
                            let currentIdx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: now)
                            activeLineIndex = currentIdx
                            activeInterludeId = ActiveLineIndexDriverView.findVisibleInterludeId(in: nodes, timestamp: now)
                            isUserBrowsing = false
                            syncTriggerToken &+= 1
                            #if !canImport(UIKit)
                            if let tid = targetNodeId(for: currentIdx, interludeId: activeInterludeId) {
                                withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.62)) {
                                    proxy.scrollTo(tid, anchor: UnitPoint(x: 0.5, y: 0.34))
                                }
                            }
                            #endif
                        } label: {
                            Image(systemName: "arrow.up.and.down")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .liquidGlassCircle(tint: accentColor, isHighlighted: false)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Синхронизировать текст")
                        .padding(.trailing, 20)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(10)
                    }
                }
            }
        }
    }
}

private struct ActiveLineIndexDriverView: View {
    let lines: [LyricLineItem]
    let nodes: [BeautifulTimelineNode]
    let isPlaying: Bool
    let liveTimeProvider: () -> Double
    @Binding var activeLineIndex: Int
    @Binding var activeInterludeId: String?

    static func findVisibleInterludeId(in nodes: [BeautifulTimelineNode], timestamp: Double) -> String? {
        for node in nodes {
            if case .interlude(let id, let start, let end) = node {
                if timestamp >= start - 0.15 && timestamp <= end + 0.25 {
                    let st = InterludeEngine.evaluate(startTime: start, endTime: end, timestamp: timestamp)
                    if st.isVisible {
                        return id
                    }
                }
            }
        }
        return nil
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { context in
            let _ = context.date
            let now = liveTimeProvider()
            let computedLine = LRCParser.findActiveLineIndex(lines: lines, currentTime: now)
            let computedInterlude = Self.findVisibleInterludeId(in: nodes, timestamp: now)
            Color.clear
                .onChange(of: computedLine) { _, newValue in
                    if activeLineIndex != newValue {
                        withAnimation(.timingCurve(0.18, 0.92, 0.26, 1.0, duration: 0.62)) {
                            activeLineIndex = newValue
                        }
                    }
                }
                .onChange(of: computedInterlude) { _, newInterlude in
                    if activeInterludeId != newInterlude {
                        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.34)) {
                            activeInterludeId = newInterlude
                        }
                    }
                }
        }
    }
}

/// Абсолютно плавный GPU-индикатор ожидания из 3 точек:
/// 1) Монтируется ТОЛЬКО для единственного активного интерлюда (0 лишних `TimelineView` в неактивных паузах!)
/// 2) Имеет фиксированную высоту `36 pt` без покадрового изменения `frame(height:)`, исключая перестроение всего `VStack` и лаги!
/// 3) Свечение точек рисуется быстрым `RadialGradient` ореолом без тяжёлого размытия Гаусса `.shadow(radius:)` на каждом кадре.
private struct InterludeDotsLiveContainer: View {
    let id: String
    let startTime: Double
    let endTime: Double
    let isPlaying: Bool
    let liveTimeProvider: () -> Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { context in
            let _ = context.date
            let now = liveTimeProvider()
            let state = InterludeEngine.evaluate(startTime: startTime, endTime: endTime, timestamp: now)

            HStack(spacing: 8.5) {
                ForEach(0..<state.dots.count, id: \.self) { idx in
                    let dot = state.dots[idx]
                    let baseWhiteAlpha = dot.isLit ? 0.98 : 0.68
                    let glowStrength = dot.glow * state.groupOpacity * state.expansionProgress

                    ZStack {
                        if glowStrength > 0.02 {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.white.opacity(0.65 * glowStrength),
                                            Color.white.opacity(0.18 * glowStrength),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 1,
                                        endRadius: 13
                                    )
                                )
                                .frame(width: 26, height: 26)
                                .scaleEffect(CGFloat(0.85 + 0.30 * dot.glow))
                        }

                        Circle()
                            .fill(Color.white.opacity(baseWhiteAlpha * dot.opacity))
                            .frame(width: 8.5, height: 8.5)
                            .scaleEffect(CGFloat(dot.scale))
                    }
                    .frame(width: 12, height: 12)
                    .offset(y: CGFloat(dot.yOffset))
                }
            }
            .scaleEffect(CGFloat(state.groupScale * (0.82 + 0.18 * state.expansionProgress)), anchor: .leading)
            .opacity(state.groupOpacity * state.expansionProgress)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 36.0)
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

    /// Приглушённый холодно-серый тон неактивных строк и ещё не спетых слов (1:1 с ПК-версией `BeautifulLyrics.css`)
    fileprivate static let mutedInactiveColor = Color(red: 0.62, green: 0.64, blue: 0.69)

    /// Неактивные строки ВСЕГДА остаются отчётливо приглушённо-серыми (`~0.24`), чтобы активная белая строка читалась мгновенно
    private var nonActiveLineOpacity: Double {
        if syncKind == .plain {
            return 0.42
        }
        if activeLineIndex < 0 {
            let dist = min(4, group.lineIndex)
            return max(0.18, 0.25 - Double(dist) * 0.015)
        }
        let dist = min(4, abs(group.lineIndex - activeLineIndex))
        let base = isLinePast ? 0.26 : 0.23
        return max(0.17, base - Double(dist) * 0.015)
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
                        // Неактивные строки рендерятся одним лёгким `Text` с предкэшированным `fitScale` (в 20 раз меньше вью в дереве SwiftUI!),
                        // а пословный `TimelineView` работает строго на 1 активной строке без перегрева iPhone
                        if isLineActive {
                            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
                                let _ = context.date
                                SyllableSingleLineView(
                                    syllables: group.syllables,
                                    lineMode: .active(currentTime: liveTimeProvider(), isPlaying: isPlaying),
                                    scaleFactor: scaleFactor,
                                    availableWidth: effectiveLineWidth
                                )
                            }
                            .frame(minHeight: ceil(31.0 * scaleFactor), alignment: .leading)
                        } else {
                            let inactiveFit = SingleLineLyricsFitHelper.fitScaleForSyllables(
                                group.syllables,
                                baseFontSize: 26.0 * scaleFactor,
                                baseSpacing: 5.8 * scaleFactor,
                                availableWidth: effectiveLineWidth
                            )
                            Text(group.mainText)
                                .font(.system(size: 26 * scaleFactor * inactiveFit, weight: .bold, design: .rounded))
                                .foregroundStyle(Self.mutedInactiveColor.opacity(nonActiveLineOpacity))
                                .lineLimit(1)
                                .minimumScaleFactor(0.30)
                                .allowsTightening(true)
                                .frame(minHeight: ceil(31.0 * scaleFactor), alignment: .leading)
                        }
                    } else {
                        Text(group.mainText)
                            .font(.system(size: 26 * scaleFactor, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                isLineActive
                                    ? Color.white
                                    : Self.mutedInactiveColor.opacity(nonActiveLineOpacity)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.30)
                            .allowsTightening(true)
                            .frame(minHeight: ceil(31.0 * scaleFactor), alignment: .leading)
                    }

                    if let bg = group.backgroundText, !bg.isEmpty {
                        Text(bg)
                            .font(.system(size: 17 * scaleFactor, weight: .semibold, design: .rounded))
                            .foregroundStyle(isLineActive ? Color.white.opacity(0.68) : Self.mutedInactiveColor.opacity(0.24))
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .allowsTightening(true)
                    }

                    if let romanized = group.romanizedText, !romanized.isEmpty {
                        Text(romanized)
                            .font(.system(size: 13.5 * scaleFactor, weight: .medium, design: .rounded))
                            .foregroundStyle(isLineActive ? Color.white.opacity(0.58) : Self.mutedInactiveColor.opacity(0.22))
                            .lineLimit(1)
                            .minimumScaleFactor(0.38)
                            .allowsTightening(true)
                    }

                    if showTranslation, let tr = group.translatedText, !tr.isEmpty {
                        Text(tr)
                            .font(.system(size: 15.5 * scaleFactor, weight: .medium, design: .rounded))
                            .foregroundStyle(isLineActive ? Color.white.opacity(0.82) : Self.mutedInactiveColor.opacity(0.28))
                            .padding(.top, 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .allowsTightening(true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.26), value: showTranslation)
                .animation(.easeInOut(duration: 0.26), value: group.translatedText != nil)
            }
            .scaleEffect(isLineActive ? 1.0 : (syncKind == .plain ? 0.98 : 0.956), anchor: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.timingCurve(0.18, 0.92, 0.26, 1.0, duration: 0.62), value: isLineActive)
        .animation(.timingCurve(0.18, 0.92, 0.26, 1.0, duration: 0.62), value: nonActiveLineOpacity)
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
                .foregroundStyle(BeautifulVocalLineRow.mutedInactiveColor.opacity(opacity))

        case .active(let currentTime, _):
            let dur = max(0.06, syllable.duration)
            let rawProgress = HarmonoidMeshEngine.clamp((currentTime - syllable.startTime) / dur, 0.0, 1.0)
            let smoothCubic = rawProgress * rawProgress * (3.0 - 2.0 * rawProgress)
            let progress = 0.45 * rawProgress + 0.55 * smoothCubic
            let isActive = rawProgress > 0.001 && rawProgress < 0.999
            let isPast = rawProgress >= 0.999
            // Ещё не пропетые слова активной строки всегда остаются приглушённо-серыми (как в ПК-версии `BeautifulLyrics.css`),
            // чтобы пропетые белые слова (`Color.white`) резко и контрастно выделялись!
            let unsungColor = BeautifulVocalLineRow.mutedInactiveColor.opacity(0.32)

            let fadeAt = fadePeer?.startTime ?? (syllable.endTime + 0.50)
            let fadeOut = isPast ? HarmonoidMeshEngine.clamp((currentTime - fadeAt) / 0.75, 0.0, 1.0) : 0.0
            let restAlpha = 1.0 - 0.06 * fadeOut

            let p = HarmonoidMeshEngine.clamp(progress, 0.01, 0.99)
            let softHalf = 0.14
            let lead = max(0.002, min(0.96, p - softHalf))
            let trail = max(lead + 0.03, min(0.998, p + softHalf))

            let style: AnyShapeStyle = {
                if isPast {
                    return AnyShapeStyle(Color.white.opacity(restAlpha))
                } else if isActive {
                    return AnyShapeStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.0),
                                .init(color: .white, location: lead),
                                .init(color: unsungColor, location: trail),
                                .init(color: unsungColor, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                } else {
                    return AnyShapeStyle(unsungColor)
                }
            }()

            Text(syllable.text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .foregroundStyle(style)
        }
    }
}
