import SwiftUI
import UniformTypeIdentifiers

/// Полный экран настроек Bebranoid iOS (`src/views/Settings.jsx` + `src/views/Auth.jsx`).
/// Включает:
/// - Настоящую авторизацию TDLib (API ID, API Hash, телефон, код, QR-вход, 2FA) и выбор основного/архивного чата Telegram
/// - Импорт локальных аудиофайлов (`FLAC`, `ALAC`, `WAV`, `M4A`, `MP3`, `OPUS`) через системный файловый пикер
/// - Настройки переходов (`Crossfade`), кривой громкости (`u^2.75`) и энергосбережения фона
/// - Настройки движка текстов песен (`Beautiful Lyrics` vs `Classic Karaoke`) и размера шрифта
/// - Статистику локального кеша и очистку
/// - Диагностический экран (`DiagnosticsView`) в Debug-сборках
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
                                let userName = appState.telegramClient.authorizedUserDisplayName
                                Text(appState.telegramClient.isAuthorized
                                     ? (userName.map { "Telegram: \($0)" } ?? "Авторизован в Telegram")
                                     : "Вход по QR-коду Telegram")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(appState.telegramClient.isAuthorized
                                     ? (appState.telegramClient.authorizedPhoneNumber ?? "Сессия активна • Чаты синхронизированы")
                                     : "Без ввода API-ключей • Автоподхват чатов и медиатеки")
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

                    #if DEBUG
                    Section("Диагностика (Debug QA)") {
                        NavigationLink {
                            DiagnosticsView(appState: appState)
                        } label: {
                            Label("Открыть экран диагностики подсистем", systemImage: "waveform.path.ecg.rectangle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(appState.accentSwiftUIColor)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                    #endif
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
/// Единственный источник статуса авторизации — `authorizationStateReady` от TDLib.
public struct TelegramAuthView: View {
    @ObservedObject var appState: BebranoidAppState
    @StateObject private var authVM = TelegramAuthViewModel()
    @State private var showPhoneLogin: Bool = true
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
                        HStack(spacing: 8) {
                            Circle()
                                .fill(authVM.connectionState == .ready ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text("TDLib: \(authVM.connectionState.rawValue)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.75))
                        }

                        switch authVM.step {
                        case .unauthorized:
                            if showPhoneLogin {
                                phoneStepView
                            } else {
                                qrConfirmationStepView(link: authVM.qrCodeConfirmLink ?? "")
                            }
                        case .awaitingCode:
                            codeStepView
                        case .awaitingQRConfirmation(let link):
                            if showPhoneLogin {
                                phoneStepView
                            } else {
                                qrConfirmationStepView(link: link)
                            }
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
                    Task { await appState.handleTelegramAuthorized() }
                    dismiss()
                }
            }
            .task {
                // Сразу запрашиваем QR-код без необходимости искать и вводить API ID / API Hash
                if !showPhoneLogin, authVM.step == .unauthorized {
                    await authVM.requestQRLogin()
                }
            }
        }
    }

    private var phoneStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Быстрый вход в Telegram (без API-ключей)", systemImage: "paperplane.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text("Введите номер телефона — код придёт прямо в пуш-уведомлении приложения Telegram на этом iPhone (или отсканируйте QR-код с другого устройства).")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))

            TextField("Номер телефона (+380... / +7...)", text: $authVM.phoneNumber)
                #if os(iOS)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                #endif
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
                    Label("Получить код в Telegram", systemImage: "message.badge.filled.fill")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(appState.accentSwiftUIColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(authVM.isLoading)

            Button {
                showPhoneLogin = false
                Task { await authVM.requestQRLogin() }
            } label: {
                HStack(spacing: 8) {
                    Label("Показать QR-код (для сканирования с другого телефона)", systemImage: "qrcode")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(authVM.isLoading)

            DisclosureGroup("Пользовательские API ID / Hash (опционально)") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("По умолчанию используются проверенные ключи Bebranoid. Если хотите подключить личные ключи с https://my.telegram.org:")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.60))

                    TextField("Telegram API ID (число)", text: $authVM.apiId)
                        .padding(12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)

                    SecureField("Telegram API Hash", text: $authVM.apiHash)
                        .padding(12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)

                    Button("Сохранить свои ключи в Keychain") {
                        authVM.saveCredentialsOnly()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 6)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var codeStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Введите 5-значный код из уведомления Telegram")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            TextField("Код подтверждения", text: $authVM.verificationCode)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
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

    private func qrConfirmationStepView(link: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Вход через QR-код Telegram", systemImage: "qrcode.viewfinder")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text("Отсканируйте этот QR-код камерой другого устройства (Telegram → Настройки → Устройства → Подключить устройство). Если Telegram установлен на этом же iPhone — войдите по номеру телефона (код придёт в пуш-уведомлении).")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))

            Button {
                showPhoneLogin = true
            } label: {
                Label("Войти по номеру телефона на этом iPhone", systemImage: "phone.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(appState.accentSwiftUIColor, in: RoundedRectangle(cornerRadius: 14))
            }

            TelegramQRCodeView(link: link)
                .frame(maxWidth: 260)
                .frame(maxWidth: .infinity)

            if !authVM.isLoading {
                Button {
                    Task { await authVM.requestQRLogin() }
                } label: {
                    Label("Обновить QR-код", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
            }
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
            Label("Сессия TDLib активна (authorizationStateReady)", systemImage: "checkmark.shield.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.green)

            if let userName = appState.telegramClient.authorizedUserDisplayName, !userName.isEmpty {
                Text("Профиль: \(userName)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Телефон: \(appState.telegramClient.authorizedPhoneNumber ?? "Подключён")")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.80))

            Text("Основной чат: \(appState.libraryState.selectedTelegramChatTitle)")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.70))

            Button(role: .destructive) {
                authVM.logout()
            } label: {
                Text("Выйти из TDLib и очистить сессию")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
