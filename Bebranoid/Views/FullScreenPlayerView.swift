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
                    isReducedMotion: appState.isReducedMotionEnabled,
                    fixedAnimationTime: fixedTime
                )

                VStack(spacing: 0) {
                    topHeaderBar
                        .padding(.top, 8)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    // Большая квадратная обложка альбома
                    let coverSide = min(geo.size.width - 48, geo.size.height * 0.43)
                    ArtworkThumbnailView(
                        track: track,
                        localPath: track.flatMap { appState.libraryState.customAlbumCovers[$0.album] ?? $0.coverPath },
                        remoteURL: track?.remoteArtworkURL,
                        fallbackSeed: "\(track?.album ?? "")|\(track?.artist ?? "")",
                        cornerRadius: 28,
                        sizeTier: .fullPlayer
                    )
                    .frame(width: coverSide, height: coverSide)
                    .scaleEffect(appState.isPlaying ? 1.0 : 0.93)
                    .shadow(color: Color.black.opacity(0.48), radius: 28, x: 0, y: 16)
                    .animation(.spring(response: 0.45, dampingFraction: 0.78), value: appState.isPlaying)
                    .animation(.easeInOut(duration: 0.35), value: track?.id)

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

    // MARK: - Subviews

    private var topHeaderBar: some View {
        HStack {
            Button {
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
        HStack(spacing: 10) {
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
        let maxDur = max(1.0, appState.duration)
        let clampedPos = min(maxDur, max(0.0, displayedTime))

        return VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { clampedPos },
                    set: { newVal in
                        isDraggingSlider = true
                        draggedTime = newVal
                    }
                ),
                in: 0...maxDur,
                onEditingChanged: { editing in
                    if !editing {
                        appState.seek(to: draggedTime)
                        isDraggingSlider = false
                    }
                }
            )
            .tint(appState.accentSwiftUIColor)

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

                Text(Self.formatSeconds(appState.duration))
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
