import SwiftUI

/// Модальное окно очереди воспроизведения с поддержкой перетаскивания (`onMove`), удаления и быстрого перехода к треку.
public struct QueueSheetView: View {
    @ObservedObject var appState: BebranoidAppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()

                if appState.queue.isEmpty {
                    Text("Очередь воспроизведения пуста")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
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
                                        .foregroundStyle(isCurrent ? appState.accentSwiftUIColor : .white.opacity(0.45))
                                        .frame(width: 26, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.system(size: 15, weight: isCurrent ? .bold : .semibold))
                                            .foregroundStyle(isCurrent ? appState.accentSwiftUIColor : .white)
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.62))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if isCurrent {
                                        Image(systemName: "waveform")
                                            .foregroundStyle(appState.accentSwiftUIColor)
                                    }
                                }
                            }
                            .listRowBackground(Color.white.opacity(isCurrent ? 0.12 : 0.04))
                        }
                        .onMove { from, to in
                            appState.queue.move(fromOffsets: from, toOffset: to)
                            if let current = appState.currentTrack,
                               let updatedIdx = appState.queue.firstIndex(where: { $0.id == current.id }) {
                                appState.currentIndex = updatedIdx
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Очередь (\(appState.queue.count))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(.white)
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                        .foregroundStyle(appState.accentSwiftUIColor)
                }
                #endif
            }
        }
    }
}

/// Модальное окно технических сведений о файле (`src/components/TrackInfoModal.jsx` 1:1).
public struct TrackInfoSheetView: View {
    public let track: Track
    public let formatInfo: AudioFormatInfo?
    @Environment(\.dismiss) private var dismiss

    public init(track: Track, formatInfo: AudioFormatInfo?) {
        self.track = track
        self.formatInfo = formatInfo
    }

    public var body: some View {
        let resolvedFormat = formatInfo ?? AudioFormatInfo.fallbackFromFilename(track.filename, fileSize: track.fileSize, duration: track.duration)
        let badge = resolvedFormat.computeQualityBadge()

        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()

                List {
                    Section("Метаданные трека") {
                        infoRow("Название", track.title)
                        infoRow("Исполнитель", track.artist)
                        infoRow("Альбом", track.album)
                        if let year = track.year {
                            infoRow("Год", "\(year)")
                        }
                        infoRow("Длительность", FullScreenPlayerView.formatSeconds(track.duration))
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section("Качество и кодек") {
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
                    .listRowBackground(Color.white.opacity(0.06))

                    Section("Источник и хранилище") {
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
                    .listRowBackground(Color.white.opacity(0.06))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Сведения о треке")
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

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Панель звуковых эффектов, скорости, Bass Boost и кроссфейда (`src/App.jsx` + `src/components/Player.jsx`).
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
                Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. Пресеты Audio FX (`normal`, `slowed`, `slowed_reverb`, `speedup`, `speedup_reverb`)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Атмосферные режимы (Audio FX)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.80))

                            ForEach(AudioFXMode.allCases) { mode in
                                let isSelected = appState.audioFXMode == mode
                                Button {
                                    appState.haptics.softSelection()
                                    appState.audioFXMode = mode
                                } label: {
                                    HStack {
                                        Text(mode.displayName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(appState.accentSwiftUIColor)
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        Color.white.opacity(isSelected ? 0.14 : 0.06),
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // 2. Bass Boost (+8 dB @ 180 Hz)
                        Toggle(isOn: $appState.bassBoostEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bass Boost (+8 dB @ 180 Hz)")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("Параметрический Low-Shelf фильтр Q = 0.707")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.62))
                            }
                        }
                        .tint(appState.accentSwiftUIColor)
                        .padding(14)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                        // 3. Скорость воспроизведения (0.5x – 2.0x)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Скорость воспроизведения")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.80))
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
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            active ? appState.accentSwiftUIColor : Color.white.opacity(0.10),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(active ? Color(red: 0.08, green: 0.06, blue: 0.14) : .white)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                        // 4. Настоящий двухпоточный кроссфейд (0.5–30 с)
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Плавный переход (Crossfade)", isOn: $appState.crossfadeEnabled)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .tint(appState.accentSwiftUIColor)

                            if appState.crossfadeEnabled {
                                HStack {
                                    Text("Длительность перехода")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.70))
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
                        .padding(14)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Звук и эффекты")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
