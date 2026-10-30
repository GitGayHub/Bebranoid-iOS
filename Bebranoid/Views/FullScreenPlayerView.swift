import SwiftUI

/// Полноэкранный плеер Bebranoid iOS, спроектированный по референсному скриншоту 1 (`src/views/NowPlaying.jsx` + `src/components/Player.jsx`).
/// Включает:
/// - Живой фон `HarmonoidMeshView`, синхронизированный с обложкой и аудио-кроссфейдом
/// - Верхнюю панель с кнопкой сворачивания `⌄` и меню трека `•••`
/// - Крупную квадратную обложку со скруглёнными углами (`28 pt`) и плавной пружинной анимацией масштаба
/// - Название трека, исполнителя/альбома и 3 круглые кнопки справа (`Избранное`, `Инфо`, `Очередь`)
/// - Капсульную панель быстрого доступа (`Текст`, `FX: ...`, `Bass Boost`)
/// - Крупные кнопки управления воспроизведением (`Shuffle`, `Prev`, круглая акцентная `Play/Pause`, `Next`, `Repeat`)
/// - Плавный слайдер прогресса, таймкоды и техническую плашку качества (`FLAC • 44.1 kHz • 952 kbps` / `Hi-Res` / `Lossless`)
public struct FullScreenPlayerView: View {
    @ObservedObject var appState: BebranoidAppState
    @Environment(\.dismiss) private var dismiss

    @State private var isDraggingSlider: Bool = false
    @State private var draggedTime: Double = 0.0
    @State private var dragDismissOffset: CGFloat = 0.0
    @State private var coverHorizontalOffset: CGFloat = 0.0
    @State private var lockedGestureAxis: Axis? = nil

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    private var track: Track? {
        appState.currentTrack
    }

    private var displayedTime: Double {
        isDraggingSlider ? draggedTime : appState.currentTime
    }

    private var activeDownloadPercent: Int? {
        appState.downloadProgress(for: track)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                #if DEBUG
                let fixedTime = appState.demoFixedMeshTime
                #else
                let fixedTime: Double? = nil
                #endif
                HarmonoidMeshView(
                    currentPalette: appState.currentPalette,
                    nextPalette: appState.nextTrackPalette,
                    crossfadeProgress: appState.crossfadeProgress,
                    isReducedMotion: appState.isReducedMotionEnabled || dragDismissOffset > 1 || abs(coverHorizontalOffset) > 1,
                    fixedAnimationTime: fixedTime
                )

                VStack(spacing: 0) {
                    topHeaderBar
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                        .gesture(headerDismissGesture)

                    Spacer(minLength: 12)

                    // Большая квадратная обложка альбома (ТОЛЬКО по обложке: свайп влево/вправо переключает треки, свайп вниз закрывает плеер)
                    let coverSide = min(geo.size.width - 48, geo.size.height * 0.43)
                    ZStack(alignment: .bottom) {
                        ArtworkThumbnailView(
                            track: track,
                            localPath: track.flatMap { appState.libraryState.customAlbumCovers[$0.album] ?? $0.coverPath },
                            remoteURL: track?.remoteArtworkURL,
                            fallbackSeed: "\(track?.album ?? "")|\(track?.artist ?? "")",
                            cornerRadius: 28,
                            sizeTier: .fullPlayer
                        )
                        .frame(width: coverSide, height: coverSide)

                        if let pct = activeDownloadPercent {
                            VStack(spacing: 6) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                    Text("Загрузка трека: \(pct)%")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                ProgressView(value: Double(max(1, min(100, pct))), total: 100.0)
                                    .tint(appState.accentSwiftUIColor)
                                    .frame(width: coverSide * 0.68)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.bottom, 14)
                        }
                    }
                    .frame(width: coverSide, height: coverSide)
                    .contentShape(Rectangle())
                    .offset(x: coverHorizontalOffset)
                    .rotationEffect(.degrees(Double(coverHorizontalOffset) * 0.035))
                    .scaleEffect(appState.isPlaying ? 1.0 : 0.93)
                    .shadow(color: Color.black.opacity(0.48), radius: 28, x: 0, y: 16)
                    .animation(.spring(response: 0.36, dampingFraction: 0.80), value: appState.isPlaying)
                    .highPriorityGesture(coverOnlyInteractiveGesture(coverWidth: coverSide))

                    Spacer(minLength: 20)

                    // Блок названия трека, исполнителя и 3 круглых кнопок справа (Heart, Info, Queue)
                    trackMetadataAndQuickActionsRow
                        .padding(.horizontal, 24)

                    Spacer(minLength: 14)

                    // Центральная капсула переключения в Текст / FX / Bass
                    centerModePillRow
                        .padding(.horizontal, 24)

                    Spacer(minLength: 18)

                    // Крупные центральные кнопки управления воспроизведением
                    transportControlsRow
                        .padding(.horizontal, 28)

                    Spacer(minLength: 20)

                    // Слайдер прогресса + время + кодек/частота/битрейт
                    progressAndTechnicalFooter
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(18, geo.safeAreaInsets.bottom > 0 ? 12 : 22))
                }
                .scaleEffect(max(0.92, 1.0 - (dragDismissOffset / 1800.0)))
                .offset(y: dragDismissOffset)
            }
        }
        .sheet(isPresented: $appState.isQueueSheetPresented) {
            QueueSheetView(appState: appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appState.isAudioFXSheetPresented) {
            AudioFXSheetView(appState: appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $appState.inspectedTrackForInfo) { targetTrack in
            TrackInfoSheetView(track: targetTrack, formatInfo: appState.audioEngine.currentFormatInfo ?? targetTrack.formatInfo)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $appState.isLyricsScreenPresented) {
            LyricsScreenView(appState: appState)
        }
    }

    private var headerDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dy = value.translation.height
                let dx = abs(value.translation.width)
                if dy > 0 && dy > dx * 0.8 {
                    dragDismissOffset = dy * 0.88
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                let predictedY = value.predictedEndTranslation.height
                if dy > 42 || predictedY > 95 {
                    dragDismissOffset = 0
                    appState.haptics.softSelection()
                    appState.isFullScreenPlayerPresented = false
                    dismiss()
                } else {
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.84)) {
                        dragDismissOffset = 0
                    }
                }
            }
    }

    private func coverOnlyInteractiveGesture(coverWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard !isDraggingSlider else { return }
                let dx = value.translation.width
                let dy = value.translation.height

                if lockedGestureAxis == nil {
                    if abs(dx) > 7 || abs(dy) > 7 {
                        if dy > 6 && dy >= abs(dx) * 0.85 {
                            lockedGestureAxis = .vertical
                        } else if abs(dx) > abs(dy) * 1.15 {
                            lockedGestureAxis = .horizontal
                        }
                    }
                }

                switch lockedGestureAxis {
                case .horizontal:
                    coverHorizontalOffset = dx * 0.88
                case .vertical:
                    dragDismissOffset = max(0, dy * 0.88)
                case .none:
                    break
                }
            }
            .onEnded { value in
                defer { lockedGestureAxis = nil }
                guard !isDraggingSlider else {
                    dragDismissOffset = 0
                    coverHorizontalOffset = 0
                    return
                }

                let dx = value.translation.width
                let dy = value.translation.height
                let predictedX = value.predictedEndTranslation.width
                let predictedY = value.predictedEndTranslation.height

                switch lockedGestureAxis {
                case .horizontal:
                    if dx < -46 || predictedX < -110 {
                        withAnimation(.easeOut(duration: 0.12)) {
                            coverHorizontalOffset = -coverWidth * 0.38
                        }
                        appState.skipToNext(isManualUserAction: true)
                        coverHorizontalOffset = coverWidth * 0.24
                        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
                            coverHorizontalOffset = 0
                        }
                    } else if dx > 46 || predictedX > 110 {
                        withAnimation(.easeOut(duration: 0.12)) {
                            coverHorizontalOffset = coverWidth * 0.38
                        }
                        appState.skipToPrevious()
                        coverHorizontalOffset = -coverWidth * 0.24
                        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
                            coverHorizontalOffset = 0
                        }
                    } else {
                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84)) {
                            coverHorizontalOffset = 0
                        }
                    }

                case .vertical:
                    if dy > 42 || predictedY > 95 {
                        dragDismissOffset = 0
                        appState.haptics.softSelection()
                        appState.isFullScreenPlayerPresented = false
                        dismiss()
                    } else {
                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84)) {
                            dragDismissOffset = 0
                        }
                    }

                case .none:
                    if dy > 42 || predictedY > 95 {
                        dragDismissOffset = 0
                        appState.haptics.softSelection()
                        appState.isFullScreenPlayerPresented = false
                        dismiss()
                    } else {
                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84)) {
                            dragDismissOffset = 0
                            coverHorizontalOffset = 0
                        }
                    }
                }
            }
    }

    // MARK: - Subviews

    private var topHeaderBar: some View {
        HStack {
            Button {
                appState.isFullScreenPlayerPresented = false
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.10), in: Circle())
            }

            Spacer()

            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 38, height: 5)

            Spacer()

            Menu {
                if let current = track {
                    Button {
                        appState.inspectedTrackForInfo = current
                    } label: {
                        Label("Сведения о файле", systemImage: "info.circle")
                    }

                    Button {
                        appState.isAudioFXSheetPresented = true
                    } label: {
                        Label("Звуковые эффекты и скорость", systemImage: "slider.horizontal.3")
                    }

                    Button {
                        appState.toggleLyricsDisabled(for: current)
                    } label: {
                        Label(
                            appState.isLyricsDisabled(for: current) ? "Включить текст для трека" : "Отключить текст для трека",
                            systemImage: appState.isLyricsDisabled(for: current) ? "text.quote" : "eye.slash"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
        }
    }

    private var trackMetadataAndQuickActionsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(track?.title ?? "Трек не выбран")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // 3 круглые стеклянные кнопки как на референсе 1: Heart, Info, Queue
            HStack(spacing: 10) {
                let isLiked = track.map { appState.isFavorite($0) } ?? false
                Button {
                    if let current = track {
                        appState.toggleFavorite(track: current)
                    }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isLiked ? Color(red: 1.0, green: 0.34, blue: 0.52) : .white.opacity(0.85))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.10), in: Circle())
                }

                Button {
                    appState.inspectedTrackForInfo = track
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.10), in: Circle())
                }

                Button {
                    appState.isQueueSheetPresented = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
            }
        }
    }

    private var centerModePillRow: some View {
        let hasAvailableLyrics = !appState.currentLyricsDocument.lines.isEmpty && !(track.map { appState.isLyricsDisabled(for: $0) } ?? false)
        return HStack(spacing: 10) {
            if hasAvailableLyrics {
                Button {
                    appState.haptics.lightTap()
                    appState.isLyricsScreenPresented = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "music.note")
                            .font(.system(size: 14, weight: .bold))
                        Text("Текст")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                }
            }

            Button {
                appState.haptics.lightTap()
                appState.isAudioFXSheetPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                    Text(fxPillTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(isAnyFXActive ? appState.accentSwiftUIColor : .white.opacity(0.82))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.10), in: Capsule())
            }
        }
    }

    private var transportControlsRow: some View {
        HStack(
            alignment: .center,
            spacing: 26
        ) {
            Button {
                appState.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(appState.isShuffleEnabled ? appState.accentSwiftUIColor : .white.opacity(0.55))
            }

            Button {
                appState.skipToPrevious()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }

            Button {
                appState.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(appState.accentSwiftUIColor)
                        .frame(width: 72, height: 72)
                        .shadow(color: appState.accentSwiftUIColor.opacity(0.50), radius: 18, x: 0, y: 8)

                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                        .offset(x: appState.isPlaying ? 0 : 2)
                }
            }

            Button {
                appState.skipToNext(isManualUserAction: true)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }

            Button {
                appState.cycleRepeatMode()
            } label: {
                Image(systemName: appState.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(appState.repeatMode != .none ? appState.accentSwiftUIColor : .white.opacity(0.55))
            }
        }
    }

    private var progressAndTechnicalFooter: some View {
        let effectiveDuration = appState.duration > 0 ? appState.duration : (track?.duration ?? 0.0)
        let maxDur = max(1.0, effectiveDuration)
        let clampedPos = min(maxDur, max(0.0, displayedTime))

        return VStack(spacing: 8) {
            InteractiveSeekBarView(
                currentTime: clampedPos,
                duration: maxDur,
                accentColor: appState.accentSwiftUIColor,
                isDragging: $isDraggingSlider,
                draggedTime: $draggedTime,
                onCommitSeek: { targetSec in
                    appState.haptics.softSelection()
                    appState.seek(to: targetSec)
                }
            )

            HStack(alignment: .center) {
                Text(Self.formatSeconds(clampedPos))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))

                Spacer()

                // Центральная техническая строка как на референсе: `FLAC • 44.1 kHz • 952 kbps`
                Button {
                    appState.inspectedTrackForInfo = track
                } label: {
                    let badge = appState.currentQualityBadge
                    HStack(spacing: 5) {
                        if badge.tier == .hiRes {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.78, blue: 0.35))
                                .frame(width: 6, height: 6)
                        } else if badge.tier == .lossless {
                            Circle()
                                .fill(Color(red: 0.82, green: 0.55, blue: 1.0))
                                .frame(width: 6, height: 6)
                        }
                        Text(badge.tooltipText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(Self.formatSeconds(effectiveDuration))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var subtitleText: String {
        guard let track else { return "Bebranoid iOS" }
        if !track.album.isEmpty && track.album != "Без альбома" {
            return "\(track.artist) — \(track.album)"
        }
        return track.artist
    }

    private var isAnyFXActive: Bool {
        appState.audioFXMode != .normal || appState.bassBoostEnabled || abs(appState.playbackSpeed - 1.0) > 0.01
    }

    private var fxPillTitle: String {
        var items: [String] = []
        if appState.audioFXMode != .normal {
            items.append(appState.audioFXMode.shortBadgeName)
        }
        if appState.bassBoostEnabled {
            items.append("Bass+")
        }
        if abs(appState.playbackSpeed - 1.0) > 0.01 {
            items.append(String(format: "%.2gx", appState.playbackSpeed))
        }
        return items.isEmpty ? "Звук / FX" : items.joined(separator: " • ")
    }

    public static func formatSeconds(_ totalSeconds: Double) -> String {
        guard totalSeconds.isFinite && totalSeconds > 0 else { return "0:00" }
        let whole = Int(floor(totalSeconds))
        let mins = whole / 60
        let secs = whole % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Плавная 120 Гц полоса перемотки, работающая как по одиночному тыку в любое место, так и перетаскиванием пальцем.
public struct InteractiveSeekBarView: View {
    public let currentTime: Double
    public let duration: Double
    public let accentColor: Color
    @Binding public var isDragging: Bool
    @Binding public var draggedTime: Double
    public let onCommitSeek: (Double) -> Void

    public init(
        currentTime: Double,
        duration: Double,
        accentColor: Color,
        isDragging: Binding<Bool>,
        draggedTime: Binding<Double>,
        onCommitSeek: @escaping (Double) -> Void
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.accentColor = accentColor
        self._isDragging = isDragging
        self._draggedTime = draggedTime
        self.onCommitSeek = onCommitSeek
    }

    public var body: some View {
        GeometryReader { geo in
            let width = max(1.0, geo.size.width)
            let safeDur = max(1.0, duration)
            let activeTime = isDragging ? draggedTime : currentTime
            let progress = min(1.0, max(0.0, activeTime / safeDur))
            let barHeight: CGFloat = isDragging ? 9.0 : 6.0
            let thumbSize: CGFloat = isDragging ? 18.0 : 13.0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: width, height: barHeight)

                Capsule()
                    .fill(accentColor)
                    .frame(width: max(barHeight, width * progress), height: barHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: accentColor.opacity(0.65), radius: isDragging ? 8 : 4, x: 0, y: 2)
                    .offset(x: min(width - thumbSize, max(0, width * progress - thumbSize * 0.5)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let ratio = min(1.0, max(0.0, Double(value.location.x / width)))
                        let target = ratio * safeDur
                        if !isDragging {
                            isDragging = true
                        }
                        draggedTime = target
                    }
                    .onEnded { value in
                        let ratio = min(1.0, max(0.0, Double(value.location.x / width)))
                        let target = ratio * safeDur
                        draggedTime = target
                        isDragging = false
                        onCommitSeek(target)
                    }
            )
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.82), value: isDragging)
        }
        .frame(height: 32)
    }
}
