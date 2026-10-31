import SwiftUI

/// Классический караоке-движок (`src/components/ClassicKaraokeLyrics.jsx`).
/// Отображает строго однострочные реплики (`lineLimit(1)` + `minimumScaleFactor(0.30)`),
/// с плавным 120 Гц пружинным скроллом `LyricsSmoothScrollBridge`, прогрессом активной строки и переводом на русский язык.
public struct ClassicKaraokeLyricsView: View {
    public let document: ParsedLyricsDocument
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
        currentTime: Double,
        isPlaying: Bool = true,
        liveTimeProvider: (() -> Double)? = nil,
        accentColor: Color,
        fontSizePreset: LyricsFontSizePreset = .medium,
        showTranslation: Bool = false,
        onSeekToTime: @escaping (Double) -> Void
    ) {
        self.document = document
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.liveTimeProvider = liveTimeProvider ?? { currentTime }
        self.accentColor = accentColor
        self.fontSizePreset = fontSizePreset
        self.showTranslation = showTranslation
        self.onSeekToTime = onSeekToTime
    }

    private static func nodeId(for line: LyricLineItem) -> String {
        "classic_line_\(line.id)"
    }

    private var documentSignature: String {
        "\(document.lines.count)|\(document.lines.first?.text ?? "")|\(fontSizePreset.rawValue)|\(showTranslation)"
    }

    private var activeLineNodeId: String? {
        guard document.kind != .plain else { return nil }
        if activeLineIndex >= 0 && activeLineIndex < document.lines.count {
            return Self.nodeId(for: document.lines[activeLineIndex])
        }
        if let first = document.lines.first {
            return Self.nodeId(for: first)
        }
        return nil
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ClassicActiveLineDriver(
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
                            targetNodeId: activeLineNodeId,
                            nodeFrames: nodeFrames,
                            documentSignature: documentSignature,
                            syncTriggerToken: syncTriggerToken,
                            isPlainLyrics: document.kind == .plain,
                            isUserBrowsing: $isUserBrowsing
                        )
                        .frame(width: 0, height: 0)
                        #endif

                        VStack(alignment: .leading, spacing: 20) {
                            Spacer().frame(height: 32)

                            ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                                let rowNodeId = Self.nodeId(for: line)
                                ClassicKaraokeLineRow(
                                    line: line,
                                    index: index,
                                    activeLineIndex: activeLineIndex,
                                    selectedPlainLineIndex: selectedPlainLineIndex,
                                    syncKind: document.kind,
                                    isPlaying: isPlaying,
                                    liveTimeProvider: liveTimeProvider,
                                    accentColor: accentColor,
                                    scaleFactor: fontSizePreset.scaleFactor,
                                    showTranslation: showTranslation,
                                    onTap: {
                                        if document.kind == .plain {
                                            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.38)) {
                                                selectedPlainLineIndex = (selectedPlainLineIndex == index) ? nil : index
                                            }
                                        } else {
                                            activeLineIndex = index
                                            isUserBrowsing = false
                                            syncTriggerToken &+= 1
                                            onSeekToTime(line.time)
                                            #if !canImport(UIKit)
                                            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.56)) {
                                                proxy.scrollTo(rowNodeId, anchor: UnitPoint(x: 0.5, y: 0.34))
                                            }
                                            #endif
                                        }
                                    }
                                )
                                .reportLyricNodeFrame(id: rowNodeId)
                                .id(rowNodeId)
                            }

                            Spacer().frame(height: 200)
                        }
                        .padding(.horizontal, 24)
                        .coordinateSpace(name: "LyricsScrollContent")
                    }
                }
                .onPreferenceChange(LyricNodeFramePreferenceKey.self) { updated in
                    nodeFrames = updated
                }
                .onAppear {
                    let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                    activeLineIndex = idx
                    #if !canImport(UIKit)
                    if idx >= 0 && idx < document.lines.count {
                        proxy.scrollTo(Self.nodeId(for: document.lines[idx]), anchor: UnitPoint(x: 0.5, y: 0.34))
                    }
                    #endif
                }
                .onChange(of: document.lines.count) { _, _ in
                    selectedPlainLineIndex = nil
                    isUserBrowsing = false
                    let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                    activeLineIndex = idx
                    #if !canImport(UIKit)
                    if idx >= 0 && idx < document.lines.count {
                        proxy.scrollTo(Self.nodeId(for: document.lines[idx]), anchor: UnitPoint(x: 0.5, y: 0.34))
                    }
                    #endif
                }

                if isUserBrowsing && document.kind != .plain {
                    Button {
                        let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                        activeLineIndex = idx
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            isUserBrowsing = false
                        }
                        syncTriggerToken &+= 1
                        #if !canImport(UIKit)
                        if idx >= 0 && idx < document.lines.count {
                            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.62)) {
                                proxy.scrollTo(Self.nodeId(for: document.lines[idx]), anchor: UnitPoint(x: 0.5, y: 0.34))
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

private struct ClassicActiveLineDriver: View {
    let lines: [LyricLineItem]
    let isPlaying: Bool
    let liveTimeProvider: () -> Double
    @Binding var activeLineIndex: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 90.0, paused: !isPlaying)) { context in
            let _ = context.date
            let computed = LRCParser.findActiveLineIndex(lines: lines, currentTime: liveTimeProvider())
            Color.clear
                .onChange(of: computed) { _, nextIdx in
                    if activeLineIndex != nextIdx {
                        withAnimation(.timingCurve(0.20, 0.96, 0.32, 1.0, duration: 0.54)) {
                            activeLineIndex = nextIdx
                        }
                    }
                }
        }
    }
}

private struct ClassicKaraokeLineRow: View {
    let line: LyricLineItem
    let index: Int
    let activeLineIndex: Int
    let selectedPlainLineIndex: Int?
    let syncKind: ParsedLyricsSyncKind
    let isPlaying: Bool
    let liveTimeProvider: () -> Double
    let accentColor: Color
    let scaleFactor: CGFloat
    let showTranslation: Bool
    let onTap: () -> Void

    private var isActive: Bool {
        if syncKind == .plain {
            return selectedPlainLineIndex == index
        }
        return index == activeLineIndex
    }

    private var inactiveAlpha: Double {
        if syncKind == .plain {
            return 0.46
        }
        let isPast = activeLineIndex >= 0 && index < activeLineIndex
        return isPast ? 0.36 : 0.28
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                if syncKind == .plain && isActive {
                    Capsule()
                        .fill(accentColor)
                        .frame(width: 3.5)
                        .padding(.vertical, 3)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(line.text)
                        .font(.system(size: 24 * scaleFactor, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? Color.white : Color.white.opacity(inactiveAlpha))
                        .lineLimit(1)
                        .minimumScaleFactor(0.30)
                        .allowsTightening(true)
                        .overlay(alignment: .leading) {
                            if isActive && syncKind != .plain {
                                ClassicActiveLineUnderline(
                                    startTime: line.time,
                                    endTime: line.endTime,
                                    isPlaying: isPlaying,
                                    liveTimeProvider: liveTimeProvider,
                                    accentColor: accentColor
                                )
                            }
                        }

                    if showTranslation, let tr = line.translation, !tr.isEmpty {
                        Text(tr)
                            .font(.system(size: 15 * scaleFactor, weight: .medium, design: .rounded))
                            .foregroundStyle(isActive ? accentColor : Color.white.opacity(0.32))
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .allowsTightening(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .scaleEffect(isActive ? 1.0 : 0.962, anchor: .leading)
            .animation(.timingCurve(0.20, 0.96, 0.32, 1.0, duration: 0.54), value: isActive)
        }
        .buttonStyle(.plain)
    }
}

private struct ClassicActiveLineUnderline: View {
    let startTime: Double
    let endTime: Double
    let isPlaying: Bool
    let liveTimeProvider: () -> Double
    let accentColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !isPlaying)) { context in
            let _ = context.date
            let lineDuration = max(0.25, endTime - startTime)
            let lineProgress = HarmonoidMeshEngine.clamp(
                (liveTimeProvider() - startTime) / lineDuration,
                0.0,
                1.0
            )
            GeometryReader { geo in
                Capsule()
                    .fill(accentColor.opacity(0.45))
                    .frame(width: geo.size.width * lineProgress, height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }
}
