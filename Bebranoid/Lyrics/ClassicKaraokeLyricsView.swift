import SwiftUI

/// Классический караоке-движок (`src/components/ClassicKaraokeLyrics.jsx`).
/// Отображает однородные строки без скачков переноса (`VStack` + единый вес шрифта `.bold`),
/// с плавным 120 Гц прогрессом активной строки, переводом на русский язык и перемоткой по тапу.
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

    public var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { context in
                let _ = context.date
                let computed = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                Color.clear
                    .onChange(of: computed) { _, nextIdx in
                        if activeLineIndex != nextIdx {
                            activeLineIndex = nextIdx
                        }
                    }
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Spacer().frame(height: 28)

                        ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                            let isActive = document.kind != .plain && index == activeLineIndex
                            let isPast = document.kind != .plain && index < activeLineIndex

                            Button {
                                if document.kind != .plain {
                                    onSeekToTime(line.time)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(line.text)
                                        .font(.system(size: 24 * fontSizePreset.scaleFactor, weight: .bold, design: .rounded))
                                        .foregroundStyle(
                                            isActive
                                                ? Color.white
                                                : Color.white.opacity(isPast ? 0.36 : 0.42)
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                        .overlay(alignment: .leading) {
                                            if isActive {
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
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .scaleEffect(isActive ? 1.0 : 0.96, anchor: .leading)
                                .animation(.spring(response: 0.42, dampingFraction: 0.94), value: isActive)
                            }
                            .buttonStyle(.plain)
                            .id(line.id)
                        }

                        Spacer().frame(height: 180)
                    }
                    .padding(.horizontal, 24)
                }
                .onAppear {
                    let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                    activeLineIndex = idx
                    if idx >= 0 && idx < document.lines.count {
                        proxy.scrollTo(document.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
                    }
                }
                .onChange(of: activeLineIndex) { _, newIdx in
                    guard newIdx >= 0, newIdx < document.lines.count else { return }
                    let lineId = document.lines[newIdx].id
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.97, blendDuration: 0.16)) {
                        proxy.scrollTo(lineId, anchor: UnitPoint(x: 0.5, y: 0.34))
                    }
                }
            }
        }
    }
}
