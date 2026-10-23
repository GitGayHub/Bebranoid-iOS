import SwiftUI

/// Сетка исполнителей (`src/views/Artists.jsx` + `src/lib/artists.js`).
/// Поддерживает:
/// - Разделение совместных треков (`feat.`, `ft.`, `,`, `&`, `/`, `x`, `и`)
/// - Закрепление любимых артистов (`favoriteArtists`) в верхней части списка
public struct ArtistsGridView: View {
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
                        ForEach(appState.computedArtists) { artist in
                            NavigationLink(value: artist) {
                                ArtistGridCard(artist: artist, appState: appState)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    Spacer().frame(height: 110)
                }
            }
            .navigationTitle("Артисты (\(appState.computedArtists.count))")
            .navigationDestination(for: ArtistSummary.self) { artist in
                ArtistDetailView(artist: artist, appState: appState)
            }
        }
    }
}

private struct ArtistGridCard: View {
    let artist: ArtistSummary
    @ObservedObject var appState: BebranoidAppState

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ArtworkThumbnailView(
                    localPath: artist.representativeCoverPath,
                    remoteURL: artist.representativeRemoteArtwork,
                    fallbackSeed: artist.displayName,
                    cornerRadius: 65
                )
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.32), radius: 10, x: 0, y: 5)

                if artist.isPinnedFavorite {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .bold))
                        .padding(6)
                        .background(appState.accentSwiftUIColor, in: Circle())
                        .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                }
            }

            Text(artist.displayName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("\(artist.tracks.count) треков • \(artist.albums.count) альб.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            Button {
                appState.toggleFavoriteArtist(artist.normalizedKey)
            } label: {
                Label(
                    artist.isPinnedFavorite ? "Открепить артиста" : "Закрепить в избранных",
                    systemImage: artist.isPinnedFavorite ? "pin.slash" : "pin.fill"
                )
            }
        }
    }
}

public struct ArtistDetailView: View {
    public let artist: ArtistSummary
    @ObservedObject var appState: BebranoidAppState

    public init(artist: ArtistSummary, appState: BebranoidAppState) {
        self.artist = artist
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        ArtworkThumbnailView(
                            localPath: artist.representativeCoverPath,
                            remoteURL: artist.representativeRemoteArtwork,
                            fallbackSeed: artist.displayName,
                            cornerRadius: 70
                        )
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())

                        Text(artist.displayName)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        HStack(spacing: 12) {
                            Button {
                                if let first = artist.tracks.first {
                                    appState.playTrack(first, in: artist.tracks)
                                }
                            } label: {
                                Label("Слушать все", systemImage: "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(appState.accentSwiftUIColor, in: Capsule())
                            }

                            Button {
                                appState.toggleFavoriteArtist(artist.normalizedKey)
                            } label: {
                                Label(artist.isPinnedFavorite ? "Закреплён" : "Закрепить", systemImage: "pin.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                    .padding(.top, 12)

                    LazyVStack(spacing: 8) {
                        ForEach(artist.tracks) { track in
                            TrackRowView(track: track, appState: appState, contextQueue: artist.tracks)
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 110)
                }
            }
        }
        .navigationTitle(artist.displayName)
    }
}
