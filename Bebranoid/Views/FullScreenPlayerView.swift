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
    @State private var trackChangeSettleScale: CGFloat = 1.0
    @StateObject private var gyro = GyroscopeMotionManager()

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

                    // Большая квадратная 3D-обложка альбома (свайп влево/вправо переключает треки, свайп вниз закрывает плеер, гироскоп вращает в 3D)
                    let coverSide = min(geo.size.width - 48, geo.size.height * 0.43)
                    let tiltX = appState.isGyroscope3DCoverEnabled ? gyro.tiltXDegrees : 0.0
                    let tiltY = appState.isGyroscope3DCoverEnabled ? gyro.tiltYDegrees : 0.0
                    let tiltMagnitude = min(1.0, hypot(tiltX, tiltY) / 20.0)
                    let resolvedLocalCoverPath = track.flatMap { appState.libraryState.customAlbumCovers[$0.album] ?? $0.coverPath }
                    let coverFallbackSeed = "\(track?.album ?? "")|\(track?.artist ?? "")"

                    ZStack(alignment: .bottom) {
                        // Идеальное 3D-продолжение крайних пикселей самой обложки по бокам (8-слойная экструзия вглубь с естественным затенением торца)
                        if appState.isGyroscope3DCoverEnabled && tiltMagnitude > 0.015 {
                            ForEach((1...8).reversed(), id: \.self) { sliceIdx in
                                let frac = Double(sliceIdx) / 8.0
                                ArtworkThumbnailView(
                                    track: track,
                                    localPath: resolvedLocalCoverPath,
                                    remoteURL: track?.remoteArtworkURL,
                                    fallbackSeed: coverFallbackSeed,
                                    cornerRadius: 28,
                                    sizeTier: .fullPlayer,
                                    enableSmoothTransition: true,
                                    showBorder: false
                                )
                                .frame(width: coverSide, height: coverSide)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                                        .fill(Color.black.opacity(0.14 + 0.34 * frac))
                                )
                                .offset(
                                    x: CGFloat(-tiltY * 0.44 * frac),
                                    y: CGFloat(tiltX * 0.44 * frac)
                                )
                                .allowsHitTesting(false)
                            }
                        }

                        // Живой бегущий ободок вокруг обложки 1:1 как на ПК (`.andro-cover-living-shell` + `.andro-cover-living-spin` 7.5s linear)
                        CoverLivingRimShellView(
                            accentRGB: appState.accentRGB,
                            cornerRadius: 28,
                            isPaused: appState.isReducedMotionEnabled || dragDismissOffset > 1 || abs(coverHorizontalOffset) > 1
                        ) {
                            ArtworkThumbnailView(
                                track: track,
                                localPath: resolvedLocalCoverPath,
                                remoteURL: track?.remoteArtworkURL,
                                fallbackSeed: coverFallbackSeed,
                                cornerRadius: 25.5,
                                sizeTier: .fullPlayer,
                                enableSmoothTransition: true,
                                showBorder: false
                            )
                        }
                        .frame(width: coverSide, height: coverSide)
                        .overlay {
                            if appState.isGyroscope3DCoverEnabled {
                                // Подвижный блик света и стеклянная 3D-фаска при вращении телефона
                                let lightCenter = UnitPoint(
                                    x: max(0.05, min(0.95, 0.5 - gyro.specularUnitOffset.width * 0.42)),
                                    y: max(0.05, min(0.95, 0.38 - gyro.specularUnitOffset.height * 0.42))
                                )
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.white.opacity(0.16 * tiltMagnitude),
                                                Color.white.opacity(0.03 * tiltMagnitude),
                                                Color.clear
                                            ],
                                            center: lightCenter,
                                            startRadius: 8,
                                            endRadius: coverSide * 0.78
                                        )
                                    )
                                    .allowsHitTesting(false)
                            }
                        }

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
                    .rotation3DEffect(
                        .degrees(tiltX),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.52
                    )
                    .rotation3DEffect(
                        .degrees(tiltY),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.52
                    )
                    .offset(x: coverHorizontalOffset)
                    .rotationEffect(.degrees(Double(coverHorizontalOffset) * 0.035))
                    .scaleEffect((appState.isPlaying ? 1.0 : 0.93) * trackChangeSettleScale)
                    .shadow(
                        color: Color.black.opacity(0.50),
                        radius: 28,
                        x: CGFloat(-tiltY * 0.85),
                        y: 16 + CGFloat(tiltX * 0.75)
                    )
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
        .onAppear {
            gyro.setActive(appState.isGyroscope3DCoverEnabled && !appState.isLyricsScreenPresented)
        }
        .onDisappear {
            gyro.stop()
        }
        .onChange(of: appState.isGyroscope3DCoverEnabled) { _, enabled in
            gyro.setActive(enabled && !appState.isLyricsScreenPresented)
        }
        .onChange(of: appState.isLyricsScreenPresented) { _, lyricsOpen in
            gyro.setActive(appState.isGyroscope3DCoverEnabled && !lyricsOpen)
        }
        .onChange(of: track?.id) { _, _ in
            trackChangeSettleScale = 0.972
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.68)) {
                trackChangeSettleScale = 1.0
            }
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
                        appState.skipToNext(isManualUserAction: true)
                        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.52)) {
                            coverHorizontalOffset = 0
                        }
                    } else if dx > 46 || predictedX > 110 {
                        appState.skipToPrevious()
                        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.52)) {
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

                    Divider()

                    Button {
                        appState.haptics.softSelection()
                        appState.isGyroscope3DCoverEnabled.toggle()
                    } label: {
                        Label(
                            appState.isGyroscope3DCoverEnabled ? "Выключить 3D-гироскоп обложки" : "Включить 3D-гироскоп обложки",
                            systemImage: appState.isGyroscope3DCoverEnabled ? "gyroscope" : "cube.transparent"
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

/// Живой бегущий световой ободок вокруг обложки (`.andro-cover-living-shell` + `.andro-cover-living-spin` из `C:\VibeCoding\Bebranoid\src\index.css` строки 939–1003):
/// конический градиент делает полный оборот за `7.5s` линейно вокруг отступа `2.5 pt` лицевой грани обложки с мягким акцентным свечением.
private struct CoverLivingRimShellView<FaceContent: View>: View {
    let accentRGB: MeshRGB
    let cornerRadius: CGFloat
    let isPaused: Bool
    @ViewBuilder let faceContent: () -> FaceContent

    private func mixColor(accentWeight: Double, baseR: Double, baseG: Double, baseB: Double) -> Color {
        let norm = accentRGB.normalizedDouble
        let w = min(1.0, max(0.0, accentWeight))
        let r = norm.r * w + baseR * (1.0 - w)
        let g = norm.g * w + baseG * (1.0 - w)
        let b = norm.b * w + baseB * (1.0 - w)
        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        let norm = accentRGB.normalizedDouble
        let pureAccent = Color(red: norm.r, green: norm.g, blue: norm.b)
        let dark50 = mixColor(accentWeight: 0.50, baseR: 0.067, baseG: 0.067, baseB: 0.067) // 50% accent + #111
        let dark48 = mixColor(accentWeight: 0.48, baseR: 0.067, baseG: 0.067, baseB: 0.067) // 48% accent + #111
        let bright82 = mixColor(accentWeight: 0.82, baseR: 1.0, baseG: 1.0, baseB: 1.0)     // 82% accent + #fff
        let bright78 = mixColor(accentWeight: 0.78, baseR: 1.0, baseG: 1.0, baseB: 1.0)     // 78% accent + #fff

        let stops: [Gradient.Stop] = [
            .init(color: dark50, location: 0.0 / 360.0),
            .init(color: pureAccent, location: 55.0 / 360.0),
            .init(color: bright82, location: 100.0 / 360.0),
            .init(color: pureAccent, location: 160.0 / 360.0),
            .init(color: dark48, location: 220.0 / 360.0),
            .init(color: bright78, location: 280.0 / 360.0),
            .init(color: dark50, location: 1.0)
        ]

        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isPaused)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let angleDeg = (t.truncatingRemainder(dividingBy: 7.5) / 7.5) * 360.0

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        AngularGradient(
                            gradient: Gradient(stops: stops),
                            center: .center,
                            startAngle: .degrees(angleDeg),
                            endAngle: .degrees(angleDeg + 360.0)
                        )
                    )
            }

            faceContent()
                .background(Color(red: 0.02, green: 0.02, blue: 0.02))
                .clipShape(RoundedRectangle(cornerRadius: max(4, cornerRadius - 2.5), style: .continuous))
                .padding(2.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: pureAccent.opacity(0.36), radius: 14, x: 0, y: 0)
        .shadow(color: pureAccent.opacity(0.42), radius: 4, x: 0, y: 0)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.65), value: accentRGB)
    }
}
