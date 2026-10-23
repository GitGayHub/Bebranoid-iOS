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
