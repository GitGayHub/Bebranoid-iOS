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
    @State private var isUserBrowsing: Bool = false
    @State private var autoResumeTask: Task<Void, Never>? = nil
    @State private var selectedPlainLineIndex: Int? = nil

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
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
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

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Spacer().frame(height: 28)

                        ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                            let isActive = document.kind == .plain
                                ? (selectedPlainLineIndex == index)
                                : (index == activeLineIndex)
                            let isPast = document.kind != .plain && activeLineIndex >= 0 && index < activeLineIndex
                            let inactiveAlpha: Double = document.kind == .plain
                                ? 0.46
                                : (isPast ? 0.36 : 0.28)

                            Button {
                                autoResumeTask?.cancel()
                                if document.kind == .plain {
                                    withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.38)) {
                                        selectedPlainLineIndex = (selectedPlainLineIndex == index) ? nil : index
                                    }
                                } else {
                                    isUserBrowsing = false
                                    onSeekToTime(line.time)
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
                                            .fixedSize(horizontal: false, vertical: true)
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
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                                .scaleEffect(isActive ? 1.0 : 0.96, anchor: .leading)
                                .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.62), value: isActive)
                            }
                            .buttonStyle(.plain)
                            .id(line.id)
                        }

                        Spacer().frame(height: 180)
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
                            autoResumeTask?.cancel()
                            autoResumeTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 4_500_000_000)
                                guard !Task.isCancelled else { return }
                                isUserBrowsing = false
                            }
                        }
                )
                .onAppear {
                    let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                    activeLineIndex = idx
                    if idx >= 0 && idx < document.lines.count {
                        proxy.scrollTo(document.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
                    }
                }
                .onChange(of: document.lines.count) { _, _ in
                    selectedPlainLineIndex = nil
                    let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                    activeLineIndex = idx
                    if idx >= 0 && idx < document.lines.count {
                        proxy.scrollTo(document.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
                    }
                }
                .onChange(of: activeLineIndex) { _, newIdx in
                    guard !isUserBrowsing, newIdx >= 0, newIdx < document.lines.count else { return }
                    let lineId = document.lines[newIdx].id
                    withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.68)) {
                        proxy.scrollTo(lineId, anchor: UnitPoint(x: 0.5, y: 0.34))
                    }
                }
                .onChange(of: isUserBrowsing) { _, browsing in
                    if !browsing {
                        let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                        activeLineIndex = idx
                        if idx >= 0 && idx < document.lines.count {
                            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.68)) {
                                proxy.scrollTo(document.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
                            }
                        }
                    }
                }

                if isUserBrowsing && document.kind != .plain {
                    Button {
                        autoResumeTask?.cancel()
                        let idx = LRCParser.findActiveLineIndex(lines: document.lines, currentTime: liveTimeProvider())
                        activeLineIndex = idx
                        isUserBrowsing = false
                        if idx >= 0 && idx < document.lines.count {
                            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.68)) {
                                proxy.scrollTo(document.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
                            }
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
    }
}
