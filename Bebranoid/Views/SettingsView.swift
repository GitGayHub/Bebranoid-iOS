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
                                     : "Быстрый вход в Telegram")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(appState.telegramClient.isAuthorized
                                     ? (appState.telegramClient.authorizedPhoneNumber ?? "Сессия активна • Чаты синхронизированы")
                                     : "Код приходит сразу в Telegram • Автоподхват чатов")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.65))
                            }

                            Spacer()

                            Button(appState.telegramClient.isAuthorized ? "Аккаунт" : "Войти") {
                                appState.openTelegramAuthSheet()
                            }
                            .buttonStyle(.plain)
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
                        Toggle("3D-вращение обложки гироскопом", isOn: $appState.isGyroscope3DCoverEnabled)
                            .foregroundStyle(.white)
                            .tint(appState.accentSwiftUIColor)

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

/// Незакрываемое диалоговое меню быстрой авторизации Telegram через нативный `TDLibFramework`.
/// По умолчанию работает по номеру телефона (5-значный код мгновенно приходит в чат «Telegram»).
/// Закрывается строго по кнопке «Отменить» или после успешного входа, чтобы свайп или переключение в Telegram за кодом никогда не сбрасывали окно.
public struct TelegramAuthView: View {
    @ObservedObject var appState: BebranoidAppState
    @StateObject private var authVM = TelegramAuthViewModel()
    @State private var showPhoneLogin: Bool = true
    @FocusState private var focusedField: AuthFieldFocus?
    @Environment(\.dismiss) private var dismiss

    private enum AuthFieldFocus: Hashable {
        case phone
        case code
        case password2FA
    }

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    private func closeModal() {
        focusedField = nil
        appState.isTelegramAuthPresented = false
        dismiss()
    }

    private var canContinueCurrentStep: Bool {
        if authVM.isLoading { return false }
        switch authVM.step {
        case .unauthorized, .awaitingQRConfirmation:
            if showPhoneLogin {
                return authVM.phoneNumber.filter(\.isWholeNumber).count >= 8
            } else {
                return true
            }
        case .awaitingCode:
            return authVM.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
        case .awaiting2FAPassword:
            return !authVM.twoFactorPassword.isEmpty
        case .authorized:
            return true
        }
    }

    private var continueButtonTitle: String {
        switch authVM.step {
        case .unauthorized, .awaitingQRConfirmation:
            return showPhoneLogin ? "Продолжить" : "Обновить QR"
        case .awaitingCode:
            return "Продолжить"
        case .awaiting2FAPassword:
            return "Продолжить"
        case .authorized:
            return "Готово"
        }
    }

    private func performPrimaryContinue() {
        switch authVM.step {
        case .unauthorized, .awaitingQRConfirmation:
            if showPhoneLogin {
                focusedField = nil
                Task { await authVM.requestCode() }
            } else {
                Task { await authVM.requestQRLogin() }
            }
        case .awaitingCode:
            focusedField = nil
            Task { await authVM.submitCode() }
        case .awaiting2FAPassword:
            focusedField = nil
            Task { await authVM.submit2FAPassword() }
        case .authorized:
            closeModal()
        }
    }

    public var body: some View {
        ZStack {
            // Затемнённая подложка без закрытия по тапу мимо или свайпу вниз
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    VStack(alignment: .leading, spacing: 16) {
                        // Шапка менюшки
                        HStack(spacing: 10) {
                            Image(systemName: "paperplane.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color(red: 0.24, green: 0.68, blue: 1.0))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Вход в Telegram")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(authVM.connectionState == .ready ? Color.green : Color.orange)
                                        .frame(width: 7, height: 7)
                                    Text(authVM.connectionState == .ready ? "Подключено к Telegram" : authVM.connectionState.rawValue)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                            }

                            Spacer()

                            Label("Anti-Ban", systemImage: "checkmark.shield.fill")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundStyle(.green)
                        }

                        Divider().overlay(Color.white.opacity(0.12))

                        // Текущий шаг диалога
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
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                                Text(error)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        }

                        Divider().overlay(Color.white.opacity(0.12))

                        // Строгие кнопки менюшки: «Отменить» и «Продолжить»
                        HStack(spacing: 12) {
                            Button {
                                closeModal()
                            } label: {
                                Text("Отменить")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button {
                                performPrimaryContinue()
                            } label: {
                                HStack(spacing: 8) {
                                    if authVM.isLoading {
                                        ProgressView()
                                            .tint(Color(red: 0.08, green: 0.06, blue: 0.14))
                                            .scaleEffect(0.85)
                                    }
                                    Text(authVM.isLoading ? "Загрузка..." : continueButtonTitle)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    canContinueCurrentStep ? appState.accentSwiftUIColor : appState.accentSwiftUIColor.opacity(0.45),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canContinueCurrentStep)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(red: 0.10, green: 0.10, blue: 0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.55), radius: 28, y: 12)
                    )
                    .padding(.horizontal, 18)

                    Spacer(minLength: 32)
                }
                .frame(minHeight: 460)
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            authVM.onAuthSuccess = {
                Task { await appState.handleTelegramAuthorized() }
                closeModal()
            }
            if authVM.step == .unauthorized && showPhoneLogin {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    focusedField = .phone
                }
            }
        }
        .onChange(of: authVM.step) { _, newStep in
            switch newStep {
            case .awaitingCode:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    focusedField = .code
                }
            case .awaiting2FAPassword:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    focusedField = .password2FA
                }
            default:
                break
            }
        }
        .task {
            // Инициализируем TDLib в состоянии ожидания номера (БЕЗ вызова QR, который раньше блокировал отправку кода!)
            if !appState.telegramClient.isAuthorized {
                _ = await appState.telegramClient.initializeAndRestoreSession()
            }
        }
    }

    private var phoneStepView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Введите ваш номер телефона — 5-значный код мгновенно придёт в чат «Telegram» на вашем телефоне.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.80))

            TextField("+380... или +7...", text: $authVM.phoneNumber)
                .focused($focusedField, equals: .phone)
                #if os(iOS)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                #endif
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .padding(14)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focusedField == .phone ? appState.accentSwiftUIColor : Color.white.opacity(0.12), lineWidth: 1.2)
                )
                .foregroundStyle(.white)

            HStack {
                Button {
                    focusedField = nil
                    showPhoneLogin = false
                    Task { await authVM.requestQRLogin() }
                } label: {
                    Label("Вход по QR с другого телефона", systemImage: "qrcode")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appState.accentSwiftUIColor)
                }
                .buttonStyle(.plain)
                .disabled(authVM.isLoading)

                Spacer()

                Button {
                    Task { await authVM.resetToPhoneInput() }
                } label: {
                    Label("Сброс сессии", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .disabled(authVM.isLoading)
            }
            .padding(.top, 2)
        }
    }

    private var codeStepView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "message.badge.filled.fill")
                    .foregroundStyle(appState.accentSwiftUIColor)
                Text(authVM.codeDeliveryHint ?? "Код отправлен в приложение Telegram")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Откройте приложение Telegram (чат «Telegram»), скопируйте 5-значный код и введите его ниже. Это окно не закроется при переключении приложений.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.72))

            TextField("5-значный код (например: 12345)", text: $authVM.verificationCode)
                .focused($focusedField, equals: .code)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(14)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(appState.accentSwiftUIColor, lineWidth: 1.5)
                )
                .foregroundStyle(.white)
                .onChange(of: authVM.verificationCode) { _, newValue in
                    let digits = newValue.filter(\.isWholeNumber)
                    if digits != newValue {
                        authVM.verificationCode = digits
                    }
                    if digits.count == 5 && !authVM.isLoading {
                        focusedField = nil
                        Task { await authVM.submitCode() }
                    }
                }

            HStack {
                Button {
                    Task { await authVM.resetToPhoneInput() }
                } label: {
                    Label("Изменить номер", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .disabled(authVM.isLoading)

                Spacer()

                Button {
                    Task { await authVM.resendCode() }
                } label: {
                    Label("Отправить код ещё раз", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appState.accentSwiftUIColor)
                }
                .buttonStyle(.plain)
                .disabled(authVM.isLoading)
            }
        }
    }

    private func qrConfirmationStepView(link: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Отсканируйте QR-код камерой второго устройства (Telegram → Настройки → Устройства → Подключить устройство).")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))

            TelegramQRCodeView(link: link)
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity)

            Button {
                showPhoneLogin = true
                Task { await authVM.resetToPhoneInput() }
            } label: {
                Label("Вернуться ко входу по номеру телефона", systemImage: "phone.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(appState.accentSwiftUIColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var twoFactorStepView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Облачный пароль 2FA", systemImage: "lock.shield.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            if let hint = authVM.twoFactorHint, !hint.isEmpty {
                Text("Подсказка пароля: \(hint)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.68))
            }

            SecureField("Введите облачный пароль Telegram", text: $authVM.twoFactorPassword)
                .focused($focusedField, equals: .password2FA)
                .padding(14)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(appState.accentSwiftUIColor, lineWidth: 1.2)
                )
                .foregroundStyle(.white)
                .onSubmit {
                    performPrimaryContinue()
                }
        }
    }

    private var authorizedSummaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Вы успешно вошли в Telegram", systemImage: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.green)

            if let userName = appState.telegramClient.authorizedUserDisplayName, !userName.isEmpty {
                Text("Аккаунт: \(userName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Телефон: \(appState.telegramClient.authorizedPhoneNumber ?? "Подключён")")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.80))

            Text("Основной чат: \(appState.libraryState.selectedTelegramChatTitle)")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.68))

            Button(role: .destructive) {
                authVM.logout()
            } label: {
                Text("Выйти из аккаунта Telegram")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.red.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}
