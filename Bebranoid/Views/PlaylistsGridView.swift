import SwiftUI

/// Экран плейлистов (`src/views/PlaylistsView.jsx` и `docs/youtube-playlists.md`).
/// Включает:
/// - Авто-плейлист «Последние 30» (`__recent_30__`)
/// - Пользовательские плейлисты
/// - Плейлисты YouTube с настройкой лимита случайного выбора (по умолчанию 15, кнопки `-10` / `+10` / `Сброс`),
///   индивидуальными галочками включения/исключения треков и кнопкой повторной сверки (`reconcilePlaylist`)
public struct PlaylistsGridView: View {
    @ObservedObject var appState: BebranoidAppState
    @State private var isYouTubeImportPresented: Bool = false
    @State private var isNewPlaylistAlertPresented: Bool = false
    @State private var newPlaylistName: String = ""

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
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Button {
                                isNewPlaylistAlertPresented = true
                            } label: {
                                Label("Новый плейлист", systemImage: "plus.circle.fill")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }

                            Button {
                                isYouTubeImportPresented = true
                            } label: {
                                Label("Импорт YouTube", systemImage: "play.rectangle.fill")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(appState.accentSwiftUIColor, in: Capsule())
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(appState.allPlaylistsWithRecent30) { playlist in
                                NavigationLink(value: playlist) {
                                    PlaylistGridCard(playlist: playlist, appState: appState)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    Spacer().frame(height: 110)
                }
            }
            .navigationTitle("Плейлисты")
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist, appState: appState)
            }
            .sheet(isPresented: $isYouTubeImportPresented) {
                YouTubeImportSheet(appState: appState)
            }
            .alert("Создать плейлист", isPresented: $isNewPlaylistAlertPresented) {
                TextField("Название плейлиста", text: $newPlaylistName)
                Button("Отмена", role: .cancel) { newPlaylistName = "" }
                Button("Создать") {
                    appState.createCustomPlaylist(name: newPlaylistName)
                    newPlaylistName = ""
                }
            }
        }
    }
}

private struct PlaylistGridCard: View {
    let playlist: Playlist
    let appState: BebranoidAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ArtworkThumbnailView(
                    track: playlist.tracksSnapshot.first,
                    localPath: playlist.customCoverPath ?? playlist.tracksSnapshot.first?.coverPath,
                    remoteURL: playlist.remoteArtworkURL ?? playlist.tracksSnapshot.first?.remoteArtworkURL,
                    fallbackSeed: playlist.name,
                    cornerRadius: 18,
                    sizeTier: .albumGrid
                )
                .aspectRatio(1.0, contentMode: .fit)

                if playlist.isYouTubePlaylist {
                    Text("YouTube")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.88), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                } else if playlist.isRecentAutoPlaylist {
                    Text("Авто")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appState.accentSwiftUIColor, in: Capsule())
                        .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                        .padding(8)
                }
            }

            Text(playlist.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("\(playlist.tracksSnapshot.count) треков")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .contextMenu {
            if !playlist.isRecentAutoPlaylist {
                Button(role: .destructive) {
                    appState.deletePlaylist(id: playlist.id)
                } label: {
                    Label("Удалить плейлист", systemImage: "trash")
                }
            }
        }
    }
}

public struct PlaylistDetailView: View {
    public let playlist: Playlist
    @ObservedObject var appState: BebranoidAppState
    @State private var isSyncingYouTube: Bool = false
    @State private var isCacheSelectionMode: Bool = false
    @State private var selectedCacheTrackIds: Set<String> = []

    public init(playlist: Playlist, appState: BebranoidAppState) {
        self.playlist = playlist
        self.appState = appState
    }

    private var livePlaylist: Playlist {
        appState.allPlaylistsWithRecent30.first(where: { $0.id == playlist.id }) ?? playlist
    }

    private var currentPreference: PlaylistShufflePreference {
        appState.libraryState.playlistShufflePreferences[livePlaylist.id] ?? PlaylistShufflePreference()
    }

    public var body: some View {
        let playlistTracks = livePlaylist.tracksSnapshot
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Блок управления YouTube-плейлистом (`playlistPreferences.js`: лимит 15, кнопки -10 / +10 / Сброс, Сверка)
                    if livePlaylist.isYouTubePlaylist {
                        youtubeShufflePreferencesCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            Button {
                                if let first = playlistTracks.first {
                                    appState.isShuffleEnabled = false
                                    appState.playTrack(first, in: playlistTracks)
                                }
                            } label: {
                                Label("Слушать", systemImage: "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 11)
                                    .background(appState.accentSwiftUIColor, in: Capsule())
                            }

                            Button {
                                let eligible = livePlaylist.isYouTubePlaylist
                                    ? PlaylistPreferencesEngine.eligiblePlaylistTracks(tracks: playlistTracks, preference: currentPreference)
                                    : playlistTracks
                                guard let rand = eligible.randomElement() else { return }
                                appState.isShuffleEnabled = true
                                appState.playTrack(rand, in: eligible)
                            } label: {
                                Label("Шаффл избранных", systemImage: "shuffle")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 11)
                                    .background(Color.white.opacity(0.14), in: Capsule())
                            }

                            if !playlistTracks.isEmpty {
                                Button {
                                    appState.haptics.softSelection()
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        isCacheSelectionMode.toggle()
                                        if !isCacheSelectionMode {
                                            selectedCacheTrackIds.removeAll()
                                        }
                                    }
                                } label: {
                                    Label(
                                        isCacheSelectionMode ? "Отменить выбор" : "Выбрать в кэш",
                                        systemImage: isCacheSelectionMode ? "checkmark.circle.fill" : "arrow.down.to.line.circle"
                                    )
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(isCacheSelectionMode ? Color(red: 0.08, green: 0.06, blue: 0.14) : .white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 11)
                                    .background(
                                        isCacheSelectionMode ? appState.accentSwiftUIColor : Color.white.opacity(0.14),
                                        in: Capsule()
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if isCacheSelectionMode {
                        let selected = playlistTracks.filter { selectedCacheTrackIds.contains($0.id) }
                        let missingCount = selected.filter { !appState.cacheIndex.isCached($0) }.count
                        let allSelected = !playlistTracks.isEmpty && selectedCacheTrackIds.count >= playlistTracks.count
                        HStack(spacing: 10) {
                            Button {
                                if allSelected {
                                    selectedCacheTrackIds.removeAll()
                                } else {
                                    selectedCacheTrackIds = Set(playlistTracks.map(\.id))
                                }
                            } label: {
                                Text(allSelected ? "Снять всё" : "Выбрать все")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                appState.downloadTracksToCache(selected)
                                isCacheSelectionMode = false
                                selectedCacheTrackIds.removeAll()
                            } label: {
                                Label(
                                    missingCount > 0 ? "Скачать в кэш (\(missingCount))" : "Выберите треки",
                                    systemImage: "arrow.down.to.line.circle.fill"
                                )
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    missingCount > 0 ? appState.accentSwiftUIColor : appState.accentSwiftUIColor.opacity(0.45),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(missingCount == 0)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }

                    LazyVStack(spacing: 8) {
                        ForEach(Array(playlistTracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 8) {
                                if !isCacheSelectionMode && livePlaylist.isYouTubePlaylist {
                                    let isEligible = isTrackEligible(track: track, index: index)
                                    Button {
                                        toggleTrackShuffleOverride(track: track, index: index)
                                    } label: {
                                        Image(systemName: isEligible ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(isEligible ? appState.accentSwiftUIColor : .white.opacity(0.35))
                                    }
                                    .buttonStyle(.plain)
                                }

                                TrackRowView(
                                    track: track,
                                    appState: appState,
                                    contextQueue: playlistTracks,
                                    isSelectionMode: isCacheSelectionMode,
                                    isSelected: selectedCacheTrackIds.contains(track.id),
                                    onToggleSelection: {
                                        if selectedCacheTrackIds.contains(track.id) {
                                            selectedCacheTrackIds.remove(track.id)
                                        } else {
                                            selectedCacheTrackIds.insert(track.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 110)
                }
            }
        }
        .navigationTitle(livePlaylist.name)
    }

    private var youtubeShufflePreferencesCard: some View {
        let pref = currentPreference
        let eligibleCount = PlaylistPreferencesEngine.eligiblePlaylistTracks(
            tracks: livePlaylist.tracksSnapshot,
            preference: pref
        ).count

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Лимит треков для общего шаффла: \(pref.limit)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Активно в пуле: \(eligibleCount) из \(livePlaylist.tracksSnapshot.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                if let sourceUrl = livePlaylist.sourceUrl {
                    Button {
                        Task {
                            isSyncingYouTube = true
                            try? await appState.importYouTubeURL(sourceUrl, customTitle: livePlaylist.name)
                            isSyncingYouTube = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isSyncingYouTube {
                                ProgressView().scaleEffect(0.7).tint(.white)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Сверка")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.white)
                    }
                }
            }

            HStack(spacing: 10) {
                Button("-10") {
                    updatePreference { $0.adjustLimit(by: -10) }
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.white)

                Button("+10") {
                    updatePreference { $0.adjustLimit(by: 10) }
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.white)

                Button("По умолч. (15)") {
                    updatePreference {
                        $0.limit = PlaylistShufflePreference.defaultLimit
                        $0.include.removeAll()
                        $0.exclude.removeAll()
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(.white.opacity(0.80))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func isTrackEligible(track: Track, index: Int) -> Bool {
        let pref = currentPreference
        let key = track.cacheKey
        if pref.exclude.contains(key) { return false }
        return pref.include.contains(key) || index < pref.limit
    }

    private func toggleTrackShuffleOverride(track: Track, index: Int) {
        let key = track.cacheKey
        let currentlyEligible = isTrackEligible(track: track, index: index)
        updatePreference { pref in
            if currentlyEligible {
                pref.toggleExclude(filename: key)
            } else {
                pref.toggleInclude(filename: key)
            }
        }
    }

    private func updatePreference(_ mutate: (inout PlaylistShufflePreference) -> Void) {
        var pref = currentPreference
        mutate(&pref)
        appState.libraryState.playlistShufflePreferences[livePlaylist.id] = pref
        appState.saveLibraryState()
    }
}
