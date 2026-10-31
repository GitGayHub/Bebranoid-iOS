import SwiftUI

/// Экран всех треков медиатеки (`src/views/Tracks.jsx`).
/// Включает:
/// - Поиск по названию, исполнителю, альбому и имени файла
/// - Фильтр «Скачанные» (показывает офлайн-готовые треки на устройстве)
/// - Выпадающее меню «Сортировка по» 1:1 с настольной версией (`Недавно добавленные`, `От А до Я (Название)`, `Исполнители`, `Альбом`, `Год`, `Часто воспроизводимые` + направление)
/// - Лаконичные круглые стеклянные кнопки обновления (`arrow.clockwise`) и пакетного выбора (`checklist`) без лишнего текста
/// - Кнопку честного шаффла всей медиатеки
public struct TracksListView: View {
    @ObservedObject var appState: BebranoidAppState
    @State private var isSelectionMode: Bool = false
    @State private var selectedTrackIds: Set<String> = []

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        let tracks = appState.filteredAndSortedTracks
        NavigationStack {
            ZStack {
                Color.black.opacity(0.28).ignoresSafeArea()

                VStack(spacing: 10) {
                    filterAndActionHeader(tracks: tracks)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    if isSelectionMode {
                        multiSelectActionBar(tracks: tracks)
                            .padding(.horizontal, 16)
                    }

                    if appState.isBatchDownloadingSelected {
                        batchDownloadProgressCard
                            .padding(.horizontal, 16)
                    }

                    if appState.isSyncingTelegramLibrary {
                        telegramLiveSyncBanner
                            .padding(.horizontal, 16)
                    }

                    if !appState.telegramClient.isAuthorized {
                        telegramSignInPromptCard
                            .padding(.horizontal, 16)
                    }

                    if tracks.isEmpty {
                        emptyTracksState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(tracks) { track in
                                    TrackRowView(
                                        track: track,
                                        appState: appState,
                                        contextQueue: tracks,
                                        isSelectionMode: isSelectionMode,
                                        isSelected: selectedTrackIds.contains(track.id),
                                        onToggleSelection: {
                                            toggleTrackSelection(track.id)
                                        }
                                    )
                                }
                                Spacer().frame(height: 118)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .navigationTitle("Треки (\(tracks.count))")
            .searchable(text: $appState.searchQuery, prompt: "Поиск треков, артистов, альбомов")
        }
    }

    private func toggleTrackSelection(_ id: String) {
        appState.haptics.lightTap()
        if selectedTrackIds.contains(id) {
            selectedTrackIds.remove(id)
        } else {
            selectedTrackIds.insert(id)
        }
    }

    private func filterAndActionHeader(tracks: [Track]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                // 1. Перемешать всё
                Button {
                    appState.shuffleAllEligibleLibrary()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 13, weight: .bold))
                        Text("Перемешать")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .liquidGlassCapsule(tint: appState.accentSwiftUIColor, isProminent: true)
                }
                .buttonStyle(.plain)

                // 2. Фильтр «Скачанные» (переименован из «В кеше»)
                Button {
                    appState.haptics.softSelection()
                    appState.showOnlyCachedTracks.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: appState.showOnlyCachedTracks ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Скачанные")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(
                        appState.showOnlyCachedTracks
                            ? Color(red: 0.08, green: 0.06, blue: 0.14)
                            : .white.opacity(0.92)
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .liquidGlassCapsule(
                        tint: appState.accentSwiftUIColor,
                        isProminent: appState.showOnlyCachedTracks
                    )
                }
                .buttonStyle(.plain)

                // 3. Меню сортировки 1:1 с настольной версией (`Tracks.jsx`)
                Menu {
                    Section("Сортировка по") {
                        ForEach(TrackSortField.allCases, id: \.self) { field in
                            Button {
                                appState.haptics.softSelection()
                                if appState.trackSortField == field {
                                    appState.trackSortAscending.toggle()
                                } else {
                                    appState.trackSortField = field
                                    // По умолчанию как на ПК: А–Я / Артист / Альбом по возрастанию, Новые / Год / Прослушивания по убыванию
                                    switch field {
                                    case .title, .artist, .album:
                                        appState.trackSortAscending = true
                                    case .recent, .year, .plays:
                                        appState.trackSortAscending = false
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(field.displayName)
                                    if appState.trackSortField == field {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Section("Порядок") {
                        Button {
                            appState.haptics.softSelection()
                            appState.trackSortAscending = false
                        } label: {
                            Label(
                                "По убыванию",
                                systemImage: !appState.trackSortAscending ? "checkmark.circle.fill" : "arrow.down"
                            )
                        }

                        Button {
                            appState.haptics.softSelection()
                            appState.trackSortAscending = true
                        } label: {
                            Label(
                                "По возрастанию",
                                systemImage: appState.trackSortAscending ? "checkmark.circle.fill" : "arrow.up"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: appState.trackSortAscending ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(appState.accentSwiftUIColor)
                        Text(appState.trackSortField.shortLabel)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .liquidGlassCapsule(tint: .white, isProminent: false)
                }

                // 4. Круглая иконка пакетного выбора треков (без лишнего текста «Выбрать»)
                if !tracks.isEmpty || isSelectionMode {
                    Button {
                        appState.haptics.softSelection()
                        withAnimation(.easeOut(duration: 0.18)) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedTrackIds.removeAll()
                            }
                        }
                    } label: {
                        Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "checklist")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(
                                isSelectionMode
                                    ? Color(red: 0.08, green: 0.06, blue: 0.14)
                                    : .white.opacity(0.92)
                            )
                            .frame(width: 37, height: 37)
                            .liquidGlassCircle(tint: appState.accentSwiftUIColor, isHighlighted: isSelectionMode)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSelectionMode ? "Отменить выбор треков" : "Выбрать треки")
                }

                // 5. Круглая иконка обновления облачной медиатеки (без текста «Обновить TG»)
                if appState.telegramClient.isAuthorized {
                    Button {
                        appState.haptics.lightTap()
                        Task { await appState.syncTelegramLibrary() }
                    } label: {
                        Group {
                            if appState.isSyncingTelegramLibrary {
                                ProgressView()
                                    .tint(appState.accentSwiftUIColor)
                                    .scaleEffect(0.76)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                        .frame(width: 37, height: 37)
                        .liquidGlassCircle(tint: appState.accentSwiftUIColor, isHighlighted: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isSyncingTelegramLibrary)
                    .accessibilityLabel("Обновить медиатеку")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func multiSelectActionBar(tracks: [Track]) -> some View {
        let selectedTracks = tracks.filter { selectedTrackIds.contains($0.id) }
        let uncachedSelectedCount = selectedTracks.filter { !appState.cacheIndex.isCached($0) }.count
        let allSelected = !tracks.isEmpty && selectedTrackIds.count >= tracks.count

        return HStack(spacing: 10) {
            Button {
                appState.haptics.softSelection()
                if allSelected {
                    selectedTrackIds.removeAll()
                } else {
                    selectedTrackIds = Set(tracks.map(\.id))
                }
            } label: {
                Text(allSelected ? "Снять всё" : "Выбрать все")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .liquidGlassCapsule(tint: .white, isProminent: false)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Button {
                appState.downloadTracksToCache(selectedTracks)
                withAnimation(.easeOut(duration: 0.18)) {
                    isSelectionMode = false
                    selectedTrackIds.removeAll()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line.circle.fill")
                    Text(uncachedSelectedCount > 0
                         ? "Скачать (\(uncachedSelectedCount))"
                         : (selectedTracks.isEmpty ? "Выберите треки" : "Уже скачаны"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlassCapsule(
                    tint: uncachedSelectedCount > 0 ? appState.accentSwiftUIColor : appState.accentSwiftUIColor.opacity(0.45),
                    isProminent: true
                )
            }
            .buttonStyle(.plain)
            .disabled(uncachedSelectedCount == 0)
        }
        .padding(11)
        .liquidGlassCard(cornerRadius: 18, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)
    }

    private var batchDownloadProgressCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(appState.accentSwiftUIColor)
                .scaleEffect(0.85)

            VStack(alignment: .leading, spacing: 2) {
                Text("Скачивание выбранных треков: \(appState.batchDownloadDoneCount) из \(appState.batchDownloadTotalCount)")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                ProgressView(
                    value: Double(appState.batchDownloadDoneCount),
                    total: Double(max(1, appState.batchDownloadTotalCount))
                )
                .tint(appState.accentSwiftUIColor)
            }

            Button("Стоп") {
                appState.cancelBatchDownload()
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.90))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassCapsule(tint: .white, isProminent: false)
            .buttonStyle(.plain)
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 18, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)
    }

    private var telegramSignInPromptCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color(red: 0.24, green: 0.68, blue: 1.0))

            VStack(alignment: .leading, spacing: 2) {
                Text("Облако Telegram не подключено")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(appState.hiddenCloudTracksCount > 0
                     ? "Войдите в Telegram, чтобы открыть ваши \(appState.hiddenCloudTracksCount) облачных треков"
                     : "Войдите по коду, чтобы загрузить музыку из облака Telegram")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 4)

            Button {
                appState.openTelegramAuthSheet()
            } label: {
                Text("Войти")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .liquidGlassCapsule(tint: appState.accentSwiftUIColor, isProminent: true)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 18, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)
    }

    private var telegramLiveSyncBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(appState.accentSwiftUIColor)
                .scaleEffect(0.85)

            VStack(alignment: .leading, spacing: 2) {
                Text("Синхронизация \(appState.libraryState.selectedTelegramChatTitle)")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(appState.telegramScanProgressText.isEmpty
                     ? "Загрузка аудиосообщений и документов из Telegram..."
                     : appState.telegramScanProgressText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 18, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)
    }

    private var emptyTracksState: some View {
        VStack(spacing: 14) {
            Spacer()
            if appState.isSyncingTelegramLibrary {
                ProgressView()
                    .tint(appState.accentSwiftUIColor)
                    .scaleEffect(1.3)
                Text("Загрузка медиатеки из \(appState.libraryState.selectedTelegramChatTitle)...")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.90))
                    .multilineTextAlignment(.center)
                Text(appState.telegramScanProgressText.isEmpty
                     ? "Подключение к чату AndroSend Облако и сканирование треков..."
                     : appState.telegramScanProgressText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.35))
                Text(appState.showOnlyCachedTracks ? "Нет скачанных треков" : "Медиатека готова к загрузке")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text(!appState.telegramClient.isAuthorized
                     ? "Войдите в Telegram по кнопке выше, чтобы отобразить и слушать вашу облачную медиатеку, или импортируйте плейлист YouTube."
                     : (appState.showOnlyCachedTracks
                        ? "Скачайте любые треки для прослушивания без сети."
                        : "Выбран чат «\(appState.libraryState.selectedTelegramChatTitle)». Нажмите кнопку ниже, чтобы подтянуть все ваши треки."))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                if appState.telegramClient.isAuthorized && !appState.showOnlyCachedTracks {
                    Button {
                        appState.haptics.mediumImpact()
                        Task { await appState.syncTelegramLibrary() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "icloud.and.arrow.down.fill")
                            Text("Загрузить треки из \(appState.libraryState.selectedTelegramChatTitle)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .liquidGlassCapsule(tint: appState.accentSwiftUIColor, isProminent: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            Spacer()
        }
    }
}

public struct TrackRowView: View {
    public let track: Track
    public let appState: BebranoidAppState
    public let contextQueue: [Track]
    public var isSelectionMode: Bool = false
    public var isSelected: Bool = false
    public var onToggleSelection: (() -> Void)? = nil

    public init(
        track: Track,
        appState: BebranoidAppState,
        contextQueue: [Track],
        isSelectionMode: Bool = false,
        isSelected: Bool = false,
        onToggleSelection: (() -> Void)? = nil
    ) {
        self.track = track
        self.appState = appState
        self.contextQueue = contextQueue
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.onToggleSelection = onToggleSelection
    }

    public var body: some View {
        let isCurrent = appState.currentTrack?.id == track.id
        let isPendingTarget = appState.pendingDownloadTrack?.id == track.id
        let downloadPct = appState.downloadProgress(for: track)
        let isCached = appState.cacheIndex.isCached(track)
        let isLiked = appState.isFavorite(track)

        Button {
            if isSelectionMode {
                onToggleSelection?()
            } else {
                appState.playTrack(track, in: contextQueue)
            }
        } label: {
            HStack(spacing: 12) {
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(isSelected ? appState.accentSwiftUIColor : .white.opacity(0.38))
                }

                ArtworkThumbnailView(
                    track: track,
                    localPath: appState.libraryState.customAlbumCovers[track.album] ?? track.coverPath,
                    remoteURL: track.remoteArtworkURL,
                    fallbackSeed: "\(track.album)|\(track.artist)",
                    cornerRadius: 10,
                    sizeTier: .listThumbnail
                )
                .frame(width: 48, height: 48)
                .overlay {
                    if isCurrent || isPendingTarget {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(appState.accentSwiftUIColor, lineWidth: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 15, weight: (isCurrent || isPendingTarget) ? .bold : .semibold, design: .rounded))
                            .foregroundStyle((isCurrent || isPendingTarget) ? appState.accentSwiftUIColor : .white)
                            .lineLimit(1)

                        if let pct = downloadPct {
                            Text("⏳ \(pct)%")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(appState.accentSwiftUIColor.opacity(0.24), in: Capsule())
                                .foregroundStyle(appState.accentSwiftUIColor)
                        } else if isCached {
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

                    if let pct = downloadPct {
                        Text("Скачивание: \(pct)% • \(track.artist)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(appState.accentSwiftUIColor)
                            .lineLimit(1)
                    } else {
                        Text("\(track.artist) • \(track.album)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.18 : (isCurrent ? 0.14 : 0.06)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(isCurrent ? 0.22 : 0.08), lineWidth: 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isCached {
                Button {
                    appState.downloadTracksToCache([track])
                } label: {
                    Label("Скачать трек", systemImage: "arrow.down.to.line.circle")
                }
            }

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
