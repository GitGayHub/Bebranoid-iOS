import SwiftUI

/// Отдельный полноэкранный экран текстов песен Bebranoid iOS по референсному скриншоту 2 (`src/views/Lyrics.jsx`).
/// Структура:
/// 1. Компактная шапка с кнопкой `⌄`, миниатюрой обложки (`46x46`), названием трека и исполнителем
/// 2. Переключатель перевода `RU`, выбор движка (`Beautiful Lyrics` / `Classic Karaoke`), размер шрифта и отключение текста для трека
/// 3. Полноэкранная область синхронизированных текстов с автоматической прокруткой, 3-точечным `Interlude`, послоговым свечением и переводом
/// 4. Компактная нижняя панель управления воспроизведением (слайдер прогресса, таймкоды, `FLAC • kHz • kbps` и кнопки `Shuffle / Prev / Play-Pause / Next / Repeat`)
public struct LyricsScreenView: View {
    @ObservedObject var appState: BebranoidAppState
    @Environment(\.dismiss) private var dismiss

    @State private var isDraggingSlider: Bool = false
    @State private var draggedTime: Double = 0.0
    @State private var dragDismissOffset: CGFloat = 0.0

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    private var track: Track? {
        appState.currentTrack
    }

    private var displayedTime: Double {
        isDraggingSlider ? draggedTime : appState.currentTime
    }

    public var body: some View {
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
                isReducedMotion: appState.isReducedMotionEnabled || dragDismissOffset > 1,
                fixedAnimationTime: fixedTime
            )

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                compactHeaderBar
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .contentShape(Rectangle())
                    .gesture(swipeDownDismissGesture)

                // Основная область текстов
                lyricsContentBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Нижняя компактная панель управления как на референсе 2
                bottomCompactTransportBar
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.0),
                                Color.black.opacity(0.38),
                                Color.black.opacity(0.65)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .offset(y: dragDismissOffset)
        }
        .onChange(of: appState.currentLyricsDocument.lines.isEmpty) { isEmpty in
            if isEmpty && !appState.isLoadingLyrics {
                appState.isLyricsScreenPresented = false
                dismiss()
            }
        }
        .onChange(of: appState.isLoadingLyrics) { loading in
            if !loading && appState.currentLyricsDocument.lines.isEmpty {
                appState.isLyricsScreenPresented = false
                dismiss()
            }
        }
    }

    private var swipeDownDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard !isDraggingSlider else { return }
                let dy = value.translation.height
                let dx = abs(value.translation.width)
                if dy > 0 && dy > dx * 0.85 {
                    dragDismissOffset = dy * 0.85
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                let predictedY = value.predictedEndTranslation.height
                if dy > 42 || predictedY > 95 {
                    dragDismissOffset = 0
                    appState.haptics.softSelection()
                    appState.isLyricsScreenPresented = false
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        dragDismissOffset = 0
                    }
                }
            }
    }

    // MARK: - Compact Header

    private var compactHeaderBar: some View {
        HStack(spacing: 12) {
            Button {
                appState.isLyricsScreenPresented = false
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.10), in: Circle())
            }

            Button {
                appState.haptics.softSelection()
                appState.isLyricsScreenPresented = false
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    ArtworkThumbnailView(
                        track: track,
                        localPath: track.flatMap { appState.libraryState.customAlbumCovers[$0.album] ?? $0.coverPath },
                        remoteURL: track?.remoteArtworkURL,
                        fallbackSeed: "\(track?.album ?? "")|\(track?.artist ?? "")",
                        cornerRadius: 10,
                        sizeTier: .listThumbnail
                    )
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track?.title ?? "Трек не выбран")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(track?.artist ?? "")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            // Кнопка перевода RU
            Button {
                appState.haptics.softSelection()
                appState.showLyricsTranslation.toggle()
            } label: {
                HStack(spacing: 4) {
                    if appState.isTranslatingLyrics {
                        ProgressView()
                            .scaleEffect(0.65)
                            .tint(.white)
                    } else {
                        Text("RU")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                }
                .foregroundStyle(appState.showLyricsTranslation ? Color(red: 0.08, green: 0.06, blue: 0.14) : .white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    appState.showLyricsTranslation ? appState.accentSwiftUIColor : Color.white.opacity(0.12),
                    in: Capsule()
                )
            }

            // Меню настроек отображения текста
            Menu {
                Picker("Движок караоке", selection: $appState.lyricsEngine) {
                    ForEach(LyricsEngineKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                Picker("Размер текста", selection: $appState.lyricsFontSize) {
                    ForEach(LyricsFontSizePreset.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }

                if let current = track {
                    Divider()
                    Button(role: appState.isLyricsDisabled(for: current) ? nil : .destructive) {
                        appState.toggleLyricsDisabled(for: current)
                    } label: {
                        Label(
                            appState.isLyricsDisabled(for: current) ? "Включить текст для этого трека" : "Отключить текст для этого трека",
                            systemImage: appState.isLyricsDisabled(for: current) ? "eye" : "eye.slash"
                        )
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
        }
    }

    // MARK: - Lyrics Content

    @ViewBuilder
    private var lyricsContentBody: some View {
        if let current = track, appState.isLyricsDisabled(for: current) {
            VStack(spacing: 14) {
                Image(systemName: "eye.slash.circle")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.45))
                Text("Текст отключён для этого трека")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Button("Включить обратно") {
                    appState.toggleLyricsDisabled(for: current)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.14), in: Capsule())
            }
            .padding(32)
        } else if appState.isLoadingLyrics {
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.white)
                Text("Поиск синхронизированного текста...")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.70))
            }
        } else if appState.currentLyricsDocument.lines.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.40))
                Text("Текст песни не найден")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Text("Проверены локальный кеш, встроенные теги и база LRCLIB.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !appState.isPlaying && !isDraggingSlider)) { context in
                let _ = context.date
                let liveTime: Double = {
                    if isDraggingSlider {
                        return draggedTime
                    }
                    if appState.isPlaying {
                        return appState.audioEngine.smoothClock.interpolatedTime(at: ProcessInfo.processInfo.systemUptime)
                    }
                    return max(appState.currentTime, appState.audioEngine.currentTime)
                }()
                switch appState.lyricsEngine {
                case .beautiful:
                    BeautifulLyricsView(
                        document: appState.currentLyricsDocument,
                        nodes: appState.currentBeautifulNodes,
                        currentTime: liveTime,
                        accentColor: appState.accentSwiftUIColor,
                        fontSizePreset: appState.lyricsFontSize,
                        showTranslation: appState.showLyricsTranslation,
                        onSeekToTime: { targetSec in
                            appState.seek(to: targetSec)
                        }
                    )
                case .classic:
                    ClassicKaraokeLyricsView(
                        document: appState.currentLyricsDocument,
                        currentTime: liveTime,
                        accentColor: appState.accentSwiftUIColor,
                        fontSizePreset: appState.lyricsFontSize,
                        showTranslation: appState.showLyricsTranslation,
                        onSeekToTime: { targetSec in
                            appState.seek(to: targetSec)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Bottom Compact Transport Bar (Reference Screenshot 2)

    private var bottomCompactTransportBar: some View {
        let effectiveDuration = appState.duration > 0 ? appState.duration : (track?.duration ?? 0.0)
        let maxDur = max(1.0, effectiveDuration)
        let clampedPos = min(maxDur, max(0.0, displayedTime))

        return VStack(spacing: 12) {
            VStack(spacing: 6) {
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

                HStack {
                    Text(FullScreenPlayerView.formatSeconds(clampedPos))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.60))

                    Spacer()

                    Text(appState.currentQualityBadge.tooltipText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)

                    Spacer()

                    Text(FullScreenPlayerView.formatSeconds(appState.duration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.60))
                }
            }

            HStack(spacing: 30) {
                Button {
                    appState.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(appState.isShuffleEnabled ? appState.accentSwiftUIColor : .white.opacity(0.55))
                }

                Button {
                    appState.skipToPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                Button {
                    appState.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(appState.accentSwiftUIColor)
                            .frame(width: 60, height: 60)
                            .shadow(color: appState.accentSwiftUIColor.opacity(0.45), radius: 14, x: 0, y: 6)

                        Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                            .offset(x: appState.isPlaying ? 0 : 2)
                    }
                }

                Button {
                    appState.skipToNext(isManualUserAction: true)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                Button {
                    appState.cycleRepeatMode()
                } label: {
                    Image(systemName: appState.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(appState.repeatMode != .none ? appState.accentSwiftUIColor : .white.opacity(0.55))
                }
            }
        }
    }
}
