import SwiftUI
import UniformTypeIdentifiers

/// Полный экран настроек Bebranoid iOS (`src/views/Settings.jsx` + `src/views/Auth.jsx`).
/// Включает:
/// - Настоящую авторизацию TDLib (API ID, API Hash, телефон, код, 2FA) и выбор основного/архивного чата Telegram
/// - Импорт локальных аудиофайлов (`FLAC`, `ALAC`, `WAV`, `M4A`, `MP3`, `OPUS`) через системный файловый пикер
/// - Настройки переходов (`Crossfade`), кривой громкости (`u^2.75`) и энергосбережения фона
/// - Настройки движка текстов песен (`Beautiful Lyrics` vs `Classic Karaoke`) и размера шрифта
/// - Статистику локального кеша и очистку
public struct SettingsView: View {
    @ObservedObject var appState: BebranoidAppState
    @State private var isTelegramAuthPresented: Bool = false
    @State private var isFileImporterPresented: Bool = false
    @State private var cacheStats: (totalBytes: Int64, fileCount: Int) = (0, 0)

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.28).ignoresSafeArea()

                List {
                    Section("Облако Telegram (TDLib)") {
                        HStack {
                            Image(systemName: "paperplane.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color(red: 0.24, green: 0.68, blue: 1.0))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(appState.telegramClient.isAuthorized ? "Авторизован в Telegram" : "Не выполнен вход")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(appState.telegramClient.authorizedPhoneNumber ?? "Подключите аккаунт через нативный TDLib")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.65))
                            }

                            Spacer()

                            Button(appState.telegramClient.isAuthorized ? "Аккаунт" : "Войти") {
                                isTelegramAuthPresented = true
                            }
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(appState.accentSwiftUIColor, in: Capsule())
                            .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                        }

                        Menu {
                            if appState.availableTelegramChats.isEmpty {
                                Button("Загрузить список чатов из TDLib") {
                                    Task { await appState.refreshTelegramChats() }
                                }
                            } else {
                                ForEach(appState.availableTelegramChats) { chat in
                                    Button {
                                        appState.selectTelegramMainChat(chat)
                                    } label: {
                                        Label(
                                            "\(chat.title) (\(chat.id))",
                                            systemImage: chat.id == appState.libraryState.selectedTelegramChatId ? "checkmark.circle.fill" : "bubble.left.and.bubble.right"
                                        )
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Основной чат")
                                    .foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                Text(appState.libraryState.selectedTelegramChatTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }

                        Menu {
                            Button("Не использовать архивный чат") {
                                appState.selectTelegramArchiveChat(nil)
                            }
                            ForEach(appState.availableTelegramChats) { chat in
                                Button {
                                    appState.selectTelegramArchiveChat(chat)
                                } label: {
                                    Label(
                                        "\(chat.title) (\(chat.id))",
                                        systemImage: chat.id == appState.libraryState.selectedTelegramArchiveChatId ? "checkmark.circle.fill" : "archivebox"
                                    )
                                }
                            }
                        } label: {
                            HStack {
                                Text("Архивный чат (Read-Only)")
                                    .foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                Text(appState.libraryState.selectedTelegramArchiveChatTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                        }

                        if appState.telegramClient.isAuthorized {
                            Button {
                                Task { await appState.refreshTelegramChats() }
                            } label: {
                                Label("Обновить список диалогов Telegram", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }

                            Button {
                                Task { await appState.syncTelegramLibrary() }
                            } label: {
                                HStack {
                                    Label(
                                        appState.isSyncingTelegramLibrary ? "Синхронизация медиатеки..." : "Синхронизировать аудио из выбранных чатов",
                                        systemImage: "icloud.and.arrow.down"
                                    )
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(appState.accentSwiftUIColor)

                                    if appState.isSyncingTelegramLibrary {
                                        Spacer()
                                        ProgressView().tint(appState.accentSwiftUIColor)
                                    }
                                }
                            }
                            .disabled(appState.isSyncingTelegramLibrary)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section("Локальные аудиофайлы (На iPhone)") {
                        Button {
                            isFileImporterPresented = true
                        } label: {
                            Label("Импортировать файлы (FLAC, WAV, M4A, MP3, OPUS)", systemImage: "folder.badge.plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(appState.accentSwiftUIColor)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section("Воспроизведение и кроссфейд") {
                        Toggle("Плавный кроссфейд между треками", isOn: $appState.crossfadeEnabled)
                            .foregroundStyle(.white)
                            .tint(appState.accentSwiftUIColor)

                        if appState.crossfadeEnabled {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Длительность кроссфейда")
                                        .foregroundStyle(.white.opacity(0.75))
                                    Spacer()
                                    Text(String(format: "%.1f сек", appState.crossfadeDuration))
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
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

                        Button {
                            appState.isAudioFXSheetPresented = true
                        } label: {
                            HStack {
                                Text("Панель Audio FX, скорости и Bass Boost")
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(appState.audioFXMode.displayName)
                                    .foregroundStyle(appState.accentSwiftUIColor)
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section("Тексты песен и караоке") {
                        Picker("Движок текстов", selection: $appState.lyricsEngine) {
                            ForEach(LyricsEngineKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .foregroundStyle(.white)

                        Picker("Размер шрифта", selection: $appState.lyricsFontSize) {
                            ForEach(LyricsFontSizePreset.allCases, id: \.self) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .foregroundStyle(.white)

                        Toggle("Перевод на русский (RU)", isOn: $appState.showLyricsTranslation)
                            .foregroundStyle(.white)
                            .tint(appState.accentSwiftUIColor)
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section("Визуализация и хранилище кеша") {
                        Toggle("Энергосберегающий режим Mesh-фона", isOn: $appState.isReducedMotionEnabled)
                            .foregroundStyle(.white)
                            .tint(appState.accentSwiftUIColor)

                        HStack {
                            Text("Закешировано файлов")
                                .foregroundStyle(.white.opacity(0.75))
                            Spacer()
                            let mb = Double(cacheStats.totalBytes) / (1024.0 * 1024.0)
                            Text("\(cacheStats.fileCount) шт. (\(String(format: "%.1f МБ", mb)))")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }

                        Button(role: .destructive) {
                            appState.cacheIndex.clearAudioCache()
                            refreshCacheStats()
                        } label: {
                            Label("Очистить загруженный аудиокеш", systemImage: "trash")
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Настройки")
            .onAppear {
                refreshCacheStats()
            }
            .sheet(isPresented: $isTelegramAuthPresented) {
                TelegramAuthView(appState: appState)
            }
            .sheet(isPresented: $appState.isAudioFXSheetPresented) {
                AudioFXSheetView(appState: appState)
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio, .folder],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        if let importedTrack = try? appState.storage.importLocalAudioFile(from: url) {
                            if !appState.libraryState.tracks.contains(where: { $0.id == importedTrack.id }) {
                                appState.libraryState.tracks.insert(importedTrack, at: 0)
                            }
                        }
                    }
                    appState.saveLibraryState()
                    refreshCacheStats()
                }
            }
        }
    }

    private func refreshCacheStats() {
        cacheStats = appState.cacheIndex.calculateCacheStats()
    }
}

/// Экран пошаговой авторизации Telegram через нативный `TDLibFramework` (`src/views/Auth.jsx`).
public struct TelegramAuthView: View {
    @ObservedObject var appState: BebranoidAppState
    @StateObject private var authVM = TelegramAuthViewModel()
    @Environment(\.dismiss) private var dismiss

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch authVM.step {
                        case .unauthorized:
                            phoneStepView
                        case .awaitingCode:
                            codeStepView
                        case .awaiting2FAPassword:
                            twoFactorStepView
                        case .authorized:
                            authorizedSummaryView
                        }

                        if let error = authVM.errorMessage {
                            Text(error)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Вход в Telegram")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .onAppear {
                authVM.onAuthSuccess = {
                    Task { await appState.refreshTelegramChats() }
                    dismiss()
                }
            }
        }
    }

    private var phoneStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Нативная сессия TDLib на iPhone")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text("Получите персональные api_id и api_hash на https://my.telegram.org — ключи сохраняются только в защищённом iOS Keychain.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.68))

            TextField("Telegram API ID (число)", text: $authVM.apiId)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)

            SecureField("Telegram API Hash", text: $authVM.apiHash)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)

            TextField("Номер телефона (+7... / +380...)", text: $authVM.phoneNumber)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)

            Button {
                Task { await authVM.requestCode() }
            } label: {
                HStack(spacing: 8) {
                    if authVM.isLoading {
                        ProgressView().tint(Color(red: 0.08, green: 0.06, blue: 0.14))
                    }
                    Text("Отправить код подтверждения через TDLib")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(appState.accentSwiftUIColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(authVM.isLoading)

            Button("Сохранить API ID / API Hash в Keychain") {
                authVM.saveCredentialsOnly()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var codeStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Введите код из приложения Telegram")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            TextField("Код подтверждения", text: $authVM.verificationCode)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)

            Button {
                Task { await authVM.submitCode() }
            } label: {
                Text("Подтвердить код")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(appState.accentSwiftUIColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(authVM.isLoading)
        }
    }

    private var twoFactorStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Облачный пароль двухфакторной аутентификации (2FA)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            if let hint = authVM.twoFactorHint, !hint.isEmpty {
                Text("Подсказка пароля: \(hint)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
            }

            SecureField("Облачный пароль 2FA", text: $authVM.twoFactorPassword)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)

            Button {
                Task { await authVM.submit2FAPassword() }
            } label: {
                Text("Войти")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(appState.accentSwiftUIColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(authVM.isLoading)
        }
    }

    private var authorizedSummaryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Сессия TDLib активна и защищена в Keychain", systemImage: "checkmark.shield.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.green)

            Text("Аккаунт: \(appState.telegramClient.authorizedPhoneNumber ?? "Подключён")")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.80))

            Button(role: .destructive) {
                authVM.logout()
            } label: {
                Text("Выйти из TDLib и очистить Keychain")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
