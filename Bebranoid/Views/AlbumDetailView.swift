import SwiftUI
import PhotosUI

/// Детальный экран альбома (`src/views/Albums.jsx`) с поддержкой:
/// - Воспроизведения и шаффла альбома
/// - Смены пользовательской обложки через системный `PhotosPicker`
/// - Скрытия альбома и исключения из общего шаффла
/// - Ручной перестановки треков (`onMove` -> `albumTrackOrders`)
public struct AlbumDetailView: View {
    public let album: Album
    @ObservedObject var appState: BebranoidAppState
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    public init(album: Album, appState: BebranoidAppState) {
        self.album = album
        self.appState = appState
    }

    private var liveAlbum: Album {
        appState.computedAlbums.first(where: { $0.name == album.name }) ?? album
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()

            List {
                Section {
                    headerHeroView
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                }

                Section {
                    ForEach(liveAlbum.tracks) { track in
                        TrackRowView(
                            track: track,
                            appState: appState,
                            contextQueue: liveAlbum.tracks
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onMove(perform: moveTracks)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(liveAlbum.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                EditButton()
                    .foregroundStyle(.white)
            }
            #endif
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let savedPath = try? appState.storage.saveCustomCover(imageData: data, identifier: liveAlbum.name) {
                    appState.libraryState.customAlbumCovers[liveAlbum.name] = savedPath
                    appState.saveLibraryState()
                }
            }
        }
    }

    private var headerHeroView: some View {
        VStack(spacing: 14) {
            ArtworkThumbnailView(
                localPath: liveAlbum.coverPath,
                remoteURL: liveAlbum.remoteArtworkURL,
                fallbackSeed: "\(liveAlbum.name)|\(liveAlbum.artist)",
                cornerRadius: 22,
                showFavoriteOverlay: liveAlbum.isFavoriteVirtualAlbum && liveAlbum.coverPath == nil
            )
            .frame(width: 190, height: 190)
            .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 10)

            VStack(spacing: 4) {
                Text(liveAlbum.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("\(liveAlbum.artist) • \(liveAlbum.tracks.count) треков")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack(spacing: 12) {
                Button {
                    if let first = liveAlbum.tracks.first {
                        appState.isShuffleEnabled = false
                        appState.playTrack(first, in: liveAlbum.tracks)
                    }
                } label: {
                    Label("Слушать", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(appState.accentSwiftUIColor, in: Capsule())
                }

                Button {
                    guard !liveAlbum.tracks.isEmpty else { return }
                    let rand = liveAlbum.tracks.randomElement()!
                    appState.isShuffleEnabled = true
                    appState.playTrack(rand, in: liveAlbum.tracks)
                } label: {
                    Label("Перемешать", systemImage: "shuffle")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func moveTracks(from source: IndexSet, to destination: Int) {
        var currentOrder = liveAlbum.tracks.map { $0.cacheKey }
        currentOrder.move(fromOffsets: source, toOffset: destination)
        appState.libraryState.albumTrackOrders[liveAlbum.name] = currentOrder
        appState.saveLibraryState()
    }
}
