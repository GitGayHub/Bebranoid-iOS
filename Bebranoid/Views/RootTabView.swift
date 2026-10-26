import SwiftUI

/// Корневой контейнер навигации iPhone с нативным `TabView` (Треки, Альбомы, Артисты, Плейлисты, Настройки),
/// общим фоном `HarmonoidMeshView` и плавающим мини-плеером над таб-баром.
public struct RootTabView: View {
    @ObservedObject var appState: BebranoidAppState

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
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

            TabView(selection: $appState.selectedTab) {
                TracksListView(appState: appState)
                    .tabItem {
                        Label("Треки", systemImage: "music.note.list")
                    }
                    .tag(0)

                AlbumsGridView(appState: appState)
                    .tabItem {
                        Label("Альбомы", systemImage: "square.stack.fill")
                    }
                    .tag(1)

                ArtistsGridView(appState: appState)
                    .tabItem {
                        Label("Артисты", systemImage: "music.mic")
                    }
                    .tag(2)

                PlaylistsGridView(appState: appState)
                    .tabItem {
                        Label("Плейлисты", systemImage: "music.note.house.fill")
                    }
                    .tag(3)

                SettingsView(appState: appState)
                    .tabItem {
                        Label("Настройки", systemImage: "gearshape.fill")
                    }
                    .tag(4)
            }
            .tint(appState.accentSwiftUIColor)

            if appState.currentTrack != nil {
                MiniPlayerCardView(appState: appState)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            #if DEBUG
            if let overrideScreen = appState.demoDirectScreenOverride {
                switch overrideScreen {
                case "library":
                    LibraryCloudOverviewScreen(appState: appState)
                        .transition(.opacity)
                case "mini-player":
                    MiniPlayerExpandedDockScreen(appState: appState)
                        .transition(.opacity)
                case "player":
                    FullScreenPlayerView(appState: appState)
                        .transition(.opacity)
                case "lyrics":
                    LyricsScreenView(appState: appState)
                        .transition(.opacity)
                case "queue":
                    QueueSheetView(appState: appState)
                        .background(Color.black.opacity(0.92).ignoresSafeArea())
                        .transition(.opacity)
                case "diagnostics":
                    NavigationStack {
                        DiagnosticsView(appState: appState)
                    }
                    .transition(.opacity)
                default:
                    EmptyView()
                }
            }
            #endif
        }
        .fullScreenCover(isPresented: $appState.isFullScreenPlayerPresented) {
            FullScreenPlayerView(appState: appState)
        }
    }
}

#if DEBUG
/// Витрина медиатеки и облака Telegram/YouTube (`--screen=library`, `01-library.png`),
/// визуально демонстрирующая подключённые облачные источники, крупные реальные обложки альбомов и недавние релизы.
private struct LibraryCloudOverviewScreen: View {
    @ObservedObject var appState: BebranoidAppState

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                ZStack {
                    Color.black.opacity(0.26).ignoresSafeArea()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            // 1. Статус облачной медиатеки Telegram + Архив + YouTube
                            HStack(spacing: 12) {
                                Image(systemName: "icloud.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(appState.accentSwiftUIColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appState.libraryState.selectedTelegramChatTitle)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("Архив: \(appState.libraryState.selectedTelegramArchiveChatTitle) • Lossless 24-bit/96kHz")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.68))
                                }
                                Spacer()
                                Text("\(appState.libraryState.tracks.count) треков")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(appState.accentSwiftUIColor.opacity(0.22), in: Capsule())
                                    .foregroundStyle(appState.accentSwiftUIColor)
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 16)

                            // 2. Витрина избранных альбомов с реальными обложками
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Альбомы и релизы медиатеки")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(appState.computedAlbums) { album in
                                            VStack(alignment: .leading, spacing: 6) {
                                                ArtworkThumbnailView(
                                                    track: album.representativeTrack,
                                                    localPath: album.preferredCoverPath,
                                                    remoteURL: album.preferredRemoteArtworkURL,
                                                    fallbackSeed: "\(album.name)|\(album.artist)",
                                                    cornerRadius: 16,
                                                    sizeTier: .grid384
                                                )
                                                .frame(width: 132, height: 132)

                                                Text(album.name)
                                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                    .frame(width: 132, alignment: .leading)

                                                Text(album.artist)
                                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.65))
                                                    .lineLimit(1)
                                                    .frame(width: 132, alignment: .leading)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }

                            // 3. Недавно добавленные треки
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Недавно добавленные в облако")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)

                                VStack(spacing: 8) {
                                    ForEach(appState.libraryState.tracks.prefix(4)) { track in
                                        TrackRowView(
                                            track: track,
                                            appState: appState,
                                            contextQueue: appState.libraryState.tracks
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            Spacer().frame(height: 120)
                        }
                        .padding(.top, 8)
                    }
                }
                .navigationTitle("Медиатека")
            }

            if appState.currentTrack != nil {
                MiniPlayerCardView(appState: appState)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 56)
            }
        }
    }
}

/// Экран фокуса на интерактивном мини-плеере, быстрых фильтрах Audio FX и очереди (`--screen=mini-player`, `10-mini-player.png`).
private struct MiniPlayerExpandedDockScreen: View {
    @ObservedObject var appState: BebranoidAppState

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.32).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Сейчас играет и Audio FX")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Crossfade \(String(format: "%.0fs", appState.crossfadeDuration))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(appState.accentSwiftUIColor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Далее в очереди
                Text("Далее в очереди воспроизведения")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    ForEach(appState.queue.dropFirst(2)) { track in
                        TrackRowView(track: track, appState: appState, contextQueue: appState.queue)
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                // Расширенный стеклянный док мини-плеера с реальной обложкой и быстрыми пресетами Audio FX
                if let track = appState.currentTrack {
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            ArtworkThumbnailView(
                                track: track,
                                localPath: appState.libraryState.customAlbumCovers[track.album] ?? track.coverPath,
                                remoteURL: track.remoteArtworkURL,
                                fallbackSeed: "\(track.album)|\(track.artist)",
                                cornerRadius: 16,
                                sizeTier: .grid384
                            )
                            .frame(width: 76, height: 76)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("LOSSLESS FLAC")
                                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(appState.accentSwiftUIColor.opacity(0.24), in: Capsule())
                                        .foregroundStyle(appState.accentSwiftUIColor)

                                    Text(appState.audioFXMode.displayName)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.14), in: Capsule())
                                        .foregroundStyle(.white)
                                }

                                Text(track.title)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text("\(track.artist) — \(track.album)")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }

                        // Быстрые переключатели DSP (Normal / Slowed / Slowed+Reverb / Nightcore / Bass Boost)
                        HStack(spacing: 8) {
                            ForEach(AudioFXMode.allCases, id: \.self) { mode in
                                let active = appState.audioFXMode == mode
                                Text(mode.displayName)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(active ? appState.accentSwiftUIColor : Color.white.opacity(0.10), in: Capsule())
                                    .foregroundStyle(active ? Color(red: 0.06, green: 0.08, blue: 0.12) : .white)
                            }
                        }

                        MiniPlayerCardView(appState: appState)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 58)
                }
            }
        }
    }
}
#endif
