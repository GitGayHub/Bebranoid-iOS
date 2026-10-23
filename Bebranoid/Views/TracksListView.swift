import SwiftUI

/// Экран всех треков медиатеки (`src/views/Tracks.jsx`).
/// Включает:
/// - Поиск по названию, исполнителю, альбому и имени файла
/// - Фильтр «В кеше» (показывает только офлайн-готовые треки)
/// - Модальное окно «Сверка» с расчётом процента закешированности каждого альбома и пакетной докачкой
/// - Сортировку по 6 критериям (`recent`, `title`, `artist`, `album`, `year`, `plays`) и направлению
/// - Кнопку честного шаффла всей медиатеки
public struct TracksListView: View {
    @ObservedObject var appState: BebranoidAppState
    @State private var isReconcileSheetPresented: Bool = false

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.28).ignoresSafeArea()

                VStack(spacing: 12) {
                    filterAndActionHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    let tracks = appState.filteredAndSortedTracks
                    if tracks.isEmpty {
                        emptyTracksState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(tracks) { track in
                                    TrackRowView(
                                        track: track,
                                        appState: appState,
                                        contextQueue: tracks
                                    )
                                }
                                Spacer().frame(height: 110)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .navigationTitle("Треки (\(appState.filteredAndSortedTracks.count))")
            .searchable(text: $appState.searchQuery, prompt: "Поиск треков, артистов, альбомов")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Сортировка", selection: $appState.trackSortField) {
                            ForEach(TrackSortField.allCases, id: \.self) { field in
                                Text(field.displayName).tag(field)
                            }
                        }
                        Divider()
                        Button {
                            appState.trackSortAscending.toggle()
                        } label: {
                            Label(
                                appState.trackSortAscending ? "По возрастанию (А–Я)" : "По убыванию (Я–А / Новые)",
                                systemImage: appState.trackSortAscending ? "arrow.up" : "arrow.down"
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $isReconcileSheetPresented) {
                AlbumCacheReconcileSheet(appState: appState)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var filterAndActionHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    appState.shuffleAllEligibleLibrary()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                        Text("Перемешать всё")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(appState.accentSwiftUIColor, in: Capsule())
                }

                // Фильтр «В кеше»
                Button {
                    appState.haptics.softSelection()
                    appState.showOnlyCachedTracks.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: appState.showOnlyCachedTracks ? "checkmark.icloud.fill" : "icloud.and.arrow.down")
                        Text("В кеше")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(appState.showOnlyCachedTracks ? appState.accentSwiftUIColor : .white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(appState.showOnlyCachedTracks ? 0.18 : 0.10), in: Capsule())
                }

                // Кнопка «Сверка» (только когда активен фильтр «В кеше» или всегда для удобства проверки)
                Button {
                    appState.haptics.lightTap()
                    isReconcileSheetPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.pie.fill")
                        Text("Сверка кеша")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.10), in: Capsule())
                }
            }
        }
    }

    private var emptyTracksState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 46))
                .foregroundStyle(.white.opacity(0.35))
            Text(appState.showOnlyCachedTracks ? "Нет треков в локальном кеше" : "Медиатека пуста")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text("Авторизуйтесь в Telegram, импортируйте плейлист YouTube или добавьте локальные файлы во вкладке «Настройки».")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
    }
}

public struct TrackRowView: View {
    public let track: Track
    @ObservedObject var appState: BebranoidAppState
    public let contextQueue: [Track]

    public var body: some View {
        let isCurrent = appState.currentTrack?.id == track.id
        let isCached = appState.cacheIndex.isCached(track)
        let isLiked = appState.isFavorite(track)

        Button {
            appState.playTrack(track, in: contextQueue)
        } label: {
            HStack(spacing: 12) {
                ArtworkThumbnailView(
                    localPath: appState.libraryState.customAlbumCovers[track.album] ?? track.coverPath,
                    remoteURL: track.remoteArtworkURL,
                    fallbackSeed: "\(track.album)|\(track.artist)",
                    cornerRadius: 10
                )
                .frame(width: 48, height: 48)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(appState.accentSwiftUIColor, lineWidth: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 15, weight: isCurrent ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(isCurrent ? appState.accentSwiftUIColor : .white)
                            .lineLimit(1)

                        if isCached {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.50))
                        }

                        if track.isFromArchive {
                            Text("Архив")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }

                    Text("\(track.artist) • \(track.album)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if appState.playCount(for: track) > 0 {
                    Text("\(appState.playCount(for: track))×")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }

                if isLiked {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 1.0, green: 0.34, blue: 0.52))
                }

                Text(FullScreenPlayerView.formatSeconds(track.duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .padding(10)
            .background(
                Color.white.opacity(isCurrent ? 0.14 : 0.06),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                appState.toggleFavorite(track: track)
            } label: {
                Label(isLiked ? "Убрать из Любимых" : "В Любимые", systemImage: isLiked ? "heart.slash" : "heart.fill")
            }

            Button {
                appState.inspectedTrackForInfo = track
            } label: {
                Label("Сведения о файле", systemImage: "info.circle")
            }

            Menu("Добавить в плейлист") {
                ForEach(appState.libraryState.playlists.filter { !$0.isRecentAutoPlaylist }) { pl in
                    Button(pl.name) {
                        appState.addTrack(track, toPlaylistId: pl.id)
                    }
                }
            }

            Button {
                appState.toggleLyricsDisabled(for: track)
            } label: {
                Label(
                    appState.isLyricsDisabled(for: track) ? "Включить текст песни" : "Отключить текст песни",
                    systemImage: appState.isLyricsDisabled(for: track) ? "eye" : "eye.slash"
                )
            }
        }
    }
}

/// Модальное окно «Сверка» кеша по альбомам (`src/views/Tracks.jsx` `showReconcileModal`)
private struct AlbumCacheReconcileSheet: View {
    @ObservedObject var appState: BebranoidAppState
    @Environment(\.dismiss) private var dismiss
    @State private var isBatchDownloading: Bool = false

    var body: some View {
        let report = appState.cacheIndex.buildReconcileReport(tracks: appState.libraryState.tracks)
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()

                List {
                    ForEach(report) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.albumName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("В кеше: \(item.cachedTracks) из \(item.totalTracks) (\(item.completionPercentage)%)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.68))
                            }

                            Spacer()

                            if item.isFullyCached {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Button("Докачать (\(item.missingTracks.count))") {
                                    downloadMissing(item.missingTracks)
                                }
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(appState.accentSwiftUIColor, in: Capsule())
                                .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Сверка кеша по альбомам")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func downloadMissing(_ tracks: [Track]) {
        guard !isBatchDownloading else { return }
        isBatchDownloading = true
        Task {
            for track in tracks {
                _ = try? await appState.telegramClient.ensureTrackDownloaded(track: track, priority: .backgroundBatch)
            }
            isBatchDownloading = false
        }
    }
}
