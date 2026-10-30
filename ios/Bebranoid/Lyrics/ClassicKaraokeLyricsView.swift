import SwiftUI

/// Классический караоке-движок (`src/components/ClassicKaraokeLyrics.jsx`).
/// Отображает центрированные или выровненные строки с плавным прогрессом заполнения активной строки/слова,
/// переводом на русский язык и перемоткой по клику на любую строку.
public struct ClassicKaraokeLyricsView: View {
    public let document: ParsedLyricsDocument
    public let currentTime: Double
    public let accentColor: Color
    public let fontSizePreset: LyricsFontSizePreset
    public let showTranslation: Bool
    public let onSeekToTime: (Double) -> Void

    public init(
        document: ParsedLyricsDocument,
        currentTime: Double,
        accentColor: Color,
        fontSizePreset: LyricsFontSizePreset = .medium,
        showTranslation: Bool = false,
        onSeekToTime: @escaping (Double) -> Void
    ) {
        self.document = document
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
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Spacer().frame(height: 24)

                    ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = document.kind != .plain && index == activeLineIndex
                        let isPast = document.kind != .plain && index < activeLineIndex
                        let lineDuration = max(0.25, line.endTime - line.time)
                        let lineProgress = isActive
                            ? HarmonoidMeshEngine.clamp((currentTime - line.time) / lineDuration, 0.0, 1.0)
                            : (isPast ? 1.0 : 0.0)

                        Button {
                            if document.kind != .plain {
                                onSeekToTime(line.time)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(line.text)
                                    .font(.system(size: 24 * fontSizePreset.scaleFactor, weight: isActive ? .bold : .semibold, design: .rounded))
                                    .foregroundStyle(
                                        isActive
                                            ? Color.white
                                            : Color.white.opacity(isPast ? 0.35 : 0.45)
                                    )
                                    .overlay(alignment: .leading) {
                                        if isActive {
                                            GeometryReader { geo in
                                                Rectangle()
                                                    .fill(accentColor.opacity(0.30))
                                                    .frame(width: geo.size.width * lineProgress, height: 3)
                                                    .frame(maxHeight: .infinity, alignment: .bottom)
                                            }
                                        }
                                    }

                                if showTranslation, let tr = line.translation, !tr.isEmpty {
                                    Text(tr)
                                        .font(.system(size: 15 * fontSizePreset.scaleFactor, weight: .medium, design: .rounded))
                                        .foregroundStyle(isActive ? accentColor : Color.white.opacity(0.32))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .scaleEffect(isActive ? 1.02 : 1.0, anchor: .leading)
                        }
                        .buttonStyle(.plain)
                        .id(line.id)
                    }

                    Spacer().frame(height: 160)
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: activeLineIndex) { _, newIdx in
                guard newIdx >= 0, newIdx < document.lines.count else { return }
                let lineId = document.lines[newIdx].id
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(lineId, anchor: .center)
                }
            }
        }
    }
}
