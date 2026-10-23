import SwiftUI

/// Сетка альбомов (`src/views/Albums.jsx`).
/// Включает:
/// - Виртуальный альбом «Любимые» всегда первым
/// - Переключатель показа скрытых альбомов с бейджем `Скрыт`
/// - Бейдж исключения альбома из общего шаффла медиатеки
/// - Контекстное меню скрытия, исключения из шаффла и перехода к трекам
public struct AlbumsGridView: View {
    @ObservedObject var appState: BebranoidAppState

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.28).ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(appState.computedAlbums) { album in
                            NavigationLink(value: album) {
                                AlbumGridCard(album: album, appState: appState)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    Spacer().frame(height: 110)
                }
            }
            .navigationTitle("Альбомы (\(appState.computedAlbums.count))")
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album, appState: appState)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.haptics.softSelection()
                        appState.showHiddenAlbums.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: appState.showHiddenAlbums ? "eye.fill" : "eye.slash")
                            Text("Скрытые")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(appState.showHiddenAlbums ? appState.accentSwiftUIColor : .white.opacity(0.82))
                    }
                }
            }
        }
    }
}

private struct AlbumGridCard: View {
    let album: Album
    @ObservedObject var appState: BebranoidAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ArtworkThumbnailView(
                    localPath: album.coverPath,
                    remoteURL: album.remoteArtworkURL,
                    fallbackSeed: "\(album.name)|\(album.artist)",
                    cornerRadius: 18,
                    showFavoriteOverlay: album.isFavoriteVirtualAlbum && album.coverPath == nil
                )
                .aspectRatio(1.0, contentMode: .fit)
                .shadow(color: .black.opacity(0.32), radius: 10, x: 0, y: 5)

                HStack(spacing: 4) {
                    if album.isHidden {
                        Text("Скрыт")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    if album.isExcludedFromShuffle {
                        Image(systemName: "shuffle.slash")
                            .font(.system(size: 11, weight: .bold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(.orange)
                    }
                }
                .padding(8)
            }

            Text(album.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("\(album.artist) • \(album.tracks.count) тр.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
        }
        .contextMenu {
            if !album.isFavoriteVirtualAlbum {
                Button {
                    appState.toggleAlbumHidden(album.name)
                } label: {
                    Label(
                        album.isHidden ? "Показать альбом" : "Скрыть альбом",
                        systemImage: album.isHidden ? "eye" : "eye.slash"
                    )
                }

                Button {
                    appState.toggleAlbumExcludedFromShuffle(album.name)
                } label: {
                    Label(
                        album.isExcludedFromShuffle ? "Вернуть в общий шаффл" : "Исключить из общего шаффла",
                        systemImage: "shuffle"
                    )
                }
            }
        }
    }
}
