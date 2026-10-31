import SwiftUI

/// Модальное окно очереди воспроизведения в стиле Liquid Glass (iOS 26 / iOS 27)
/// с поддержкой перетаскивания (`onMove`) и быстрого перехода к треку.
public struct QueueSheetView: View {
    @ObservedObject var appState: BebranoidAppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassSheetBackdrop(accentColor: appState.accentSwiftUIColor)

                if appState.queue.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                        Text("Очередь воспроизведения пуста")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(28)
                    .liquidGlassCard(cornerRadius: 24, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)
                    .padding(.horizontal, 24)
                } else {
                    List {
                        ForEach(Array(appState.queue.enumerated()), id: \.element.id) { index, track in
                            let isCurrent = index == appState.currentIndex
                            Button {
                                appState.playTrack(track, in: appState.queue)
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isCurrent ? appState.accentSwiftUIColor : .white.opacity(0.48))
                                        .frame(width: 24, alignment: .leading)

                                    ArtworkThumbnailView(
                                        track: track,
                                        localPath: appState.libraryState.customAlbumCovers[track.album] ?? track.coverPath,
                                        remoteURL: track.remoteArtworkURL,
                                        fallbackSeed: "\(track.album)|\(track.artist)",
                                        cornerRadius: 10,
                                        sizeTier: .listThumbnail
                                    )
                                    .frame(width: 44, height: 44)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.system(size: 15, weight: isCurrent ? .bold : .semibold, design: .rounded))
                                            .foregroundStyle(isCurrent ? appState.accentSwiftUIColor : .white)
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.65))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if isCurrent {
                                        Image(systemName: "waveform")
                                            .foregroundStyle(appState.accentSwiftUIColor)
                                    }

                                    Text(FullScreenPlayerView.formatSeconds(track.duration))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.58))
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isCurrent ? appState.accentSwiftUIColor.opacity(0.16) : Color.white.opacity(0.07))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.white.opacity(isCurrent ? 0.28 : 0.10), lineWidth: 0.7)
                                    )
                                    .padding(.vertical, 2)
                            )
                            .listRowSeparator(.hidden)
                        }
                        .onMove { from, to in
                            appState.queue.move(fromOffsets: from, toOffset: to)
                            if let current = appState.currentTrack,
                               let updatedIdx = appState.queue.firstIndex(where: { $0.id == current.id }) {
                                appState.currentIndex = updatedIdx
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Очередь (\(appState.queue.count))")
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
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(appState.accentSwiftUIColor)
                }
                #endif
            }
        }
        .liquidGlassSheetPresentation()
    }
}

/// Модальное окно технических сведений о файле (`src/components/TrackInfoModal.jsx` 1:1) в стиле Liquid Glass.
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

        NavigationStack {
            ZStack {
                LiquidGlassSheetBackdrop(accentColor: accentColor)

                ScrollView {
                    VStack(spacing: 16) {
                        glassSection(title: "Метаданные трека") {
                            infoRow("Название", track.title)
                            infoRow("Исполнитель", track.artist)
                            infoRow("Альбом", track.album)
                            if let year = track.year {
                                infoRow("Год", "\(year)")
                            }
                            infoRow("Длительность", FullScreenPlayerView.formatSeconds(track.duration))
                        }

                        glassSection(title: "Качество и кодек") {
                            infoRow("Класс качества", badge.label)
                            infoRow("Кодек", resolvedFormat.codec)
                            if let sr = resolvedFormat.sampleRateHz {
                                infoRow("Частота дискретизации", "\(sr) Hz")
                            }
                            if let bps = resolvedFormat.bitsPerSample {
                                infoRow("Разрядность", "\(bps)-bit")
                            }
                            if let br = resolvedFormat.bitrateKbps {
                                infoRow("Битрейт", "\(br) kbps")
                            }
                            if let ch = resolvedFormat.channels {
                                infoRow("Каналы", ch == 2 ? "Стерео (2)" : "\(ch)")
                            }
                        }

                        glassSection(title: "Источник и хранилище") {
                            infoRow("Источник", track.sourceKind.rawValue.uppercased())
                            infoRow("Внутренний ID", track.id)
                            infoRow("Имя файла", track.filename)
                            if let size = track.fileSize, size > 0 {
                                let mb = Double(size) / (1024.0 * 1024.0)
                                infoRow("Размер файла", String(format: "%.2f МБ", mb))
                            }
                            if track.isFromArchive {
                                infoRow("Статус архива", "Архивный чат (Read-Only)")
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Сведения о треке")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .liquidGlassSheetPresentation()
    }

    @ViewBuilder
    private func glassSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                content()
            }
            .padding(15)
            .liquidGlassCard(cornerRadius: 20, tint: accentColor, tintOpacity: 0.08)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Панель звуковых эффектов, скорости, Bass Boost и кроссфейда (`src/App.jsx` + `src/components/Player.jsx`) в стиле Liquid Glass.
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
                                    Button {
                                        appState.haptics.softSelection()
                                        appState.audioFXMode = mode
                                    } label: {
                                        HStack {
                                            Text(mode.displayName)
                                                .font(.system(size: 15, weight: isSelected ? .bold : .semibold, design: .rounded))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(appState.accentSwiftUIColor)
                                            }
                                        }
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                                .fill(isSelected ? appState.accentSwiftUIColor.opacity(0.18) : Color.white.opacity(0.06))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                                        .strokeBorder(
                                                            isSelected ? appState.accentSwiftUIColor.opacity(0.55) : Color.white.opacity(0.10),
                                                            lineWidth: 0.9
                                                        )
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .liquidGlassCard(cornerRadius: 22, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)
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
                        .liquidGlassCard(cornerRadius: 20, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)

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
                        .liquidGlassCard(cornerRadius: 20, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)

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
                        .liquidGlassCard(cornerRadius: 20, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)
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
