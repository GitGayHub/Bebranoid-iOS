import SwiftUI

/// Компактная плавающая карточка очереди воспроизведения на 4 трека для полноэкранного плеера (`FullScreenPlayerView`):
/// - Располагается в верхней части над названием трека и подписью плейлиста/альбома, никогда их не загораживая
/// - Вмещает ровно 4 трека по высоте и сразу прокручивается пальцем вверх/вниз без раскрытия на весь экран
public struct CompactPlayerQueueOverlayView: View {
    @ObservedObject var appState: BebranoidAppState

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        let queue = appState.queue
        let currentIdx = appState.currentIndex

        VStack(spacing: 0) {
            // Компактная шапка очереди
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(appState.accentSwiftUIColor)
                    Text("Очередь • \(queue.count)")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    appState.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(appState.isShuffleEnabled ? appState.accentSwiftUIColor : .white.opacity(0.62))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(appState.isShuffleEnabled ? appState.accentSwiftUIColor.opacity(0.20) : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    appState.cycleRepeatMode()
                } label: {
                    Image(systemName: appState.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(appState.repeatMode != .none ? appState.accentSwiftUIColor : .white.opacity(0.62))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(appState.repeatMode != .none ? appState.accentSwiftUIColor.opacity(0.20) : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    appState.haptics.softSelection()
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        appState.isQueueSheetPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()
                .overlay(Color.white.opacity(0.10))

            if queue.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                    Text("Очередь воспроизведения пуста")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 208)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(queue.enumerated()), id: \.offset) { index, item in
                                let isCurrent = (index == currentIdx)
                                let dlPct = appState.downloadProgress(for: item)
                                let isPendingDl = (appState.pendingDownloadTrack?.id == item.id) || (dlPct != nil)
                                let rowDlColor = appState.downloadAccentColor(for: item)

                                Button {
                                    appState.playTrack(item, in: queue)
                                } label: {
                                    HStack(spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(
                                                isPendingDl
                                                    ? rowDlColor
                                                    : (isCurrent ? appState.accentSwiftUIColor : .white.opacity(0.44))
                                            )
                                            .frame(width: 22, alignment: .leading)

                                        ArtworkThumbnailView(
                                            track: item,
                                            localPath: appState.libraryState.customAlbumCovers[item.album] ?? item.coverPath,
                                            remoteURL: item.remoteArtworkURL,
                                            fallbackSeed: "\(item.album)|\(item.artist)",
                                            cornerRadius: 8,
                                            sizeTier: .listThumbnail
                                        )
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            if isPendingDl {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(rowDlColor, lineWidth: 1.4)
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 1.5) {
                                            Text(item.title)
                                                .font(.system(size: 13.5, weight: (isCurrent || isPendingDl) ? .bold : .semibold, design: .rounded))
                                                .foregroundStyle(
                                                    isPendingDl
                                                        ? rowDlColor
                                                        : (isCurrent ? appState.accentSwiftUIColor : .white)
                                                )
                                                .lineLimit(1)

                                            Text(item.artist)
                                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.62))
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 4)

                                        if let pct = dlPct {
                                            Text("\(pct)%")
                                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                                .foregroundStyle(rowDlColor)
                                        } else if isCurrent {
                                            Image(systemName: "waveform")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(appState.accentSwiftUIColor)
                                        }

                                        Text(FullScreenPlayerView.formatSeconds(item.duration))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.52))
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(
                                                isPendingDl
                                                    ? rowDlColor.opacity(0.14)
                                                    : (isCurrent ? appState.accentSwiftUIColor.opacity(0.16) : Color.white.opacity(0.04))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                    .strokeBorder(
                                                        isPendingDl
                                                            ? rowDlColor.opacity(0.75)
                                                            : Color.white.opacity(isCurrent ? 0.22 : 0.05),
                                                        lineWidth: isPendingDl ? 1.1 : 0.6
                                                    )
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    // Ровно 4 трека по высоте (4 × 52pt = 208pt), прокручиваются пальцем напрямую без растягивания окна
                    .frame(height: 208)
                    .onAppear {
                        let target = min(max(0, currentIdx), max(0, queue.count - 1))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.20)) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .liquidGlassCard(cornerRadius: 24, tint: appState.accentSwiftUIColor, tintOpacity: 0.10, isInteractive: true)
    }
}

/// Модальное окно очереди воспроизведения в стиле Liquid Glass
public struct QueueSheetView: View {
    @ObservedObject var appState: BebranoidAppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            CompactPlayerQueueOverlayView(appState: appState)
                .padding(.horizontal, 18)
        }
        .presentationBackground(.clear)
    }
}

/// Всплывающее полупрозрачное окно «Свойства трека» (`src/components/TrackInfoModal.jsx` 1:1) в эстетике Apple Liquid Glass:
/// не скрывает задний фон (оставляет его видимым) и содержит дату выгрузки трека и переход к сообщению в Telegram.
public struct TrackInfoSheetView: View {
    public let track: Track
    public let formatInfo: AudioFormatInfo?
    public var accentColor: Color
    @Environment(\.dismiss) private var dismiss

    public init(track: Track, formatInfo: AudioFormatInfo?, accentColor: Color = .white) {
        self.track = track
        self.formatInfo = formatInfo
        self.accentColor = accentColor
    }

    public var body: some View {
        let resolvedFormat = formatInfo ?? AudioFormatInfo.fallbackFromFilename(track.filename, fileSize: track.fileSize, duration: track.duration)
        let badge = resolvedFormat.computeQualityBadge()
        let isLossless = (badge.tier == .hiRes || badge.tier == .lossless)
        let canOpenTG = TrackMetadataActions.canJumpToTelegram(track)

        ZStack {
            // Полупрозрачная дымка, сквозь которую полностью виден задний фон приложения
            Color.black.opacity(0.26)
                .ignoresSafeArea()
                .onTapGesture {
                    HapticsManager.shared.lightTap()
                    dismiss()
                }

            VStack(spacing: 14) {
                // Шапка окна «Свойства трека»
                HStack {
                    Text("Свойства трека")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        HapticsManager.shared.lightTap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Карточка трека с обложкой и бейджем качества
                HStack(spacing: 13) {
                    ArtworkThumbnailView(
                        track: track,
                        localPath: track.coverPath,
                        remoteURL: track.remoteArtworkURL,
                        fallbackSeed: "\(track.album)|\(track.artist)",
                        cornerRadius: 14,
                        sizeTier: .albumGrid
                    )
                    .frame(width: 68, height: 68)
                    .shadow(color: .black.opacity(0.32), radius: 10, x: 0, y: 5)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: isLossless ? "waveform.badge.checkmark" : "waveform")
                                .font(.system(size: 10, weight: .bold))
                            Text(isLossless ? "Lossless Audio (Без потерь)" : "Сжатый звук (Lossy)")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.22), in: Capsule())
                        .foregroundStyle(accentColor)

                        Text(track.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text("\(track.artist) • \(track.album)")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Divider()
                    .overlay(Color.white.opacity(0.12))

                // Сетка параметров 1:1 как в ПК-версии (`src/components/TrackInfoModal.jsx`)
                VStack(spacing: 8) {
                    infoRow("Формат", resolvedFormat.codec)
                    infoRow(
                        "Разрядность",
                        resolvedFormat.bitsPerSample != nil ? "\(resolvedFormat.bitsPerSample!) bit" : "— (Поток с потерями)"
                    )
                    infoRow(
                        "Частота дискретизации",
                        resolvedFormat.sampleRateHz != nil
                            ? String(format: "%.1f kHz", Double(resolvedFormat.sampleRateHz!) / 1000.0)
                            : "44.1 kHz"
                    )
                    infoRow(
                        "Каналы",
                        resolvedFormat.channels != nil
                            ? "\(resolvedFormat.channels!) (\(resolvedFormat.channels == 1 ? "Моно" : "Стерео"))"
                            : "2 (Стерео)"
                    )
                    infoRow(
                        "Битрейт",
                        resolvedFormat.bitrateKbps != nil ? "\(resolvedFormat.bitrateKbps!) kbps" : "Авто"
                    )
                    if let size = track.fileSize, size > 0 {
                        let mb = Double(size) / (1024.0 * 1024.0)
                        infoRow("Размер файла", String(format: "%.2f МБ", mb))
                    }
                    infoRow("Длительность", FullScreenPlayerView.formatSeconds(track.duration))
                    infoRow("Дата выгрузки", TrackMetadataActions.formatUploadDate(track.dateAdded))
                }

                // Кнопка перехода к сообщению в Telegram (как в ПК-версии `TrackInfoModal.jsx`)
                if canOpenTG {
                    Button {
                        HapticsManager.shared.mediumImpact()
                        TrackMetadataActions.openInTelegram(track)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Показать в Telegram")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.20, green: 0.58, blue: 0.98).opacity(0.32))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color(red: 0.35, green: 0.72, blue: 1.0).opacity(0.65), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .liquidGlassCard(cornerRadius: 28, tint: accentColor, tintOpacity: 0.12, isInteractive: false)
            .padding(.horizontal, 20)
        }
        .presentationBackground(.clear)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Панель звуковых эффектов, скорости, Bass Boost и кроссфейда (`src/App.jsx` + `src/components/Player.jsx`) в стиле Liquid Glass
/// с оригинальными иконками красной розочки (`Slowed`) и синей розочки (`Speed Up`).
public struct AudioFXSheetView: View {
    @ObservedObject var appState: BebranoidAppState
    @Environment(\.dismiss) private var dismiss

    private let speedPresets: [Float] = [0.75, 0.9, 1.0, 1.15, 1.25, 1.5]

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassSheetBackdrop(accentColor: appState.accentSwiftUIColor)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 1. Пресеты Audio FX (`normal`, `slowed`, `slowed_reverb`, `speedup`, `speedup_reverb`)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Атмосферные режимы (Audio FX)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.84))
                                .padding(.horizontal, 4)

                            VStack(spacing: 8) {
                                ForEach(AudioFXMode.allCases) { mode in
                                    let isSelected = appState.audioFXMode == mode
                                    let modeTint = FXRoseStyle.tintColor(for: mode, fallbackAccent: appState.accentSwiftUIColor)
                                    Button {
                                        appState.haptics.softSelection()
                                        appState.audioFXMode = mode
                                    } label: {
                                        HStack(spacing: 10) {
                                            if mode != .normal {
                                                FXRoseBadgeIcon(mode: mode, size: 18)
                                            } else {
                                                Image(systemName: "waveform")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(.white.opacity(0.75))
                                                    .frame(width: 18, height: 18)
                                            }

                                            Text(mode.displayName)
                                                .font(.system(size: 15, weight: isSelected ? .bold : .semibold, design: .rounded))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(modeTint)
                                            }
                                        }
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                                .fill(isSelected ? modeTint.opacity(0.20) : Color.white.opacity(0.06))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                                        .strokeBorder(
                                                            isSelected ? modeTint.opacity(0.60) : Color.white.opacity(0.10),
                                                            lineWidth: 0.9
                                                        )
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .liquidGlassCard(cornerRadius: 22, tint: appState.accentSwiftUIColor, tintOpacity: 0.06, isSheer: true)
                        }

                        // 2. Bass Boost (+8 dB @ 180 Hz)
                        Toggle(isOn: $appState.bassBoostEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bass Boost (+8 dB @ 180 Hz)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("Параметрический Low-Shelf фильтр Q = 0.707")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        .tint(appState.accentSwiftUIColor)
                        .padding(16)
                        .liquidGlassCard(cornerRadius: 20, tint: appState.accentSwiftUIColor, tintOpacity: 0.06, isSheer: true)

                        // 3. Скорость воспроизведения (0.5x – 2.0x)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Скорость воспроизведения")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.84))
                                Spacer()
                                Text(String(format: "%.2fx", appState.playbackSpeed))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(appState.accentSwiftUIColor)
                            }

                            Slider(value: $appState.playbackSpeed, in: 0.5...2.0, step: 0.05)
                                .tint(appState.accentSwiftUIColor)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(speedPresets, id: \.self) { preset in
                                        let active = abs(appState.playbackSpeed - preset) < 0.01
                                        Button(String(format: "%.2gx", preset)) {
                                            appState.haptics.softSelection()
                                            appState.playbackSpeed = preset
                                        }
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(active ? Color(red: 0.08, green: 0.06, blue: 0.14) : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .liquidGlassCapsule(tint: appState.accentSwiftUIColor, isProminent: active)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .liquidGlassCard(cornerRadius: 20, tint: appState.accentSwiftUIColor, tintOpacity: 0.06, isSheer: true)

                        // 4. Настоящий двухпоточный кроссфейд (0.5–30 с)
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Плавный переход (Crossfade)", isOn: $appState.crossfadeEnabled)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .tint(appState.accentSwiftUIColor)

                            if appState.crossfadeEnabled {
                                HStack {
                                    Text("Длительность перехода")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.72))
                                    Spacer()
                                    Text(String(format: "%.1f с", appState.crossfadeDuration))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(appState.accentSwiftUIColor)
                                }
                                Slider(
                                    value: $appState.crossfadeDuration,
                                    in: AppConfig.minCrossfadeDuration...AppConfig.maxCrossfadeDuration,
                                    step: 0.5
                                )
                                .tint(appState.accentSwiftUIColor)
                            }
                        }
                        .padding(16)
                        .liquidGlassCard(cornerRadius: 20, tint: appState.accentSwiftUIColor, tintOpacity: 0.06, isSheer: true)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Звук и эффекты")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .liquidGlassSheetPresentation()
    }
}
