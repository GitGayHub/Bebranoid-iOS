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

    private var documentSignature: String {
        "\(document.lines.count)|\(document.lines.first?.text ?? "")|\(fontSizePreset.rawValue)|\(showTranslation)"
    }

    private var activeLineId: String? {
        guard document.kind != .plain, activeLineIndex >= 0, activeLineIndex < document.lines.count else {
            return document.lines.first?.id
        }
        return document.lines[activeLineIndex].id
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                TimelineView(.animation(minimumInterval: 1.0 / 90.0, paused: !isPlaying)) { context in
                    let _ = context.date
                    let computed = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                    Color.clear
                        .onChange(of: computed) { _, nextIdx in
                            if activeLineIndex != nextIdx {
                                withAnimation(.timingCurve(0.20, 0.96, 0.32, 1.0, duration: 0.54)) {
                                    activeLineIndex = nextIdx
                                }
                            }
                        }
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        #if canImport(UIKit)
                        LyricsSmoothScrollBridge(
                            targetNodeId: activeLineId,
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
                                let isActive = document.kind == .plain
                                    ? (selectedPlainLineIndex == index)
                                    : (index == activeLineIndex)
                                let isPast = document.kind != .plain && activeLineIndex >= 0 && index < activeLineIndex
                                let inactiveAlpha: Double = document.kind == .plain
                                    ? 0.46
                                    : (isPast ? 0.36 : 0.28)

                                Button {
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
                                            proxy.scrollTo(line.id, anchor: UnitPoint(x: 0.5, y: 0.34))
                                        }
                                        #endif
                                    }
                                } label: {
                                    HStack(alignment: .center, spacing: 10) {
                                        if document.kind == .plain && isActive {
                                            Capsule()
                                                .fill(accentColor)
                                                .frame(width: 3.5)
                                                .padding(.vertical, 3)
                                        }

                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(line.text)
                                                .font(.system(size: 24 * fontSizePreset.scaleFactor, weight: .bold, design: .rounded))
                                                .foregroundStyle(
                                                    isActive
                                                        ? Color.white
                                                        : Color.white.opacity(inactiveAlpha)
                                                )
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.30)
                                                .allowsTightening(true)
                                                .overlay(alignment: .leading) {
                                                    if isActive && document.kind != .plain {
                                                        TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !isPlaying)) { context in
                                                            let _ = context.date
                                                            let lineDuration = max(0.25, line.endTime - line.time)
                                                            let lineProgress = HarmonoidMeshEngine.clamp(
                                                                (liveTimeProvider() - line.time) / lineDuration,
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

                                            if showTranslation, let tr = line.translation, !tr.isEmpty {
                                                Text(tr)
                                                    .font(.system(size: 15 * fontSizePreset.scaleFactor, weight: .medium, design: .rounded))
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
                                .reportLyricNodeFrame(id: line.id)
                                .id(line.id)
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
                        proxy.scrollTo(document.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
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
                        proxy.scrollTo(document.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
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
                                proxy.scrollTo(document.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
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
