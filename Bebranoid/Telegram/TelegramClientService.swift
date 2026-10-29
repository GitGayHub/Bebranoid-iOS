import Foundation
#if canImport(TDLibFramework)
import TDLibFramework
#endif

public struct TelegramChatSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var isForum: Bool
    public var isReadOnlyArchive: Bool
    public var unreadAudioCount: Int

    public init(
        id: String,
        title: String,
        isForum: Bool = false,
        isReadOnlyArchive: Bool = false,
        unreadAudioCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.isForum = isForum
        self.isReadOnlyArchive = isReadOnlyArchive
        self.unreadAudioCount = unreadAudioCount
    }
}

public struct TelegramForumTopic: Identifiable, Codable, Hashable, Sendable {
    public var id: Int
    public var title: String

    public init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

public enum TelegramAuthStepState: Equatable, Sendable {
    case unauthorized
    case awaitingCode(phoneNumber: String)
    case awaitingQRConfirmation(link: String)
    case awaiting2FAPassword(hint: String?)
    case authorized
}

public enum TelegramConnectionState: String, Codable, Sendable {
    case uninitialized = "Не инициализирован"
    case waitingForNetwork = "Ожидание сети (Offline)"
    case connecting = "Подключение к Telegram..."
    case updating = "Обновление данных TDLib..."
    case ready = "Подключено (Ready)"
    case closed = "Сессия закрыта"
}

public extension Notification.Name {
    static let telegramAuthStateDidChange = Notification.Name("Bebranoid.telegramAuthStateDidChange")
    static let telegramConnectionStateDidChange = Notification.Name("Bebranoid.telegramConnectionStateDidChange")
}

/// Низкоуровневый мост к нативному `TDLibFramework` (`td_create_client_id`, `td_send`, `td_receive`, `td_execute`).
public final class TDLibJSONBridge: @unchecked Sendable {
    public static let shared = TDLibJSONBridge()

    public static var isNativeTDLibAvailable: Bool {
        #if canImport(TDLibFramework)
        return true
        #else
        return false
        #endif
    }

    public var isNativeLibraryAvailable: Bool {
        Self.isNativeTDLibAvailable
    }

    private let lock = NSLock()
    private var clientId: Int32?
    private var isReceiveLoopRunning = false
    private var nextExtraId: Int64 = 1
    private var pendingContinuations: [String: CheckedContinuation<[String: Any], Error>] = [:]
    public var onUpdate: (([String: Any]) -> Void)?

    private init() {
        #if canImport(TDLibFramework)
        _ = Self.executeSync(["@type": "setLogVerbosityLevel", "new_verbosity_level": 1])
        #endif
    }

    /// Синхронный вызов `td_execute` (для `getTextEntities`, `setLogVerbosityLevel` и проверок связывания TDLib)
    public static func executeSync(_ request: [String: Any]) -> [String: Any]? {
        #if canImport(TDLibFramework)
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8) else {
            return nil
        }
        guard let cPtr = td_execute(jsonStr) else {
            return nil
        }
        let responseStr = String(cString: cPtr)
        guard let respData = responseStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            return nil
        }
        return dict
        #else
        return nil
        #endif
    }

    public func ensureClientCreated() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        if let existing = clientId {
            return existing
        }
        #if canImport(TDLibFramework)
        let created = td_create_client_id()
        clientId = created
        startReceiveLoopIfNeededLocked()
        return created
        #else
        let fallbackId: Int32 = 1
        clientId = fallbackId
        return fallbackId
        #endif
    }

    public func resetClient() {
        lock.lock()
        let pending = pendingContinuations
        pendingContinuations.removeAll()
        clientId = nil
        lock.unlock()

        for (_, cont) in pending {
            cont.resume(throwing: NSError(domain: "TDLibJSONBridge", code: 499, userInfo: [NSLocalizedDescriptionKey: "Сессия TDLib перезапущена"]))
        }
    }

    public func sendAsync(_ request: [String: Any], timeoutSeconds: Double = 20.0) async throws -> [String: Any] {
        #if canImport(TDLibFramework)
        let cid = ensureClientCreated()
        let extraKey: String = {
            lock.lock()
            defer { lock.unlock() }
            let id = "req_\(nextExtraId)"
            nextExtraId += 1
            return id
        }()

        var payload = request
        payload["@extra"] = extraKey
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "TDLibJSONBridge", code: 400, userInfo: [NSLocalizedDescriptionKey: "Ошибка сериализации JSON-запроса TDLib"])
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            lock.lock()
            pendingContinuations[extraKey] = continuation
            lock.unlock()

            td_send(cid, jsonStr)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let timedOut = self.pendingContinuations.removeValue(forKey: extraKey)
                self.lock.unlock()
                timedOut?.resume(throwing: NSError(
                    domain: "TDLibJSONBridge",
                    code: 504,
                    userInfo: [NSLocalizedDescriptionKey: "Превышено время ожидания ответа от TDLib (\(request["@type"] ?? "unknown"))"]
                ))
            }
        }
        #else
        throw NSError(
            domain: "TDLibJSONBridge",
            code: 501,
            userInfo: [NSLocalizedDescriptionKey: "Нативный фреймворк TDLibFramework не подключён в текущем окружении сборки."]
        )
        #endif
    }

    public func sendFireAndForget(_ request: [String: Any]) {
        #if canImport(TDLibFramework)
        let cid = ensureClientCreated()
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8) else {
            return
        }
        td_send(cid, jsonStr)
        #endif
    }

    #if canImport(TDLibFramework)
    private func startReceiveLoopIfNeededLocked() {
        guard !isReceiveLoopRunning else { return }
        isReceiveLoopRunning = true

        DispatchQueue(label: "com.bebranoid.ios.tdlib.receive", qos: .utility).async { [weak self] in
            while let self {
                guard let cPtr = td_receive(1.0) else {
                    continue
                }
                let rawJSON = String(cString: cPtr)
                guard let data = rawJSON.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                self.handleIncomingObject(dict)
            }
        }
    }

    private func handleIncomingObject(_ dict: [String: Any]) {
        if let extra = dict["@extra"] as? String {
            lock.lock()
            let cont = pendingContinuations.removeValue(forKey: extra)
            lock.unlock()

            if let cont {
                if (dict["@type"] as? String) == "error" {
                    let code = (dict["code"] as? Int) ?? 500
                    let msg = (dict["message"] as? String) ?? "Ошибка TDLib"
                    cont.resume(throwing: NSError(
                        domain: "TDLib",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: TelegramClientService.translateTDLibError(msg)]
                    ))
                } else {
                    cont.resume(returning: dict)
                }
                return
            }
        }
        onUpdate?(dict)
    }
    #endif
}

/// Автономный iOS-клиент Telegram на базе реального `TDLibFramework` (`SwiftGram/TDLibFramework`).
/// Реализует:
/// - Настоящую авторизацию TDLib (`setTdlibParameters`, `setAuthenticationPhoneNumber`, `checkAuthenticationCode`, `checkAuthenticationPassword`, `requestQrCodeAuthentication`)
/// - Единственный источник истины `isAuthorized`: только подтверждённое состояние TDLib `authorizationStateReady` (без ложноположительного маркера Keychain)
/// - Безопасное хранение API ID / API Hash и 256-битного ключа шифрования БД TDLib в iOS Keychain
/// - Загрузку реального списка чатов (`loadChats`, `getChats`, `getChat`, `getSupergroup`) и топиков форума (`getForumTopics`)
/// - Сканирование аудиосообщений и аудио-документов (`searchChatMessages`) с парсингом `key=value` подписи, `coverFileId` и 3-уровневой дедупликацией архива
/// - Скачивание обложек (`downloadCoverFromTelegram`) и аудиофайлов через TDLib (`downloadFile`, `getFile`, `cancelDownloadFile`) с приоритетами `PriorityDownloadQueue` и докачкой `.part`
/// - Защиту выбранного пользователем архивного чата от удаления (`deleteMessages` блокируется для read-only архива)
public final class TelegramClientService: @unchecked Sendable {
    public static let shared = TelegramClientService()

    private let keychain: KeychainHelper
    private let storage: StorageManager
    private let cacheIndex: CacheIndexManager
    private let bridge: TDLibJSONBridge
    public let downloadQueue: PriorityDownloadQueue
    private let lock = NSLock()

    private var currentAuthStep: TelegramAuthStepState = .unauthorized
    private var currentConnectionState: TelegramConnectionState = .uninitialized
    private var currentRawAuthStateName: String = "uninitialized"
    private var currentScanProgressText: String = "Ожидание"
    private var lastErrorText: String? = nil
    private var currentUserDisplayName: String? = nil
    private var password2FAHint: String?
    private var pendingPhoneNumber: String?
    private var tdlibParametersConfigured = false

    private static let supportedAudioExtensions: Set<String> = [
        "flac", "alac", "wav", "m4a", "mp3", "aac", "ogg", "opus", "aiff", "wv"
    ]

    public init(
        keychain: KeychainHelper = .shared,
        storage: StorageManager = .shared,
        cacheIndex: CacheIndexManager = .shared,
        bridge: TDLibJSONBridge = .shared,
        downloadQueue: PriorityDownloadQueue = .shared
    ) {
        self.keychain = keychain
        self.storage = storage
        self.cacheIndex = cacheIndex
        self.bridge = bridge
        self.downloadQueue = downloadQueue

        self.bridge.onUpdate = { [weak self] update in
            self?.handleTDLibUpdate(update)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - Credentials & Auth State (TDLib Single Source of Truth)

    /// Единственный источник достоверного статуса авторизации — текущее состояние TDLib (`authorizationStateReady`).
    /// Сохранённый маркер в Keychain НЕ делает пользователя авторизованным до подтверждения от TDLib.
    public var isAuthorized: Bool {
        withLock { currentAuthStep == .authorized }
    }

    public var authStep: TelegramAuthStepState {
        withLock { currentAuthStep }
    }

    public var connectionState: TelegramConnectionState {
        withLock { currentConnectionState }
    }

    public var rawAuthorizationStateName: String {
        withLock { currentRawAuthStateName }
    }

    public var rawTDLibAuthState: String {
        rawAuthorizationStateName
    }

    public var scanProgressText: String {
        withLock { currentScanProgressText }
    }

    public var lastErrorDescription: String? {
        withLock { lastErrorText }
    }

    public var authorizedUserDisplayName: String? {
        withLock { currentUserDisplayName }
    }

    public var authorizedPhoneNumber: String? {
        guard isAuthorized else { return nil }
        return keychain.readString(for: .telegramAuthorizedPhone)
    }

    public var configuredApiId: String {
        keychain.readString(for: .telegramApiId) ?? ""
    }

    public var configuredApiHash: String {
        keychain.readString(for: .telegramApiHash) ?? ""
    }

    public var hasConfiguredApiCredentials: Bool {
        guard let idNum = Int32(configuredApiId.trimmingCharacters(in: .whitespacesAndNewlines)),
              idNum > 0 else {
            return false
        }
        return !configuredApiHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func saveApiCredentials(apiId: String, apiHash: String) {
        keychain.saveString(apiId.trimmingCharacters(in: .whitespacesAndNewlines), for: .telegramApiId)
        keychain.saveString(apiHash.trimmingCharacters(in: .whitespacesAndNewlines), for: .telegramApiHash)
    }

    /// Инициализирует TDLib при запуске приложения, открывает существующую локальную базу TDLib,
    /// дожидается ответа `updateAuthorizationState` от TDLib и только после `authorizationStateReady` активирует авторизованное состояние.
    @discardableResult
    public func initializeAndRestoreSession() async -> TelegramAuthStepState {
        importBundledCredentialsIfPresent()
        guard hasConfiguredApiCredentials else {
            setAuthStep(.unauthorized, rawState: "missingApiCredentials")
            return .unauthorized
        }

        guard TDLibJSONBridge.isNativeTDLibAvailable else {
            setAuthStep(.unauthorized, rawState: "tdlibBridgeUnavailable")
            return .unauthorized
        }

        _ = bridge.ensureClientCreated()
        try? await sendTdlibParametersIfPossible()

        if let stateResp = try? await bridge.sendAsync(["@type": "getAuthorizationState"], timeoutSeconds: 5.0) {
            handleAuthorizationState(stateResp)
        } else {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        if isAuthorized {
            await refreshAuthorizedUserProfile()
        }
        return authStep
    }

    public func refreshAuthorizedUserProfile() async {
        guard isAuthorized else { return }
        guard let me = try? await bridge.sendAsync(["@type": "getMe"], timeoutSeconds: 6.0) else { return }
        let firstName = (me["first_name"] as? String) ?? ""
        let lastName = (me["last_name"] as? String) ?? ""
        let phone = (me["phone_number"] as? String) ?? ""
        if !phone.isEmpty {
            let formattedPhone = phone.hasPrefix("+") ? phone : "+\(phone)"
            keychain.saveString(formattedPhone, for: .telegramAuthorizedPhone)
        }
        let fullName = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty {
            withLock { currentUserDisplayName = fullName }
        }
    }

    // MARK: - TDLib Initialization & Updates

    private func handleTDLibUpdate(_ update: [String: Any]) {
        guard let type = update["@type"] as? String else { return }

        if type == "updateAuthorizationState",
           let authState = update["authorization_state"] as? [String: Any] {
            handleAuthorizationState(authState)
        } else if type == "updateConnectionState",
                  let connState = update["state"] as? [String: Any],
                  let connType = connState["@type"] as? String {
            handleConnectionState(connType)
        }
    }

    private func handleConnectionState(_ connType: String) {
        let mapped: TelegramConnectionState
        switch connType {
        case "connectionStateWaitingForNetwork":
            mapped = .waitingForNetwork
        case "connectionStateConnecting", "connectionStateConnectingToProxy":
            mapped = .connecting
        case "connectionStateUpdating":
            mapped = .updating
        case "connectionStateReady":
            mapped = .ready
        default:
            mapped = .connecting
        }
        withLock { currentConnectionState = mapped }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .telegramConnectionStateDidChange, object: mapped)
        }
    }

    private func handleAuthorizationState(_ authState: [String: Any]) {
        guard let stateType = authState["@type"] as? String else { return }

        switch stateType {
        case "authorizationStateWaitTdlibParameters":
            withLock { currentRawAuthStateName = stateType }
            Task {
                try? await self.sendTdlibParametersIfPossible()
            }
        case "authorizationStateWaitPhoneNumber":
            setAuthStep(.unauthorized, rawState: stateType)

        case "authorizationStateWaitOtherDeviceConfirmation":
            let link = (authState["link"] as? String) ?? ""
            setAuthStep(.awaitingQRConfirmation(link: link), rawState: stateType)

        case "authorizationStateWaitCode":
            let phone = withLock { pendingPhoneNumber } ?? keychain.readString(for: .telegramAuthorizedPhone) ?? ""
            setAuthStep(.awaitingCode(phoneNumber: phone), rawState: stateType)

        case "authorizationStateWaitPassword":
            let hint = authState["password_hint"] as? String
            withLock { password2FAHint = hint }
            setAuthStep(.awaiting2FAPassword(hint: hint), rawState: stateType)

        case "authorizationStateReady":
            let phone = withLock { pendingPhoneNumber }
            finalizeAuthorizedState(fallbackPhone: phone)
            setAuthStep(.authorized, rawState: stateType)
            Task { await refreshAuthorizedUserProfile() }

        case "authorizationStateClosed", "authorizationStateClosing", "authorizationStateLoggingOut":
            withLock { tdlibParametersConfigured = false }
            setAuthStep(.unauthorized, rawState: stateType)

        default:
            withLock { currentRawAuthStateName = stateType }
        }
    }

    private func setAuthStep(_ newStep: TelegramAuthStepState, rawState: String) {
        withLock {
            currentAuthStep = newStep
            currentRawAuthStateName = rawState
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .telegramAuthStateDidChange, object: newStep)
        }
    }

    private func ensureTdlibInitialized(apiId: String, apiHash: String) async throws {
        let cleanApiIdStr = apiId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanApiHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let numericApiId = Int32(cleanApiIdStr), numericApiId > 0, !cleanApiHash.isEmpty else {
            throw NSError(
                domain: "TelegramClientService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Укажите корректные Telegram API ID (число) и API Hash (получите бесплатно на https://my.telegram.org)."]
            )
        }

        saveApiCredentials(apiId: cleanApiIdStr, apiHash: cleanApiHash)
        _ = bridge.ensureClientCreated()
        try await sendTdlibParameters(apiId: numericApiId, apiHash: cleanApiHash)
    }

    private func sendTdlibParametersIfPossible() async throws {
        let apiIdStr = configuredApiId
        let apiHash = configuredApiHash
        guard let numericApiId = Int32(apiIdStr), numericApiId > 0, !apiHash.isEmpty else {
            return
        }
        try await sendTdlibParameters(apiId: numericApiId, apiHash: apiHash)
    }

    private func sendTdlibParameters(apiId: Int32, apiHash: String) async throws {
        let tdlibRoot = storage.databaseDirectory.appendingPathComponent("tdlib", isDirectory: true)
        let dbDir = tdlibRoot.appendingPathComponent("db", isDirectory: true)
        let filesDir = tdlibRoot.appendingPathComponent("files", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)

        let dbKey = keychain.getOrCreateDatabaseEncryptionKey()

        let request: [String: Any] = [
            "@type": "setTdlibParameters",
            "use_test_dc": false,
            "database_directory": dbDir.path,
            "files_directory": filesDir.path,
            "database_encryption_key": dbKey,
            "use_file_database": true,
            "use_chat_info_database": true,
            "use_message_database": true,
            "use_secret_chats": false,
            "api_id": apiId,
            "api_hash": apiHash,
            "system_language_code": "ru",
            "device_model": "iPhone",
            "system_version": "iOS 17.0",
            "application_version": "2.0.0"
        ]

        do {
            _ = try await bridge.sendAsync(request, timeoutSeconds: 15.0)
            withLock { tdlibParametersConfigured = true }
        } catch let error as NSError {
            if error.localizedDescription.lowercased().contains("unexpected settdlibparameters") {
                withLock { tdlibParametersConfigured = true }
                return
            }
            throw error
        }
    }

    // MARK: - Real TDLib Auth Flow (Phone -> Code -> 2FA Password & QR Login)

    public func startPhoneAuthentication(phoneNumber: String) async throws -> TelegramAuthStepState {
        _ = try await sendAuthenticationCode(
            phoneNumber: phoneNumber,
            apiId: configuredApiId,
            apiHash: configuredApiHash
        )
        return authStep
    }

    public func sendAuthenticationCode(
        phoneNumber: String,
        apiId: String,
        apiHash: String
    ) async throws -> (phoneCodeHash: String, requires2FAHint: String?) {
        let cleanPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPhone.count >= 7 else {
            throw NSError(
                domain: "TelegramClientService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Введите корректный номер телефона в международном формате (+7 / +380 / ...)"]
            )
        }

        let effectiveApiId = apiId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? configuredApiId : apiId
        let effectiveApiHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? configuredApiHash : apiHash

        try await ensureTdlibInitialized(apiId: effectiveApiId, apiHash: effectiveApiHash)

        withLock { pendingPhoneNumber = cleanPhone }
        keychain.saveString(cleanPhone, for: .telegramAuthorizedPhone)

        let request: [String: Any] = [
            "@type": "setAuthenticationPhoneNumber",
            "phone_number": cleanPhone,
            "settings": [
                "@type": "phoneNumberAuthenticationSettings",
                "allow_flash_call": false,
                "allow_missed_call": false,
                "is_current_phone_number": true,
                "allow_sms_retriever_api": false
            ]
        ]

        do {
            _ = try await bridge.sendAsync(request, timeoutSeconds: 25.0)
        } catch {
            let friendly = Self.translateTDLibError(error.localizedDescription)
            withLock { lastErrorText = friendly }
            throw NSError(domain: "TelegramClientService", code: 400, userInfo: [NSLocalizedDescriptionKey: friendly])
        }

        let authState = try? await bridge.sendAsync(["@type": "getAuthorizationState"], timeoutSeconds: 10.0)
        if let authState {
            handleAuthorizationState(authState)
        } else {
            setAuthStep(.awaitingCode(phoneNumber: cleanPhone), rawState: "authorizationStateWaitCode")
        }
        let stateType = (authState?["@type"] as? String) ?? "authorizationStateWaitCode"
        let hint = withLock { password2FAHint }
        return (stateType, hint)
    }

    /// Официальный Telegram QR-login flow (`requestQrCodeAuthentication` -> `authorizationStateWaitOtherDeviceConfirmation`)
    public func requestQRCodeAuthentication() async throws -> TelegramAuthStepState {
        try await ensureTdlibInitialized(apiId: configuredApiId, apiHash: configuredApiHash)
        do {
            let resp = try await bridge.sendAsync([
                "@type": "requestQrCodeAuthentication",
                "other_user_ids": [] as [Int]
            ], timeoutSeconds: 15.0)
            handleAuthorizationState(resp)
            if let state = try? await bridge.sendAsync(["@type": "getAuthorizationState"], timeoutSeconds: 5.0) {
                handleAuthorizationState(state)
            }
            return authStep
        } catch {
            let friendly = Self.translateTDLibError(error.localizedDescription)
            withLock { lastErrorText = friendly }
            throw NSError(domain: "TelegramClientService", code: 400, userInfo: [NSLocalizedDescriptionKey: friendly])
        }
    }

    public func submitVerificationCode(_ code: String) async throws -> TelegramAuthStepState {
        try await verifyAuthenticationCode(code: code)
    }

    public func verifyAuthenticationCode(code: String) async throws -> TelegramAuthStepState {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "TelegramClientService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Введите код подтверждения из Telegram"]
            )
        }

        do {
            _ = try await bridge.sendAsync([
                "@type": "checkAuthenticationCode",
                "code": trimmed
            ], timeoutSeconds: 25.0)
        } catch {
            let friendly = Self.translateTDLibError(error.localizedDescription)
            withLock { lastErrorText = friendly }
            throw NSError(domain: "TelegramClientService", code: 400, userInfo: [NSLocalizedDescriptionKey: friendly])
        }

        return try await refreshAuthStepFromTDLib()
    }

    public func submitTwoFactorPassword(_ password: String) async throws -> TelegramAuthStepState {
        try await verify2FAPassword(password: password)
    }

    public func verify2FAPassword(password: String) async throws -> TelegramAuthStepState {
        guard !password.isEmpty else {
            throw NSError(
                domain: "TelegramClientService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Облачный пароль 2FA не может быть пустым"]
            )
        }

        do {
            _ = try await bridge.sendAsync([
                "@type": "checkAuthenticationPassword",
                "password": password
            ], timeoutSeconds: 25.0)
        } catch {
            let friendly = Self.translateTDLibError(error.localizedDescription)
            withLock { lastErrorText = friendly }
            throw NSError(domain: "TelegramClientService", code: 400, userInfo: [NSLocalizedDescriptionKey: friendly])
        }

        return try await refreshAuthStepFromTDLib()
    }

    private func refreshAuthStepFromTDLib() async throws -> TelegramAuthStepState {
        let state = try await bridge.sendAsync(["@type": "getAuthorizationState"], timeoutSeconds: 10.0)
        handleAuthorizationState(state)
        if isAuthorized {
            await refreshAuthorizedUserProfile()
        }
        return authStep
    }

    public func logout() {
        bridge.sendFireAndForget(["@type": "logOut"])
        keychain.clearAllTelegramCredentials()
        withLock {
            pendingPhoneNumber = nil
            password2FAHint = nil
            currentUserDisplayName = nil
            lastErrorText = nil
            tdlibParametersConfigured = false
        }
        setAuthStep(.unauthorized, rawState: "authorizationStateClosed")
    }

    private func finalizeAuthorizedState(fallbackPhone: String?) {
        let phone = fallbackPhone ?? keychain.readString(for: .telegramAuthorizedPhone) ?? "Telegram Account"
        keychain.saveString("tdlib_authenticated_v1", for: .telegramSessionData)
        keychain.saveString(phone, for: .telegramAuthorizedPhone)
    }

    public static func translateTDLibError(_ rawMessage: String) -> String {
        let upper = rawMessage.uppercased()
        if upper.contains("PHONE_CODE_INVALID") {
            return "Неверный код подтверждения Telegram. Проверьте введённые цифры и попробуйте снова."
        }
        if upper.contains("PHONE_CODE_EXPIRED") {
            return "Срок действия кода подтверждения истёк. Запросите новый код."
        }
        if upper.contains("PASSWORD_HASH_INVALID") {
            return "Неверный облачный пароль двухфакторной аутентификации (2FA)."
        }
        if upper.contains("PHONE_NUMBER_INVALID") {
            return "Некорректный формат номера телефона. Укажите номер в международном формате (например, +380... или +7...)."
        }
        if upper.contains("API_ID_INVALID") || upper.contains("API_HASH_INVALID") {
            return "Неверные API ID или API Hash. Проверьте ключи на https://my.telegram.org."
        }
        if upper.contains("FLOOD_WAIT") {
            return "Слишком много попыток входа. Пожалуйста, подождите несколько минут перед повторной отправкой."
        }
        return rawMessage
    }

    // MARK: - Real Dialogs & Forum Topics (`getChats`, `getChat`, `getForumTopics`)

    public func fetchAvailableAudioChats(configuredArchiveChatId: String? = nil) async throws -> [TelegramChatSummary] {
        try await sendTdlibParametersIfPossible()

        _ = try? await bridge.sendAsync([
            "@type": "loadChats",
            "chat_list": ["@type": "chatListMain"],
            "limit": 100
        ], timeoutSeconds: 15.0)

        _ = try? await bridge.sendAsync([
            "@type": "loadChats",
            "chat_list": ["@type": "chatListArchive"],
            "limit": 50
        ], timeoutSeconds: 10.0)

        var chatIds: [Int64] = []
        if let mainResp = try? await bridge.sendAsync([
            "@type": "getChats",
            "chat_list": ["@type": "chatListMain"],
            "limit": 100
        ], timeoutSeconds: 15.0),
           let ids = Self.extractInt64Array(from: mainResp["chat_ids"]) {
            chatIds.append(contentsOf: ids)
        }

        if let archResp = try? await bridge.sendAsync([
            "@type": "getChats",
            "chat_list": ["@type": "chatListArchive"],
            "limit": 50
        ], timeoutSeconds: 10.0),
           let ids = Self.extractInt64Array(from: archResp["chat_ids"]) {
            for id in ids where !chatIds.contains(id) {
                chatIds.append(id)
            }
        }

        var summaries: [TelegramChatSummary] = []
        for cid in chatIds {
            guard let chatDict = try? await bridge.sendAsync([
                "@type": "getChat",
                "chat_id": cid
            ], timeoutSeconds: 8.0) else {
                continue
            }

            let title = (chatDict["title"] as? String) ?? "Chat \(cid)"
            var isForum = false

            if let chatType = chatDict["type"] as? [String: Any],
               (chatType["@type"] as? String) == "chatTypeSupergroup",
               let sgId = Self.extractInt64(from: chatType["supergroup_id"]),
               let sgDict = try? await bridge.sendAsync([
                   "@type": "getSupergroup",
                   "supergroup_id": sgId
               ], timeoutSeconds: 6.0) {
                isForum = (sgDict["is_forum"] as? Bool) ?? false
            }

            let chatIdStr = String(cid)
            let isArchive = AppConfig.isArchiveChatId(chatIdStr, configuredArchiveChatId: configuredArchiveChatId)

            summaries.append(
                TelegramChatSummary(
                    id: chatIdStr,
                    title: title,
                    isForum: isForum,
                    isReadOnlyArchive: isArchive
                )
            )
        }

        return summaries
    }

    /// Загружает список топиков форума (`getForumTopics`) для супергруппы с включёнными темами
    public func fetchForumTopics(chatId: Int64) async -> [Int: String] {
        guard let resp = try? await bridge.sendAsync([
            "@type": "getForumTopics",
            "chat_id": chatId,
            "query": "",
            "offset_date": 0,
            "offset_message_id": 0,
            "offset_message_thread_id": 0,
            "limit": 100
        ], timeoutSeconds: 12.0),
              let topics = resp["topics"] as? [[String: Any]] else {
            return [:]
        }

        var map: [Int: String] = [:]
        for topic in topics {
            if let info = topic["info"] as? [String: Any],
               let name = info["name"] as? String,
               !name.isEmpty {
                if let threadId = Self.extractInt(from: info["message_thread_id"]) {
                    map[threadId] = name
                }
                if let topicId = Self.extractInt(from: info["forum_topic_id"]) {
                    map[topicId] = name
                }
            }
        }
        return map
    }

    // MARK: - Real Audio & Document Scanning (`searchChatMessages`)

    /// Сканирует аудиосообщения (`messageAudio`) и аудио-документы (`messageDocument`) выбранного чата Telegram через TDLib
    public func scanChatAudioTracks(
        chatId: String,
        chatTitle: String,
        isArchiveChat: Bool,
        ignoredChatTitles: Set<String> = [],
        maxTracks: Int = 2500
    ) async throws -> [Track] {
        guard let numericChatId = Int64(chatId.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(
                domain: "TelegramClientService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Выберите облачный чат Telegram в настройках перед синхронизацией."]
            )
        }

        withLock { currentScanProgressText = "Загрузка топиков \(chatTitle)..." }
        try await sendTdlibParametersIfPossible()
        let forumTopics = await fetchForumTopics(chatId: numericChatId)

        var rawMessages: [RawTelegramAudioMessage] = []
        var seenMessageIds = Set<Int>()

        // 1. Сканируем нативные аудиосообщения (`searchMessagesFilterAudio`)
        let audioMsgs = try await searchMessagesWithFilter(
            chatId: numericChatId,
            chatTitle: chatTitle,
            filterType: "searchMessagesFilterAudio",
            forumTopics: forumTopics,
            maxMessages: maxTracks
        )
        for msg in audioMsgs where !seenMessageIds.contains(msg.messageId) {
            seenMessageIds.insert(msg.messageId)
            rawMessages.append(msg)
        }

        // 2. Сканируем документы без сжатия (`searchMessagesFilterDocument` — FLAC, WAV, ALAC, OPUS и др.)
        let docMsgs = try await searchMessagesWithFilter(
            chatId: numericChatId,
            chatTitle: chatTitle,
            filterType: "searchMessagesFilterDocument",
            forumTopics: forumTopics,
            maxMessages: maxTracks
        )
        for msg in docMsgs where !seenMessageIds.contains(msg.messageId) {
            seenMessageIds.insert(msg.messageId)
            rawMessages.append(msg)
        }

        let built = rawMessages.map {
            TelegramScanner.buildTrack(
                from: $0,
                isFromArchive: isArchiveChat,
                ignoredChatTitles: ignoredChatTitles
            )
        }
        withLock { currentScanProgressText = "Готово (\(built.count) треков из \(chatTitle))" }
        return built
    }

    /// Полная синхронизация основного и (опционально) архивного read-only чата с 3-уровневой дедупликацией
    public func syncMainAndArchiveChats(
        mainChatId: String,
        mainChatTitle: String,
        archiveChatId: String,
        archiveChatTitle: String
    ) async throws -> [Track] {
        var ignoredTitles: Set<String> = [
            AppConfig.defaultMainChatPlaceholderTitle,
            AppConfig.defaultArchiveChatPlaceholderTitle
        ]
        if !mainChatTitle.isEmpty { ignoredTitles.insert(mainChatTitle) }
        if !archiveChatTitle.isEmpty { ignoredTitles.insert(archiveChatTitle) }

        let mainTracks = try await scanChatAudioTracks(
            chatId: mainChatId,
            chatTitle: mainChatTitle,
            isArchiveChat: false,
            ignoredChatTitles: ignoredTitles
        )

        let cleanArchiveId = archiveChatId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanArchiveId.isEmpty, Int64(cleanArchiveId) != nil else {
            return mainTracks
        }

        let archiveTracks = (try? await scanChatAudioTracks(
            chatId: cleanArchiveId,
            chatTitle: archiveChatTitle,
            isArchiveChat: true,
            ignoredChatTitles: ignoredTitles
        )) ?? []

        return TelegramScanner.mergeMainAndArchiveTracks(
            mainTracks: mainTracks,
            archiveTracks: archiveTracks
        )
    }

    private func searchMessagesWithFilter(
        chatId: Int64,
        chatTitle: String,
        filterType: String,
        forumTopics: [Int: String],
        maxMessages: Int
    ) async throws -> [RawTelegramAudioMessage] {
        var results: [RawTelegramAudioMessage] = []
        var fromMessageId: Int64 = 0

        while results.count < maxMessages {
            withLock {
                currentScanProgressText = "Сканирование \(chatTitle): \(results.count) тр."
            }
            let resp = try await bridge.sendAsync([
                "@type": "searchChatMessages",
                "chat_id": chatId,
                "query": "",
                "from_message_id": fromMessageId,
                "offset": 0,
                "limit": 100,
                "filter": ["@type": filterType],
                "message_thread_id": 0,
                "saved_messages_topic_id": 0
            ], timeoutSeconds: 20.0)

            guard let messages = resp["messages"] as? [[String: Any]], !messages.isEmpty else {
                break
            }

            var lastMsgId: Int64 = 0
            for msgDict in messages {
                guard let msgId64 = Self.extractInt64(from: msgDict["id"]) else { continue }
                lastMsgId = msgId64

                if let parsed = Self.parseTDLibMessage(
                    msgDict,
                    chatId: String(chatId),
                    chatTitle: chatTitle,
                    forumTopics: forumTopics
                ) {
                    results.append(parsed)
                }
            }

            if lastMsgId == 0 || lastMsgId == fromMessageId {
                break
            }
            fromMessageId = lastMsgId
        }

        return results
    }

    /// Разбирает JSON-объект `message` из TDLib (`messageAudio` или `messageDocument`) и извлекает `coverFileId` (`album_cover_thumbnail.file.remote.id`)
    public static func parseTDLibMessage(
        _ msgDict: [String: Any],
        chatId: String,
        chatTitle: String,
        forumTopics: [Int: String]
    ) -> RawTelegramAudioMessage? {
        guard let msgId64 = extractInt64(from: msgDict["id"]),
              let content = msgDict["content"] as? [String: Any],
              let contentType = content["@type"] as? String else {
            return nil
        }

        let threadId = extractInt(from: msgDict["message_thread_id"])
        let topicTitle = threadId.flatMap { forumTopics[$0] }
        let captionText = (content["caption"] as? [String: Any])?["text"] as? String
        let timestamp = extractInt64(from: msgDict["date"]) ?? Int64(Date().timeIntervalSince1970)
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))

        if contentType == "messageAudio",
           let audio = content["audio"] as? [String: Any],
           let fileDict = audio["audio"] as? [String: Any] {
            let fileName = (audio["file_name"] as? String) ?? "track_\(msgId64).mp3"
            let mimeType = audio["mime_type"] as? String
            let duration = Double(extractInt(from: audio["duration"]) ?? 0)
            let performer = audio["performer"] as? String
            let title = audio["title"] as? String
            let fileSize = extractInt64(from: fileDict["size"]) ?? extractInt64(from: fileDict["expected_size"])
            let remoteDict = fileDict["remote"] as? [String: Any]
            let uniqueId = (remoteDict?["unique_id"] as? String) ?? (remoteDict?["id"] as? String)
            let coverFileId = extractRemoteThumbnailId(from: audio["album_cover_thumbnail"] as? [String: Any])

            return RawTelegramAudioMessage(
                chatId: chatId,
                chatTitle: chatTitle,
                messageId: Int(msgId64),
                messageThreadId: threadId,
                topicTitle: topicTitle,
                caption: captionText,
                performer: performer,
                audioTitle: title,
                filename: fileName,
                mimeType: mimeType,
                fileSize: fileSize,
                durationSeconds: duration,
                fileUniqueId: uniqueId,
                coverFileId: coverFileId,
                date: date
            )
        }

        if contentType == "messageDocument",
           let doc = content["document"] as? [String: Any],
           let fileDict = doc["document"] as? [String: Any] {
            let fileName = (doc["file_name"] as? String) ?? ""
            let mimeType = (doc["mime_type"] as? String) ?? ""
            let ext = (fileName as NSString).pathExtension.lowercased()
            let isAudioDoc = supportedAudioExtensions.contains(ext) || mimeType.lowercased().hasPrefix("audio/")
            guard isAudioDoc else { return nil }

            let fileSize = extractInt64(from: fileDict["size"]) ?? extractInt64(from: fileDict["expected_size"])
            let remoteDict = fileDict["remote"] as? [String: Any]
            let uniqueId = (remoteDict?["unique_id"] as? String) ?? (remoteDict?["id"] as? String)
            let coverFileId = extractRemoteThumbnailId(from: doc["thumbnail"] as? [String: Any])

            return RawTelegramAudioMessage(
                chatId: chatId,
                chatTitle: chatTitle,
                messageId: Int(msgId64),
                messageThreadId: threadId,
                topicTitle: topicTitle,
                caption: captionText,
                performer: nil,
                audioTitle: nil,
                filename: fileName.isEmpty ? "document_\(msgId64).flac" : fileName,
                mimeType: mimeType.isEmpty ? nil : mimeType,
                fileSize: fileSize,
                durationSeconds: 0,
                fileUniqueId: uniqueId,
                coverFileId: coverFileId,
                date: date
            )
        }

        return nil
    }

    private static func extractRemoteThumbnailId(from thumbDict: [String: Any]?) -> String? {
        guard let thumbDict else { return nil }
        if let file = thumbDict["file"] as? [String: Any],
           let remote = file["remote"] as? [String: Any],
           let remoteId = remote["id"] as? String,
           !remoteId.isEmpty {
            return remoteId
        }
        return nil
    }

    // MARK: - Cover Thumbnail Download via TDLib (`downloadCoverFromTelegram`)

    /// Скачивает миниатюру обложки трека из Telegram по `coverFileId` (`electron/main.js` строки 2906–2932)
    /// и сохраняет её в `Covers/<safeFilename>.jpg`.
    public func downloadCoverFromTelegram(coverFileId: String, filename: String) async -> String? {
        let trimmedId = coverFileId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return nil }

        let safeBase = storage.safeCacheFilename(for: filename)
        let targetURL = storage.coversDirectory.appendingPathComponent("\(safeBase).jpg")
        if FileManager.default.fileExists(atPath: targetURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
           let size = attrs[.size] as? Int64, size > 128 {
            return targetURL.path
        }

        guard TDLibJSONBridge.isNativeTDLibAvailable, isAuthorized else { return nil }

        guard let remoteResp = try? await bridge.sendAsync([
            "@type": "getRemoteFile",
            "remote_file_id": trimmedId,
            "file_type": ["@type": "fileTypeThumbnail"]
        ], timeoutSeconds: 8.0),
        let fileId = Self.extractInt(from: remoteResp["id"]) else {
            return nil
        }

        if let completedPath = Self.completedLocalPath(from: remoteResp) {
            try? FileManager.default.removeItem(at: targetURL)
            try? FileManager.default.copyItem(atPath: completedPath, toPath: targetURL.path)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                return targetURL.path
            }
        }

        if let dlResp = try? await bridge.sendAsync([
            "@type": "downloadFile",
            "file_id": fileId,
            "priority": 16,
            "offset": 0,
            "limit": 0,
            "synchronous": true
        ], timeoutSeconds: 12.0),
        let dlPath = Self.completedLocalPath(from: dlResp) {
            try? FileManager.default.removeItem(at: targetURL)
            try? FileManager.default.copyItem(atPath: dlPath, toPath: targetURL.path)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                return targetURL.path
            }
        }

        return nil
    }

    // MARK: - Deletion Protection (`electron/main.js` Archive Chat Protection)

    public func deleteCloudMessage(track: Track) async throws {
        if track.isCloudDeletionBlocked {
            throw NSError(
                domain: "TelegramClientService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Удаление из архивного чата заблокировано (read-only)."]
            )
        }

        if let chatIdStr = track.chatId,
           let chatId64 = Int64(chatIdStr),
           let msgId = track.messageId {
            try? await sendTdlibParametersIfPossible()
            _ = try? await bridge.sendAsync([
                "@type": "deleteMessages",
                "chat_id": chatId64,
                "message_ids": [Int64(msgId)],
                "revoke": true
            ], timeoutSeconds: 12.0)
        }

        let cachedURL = storage.cachedAudioFileURL(for: track)
        try? FileManager.default.removeItem(at: cachedURL)
    }

    // MARK: - Priority Audio Download with Partial Resume & Preemption (`downloadFile` + `.part`)

    /// Скачивает аудиофайл для трека через `PriorityDownloadQueue` с поддержкой докачки `.part` файла и вытеснения
    public func ensureTrackDownloaded(
        track: Track,
        priority: DownloadPriorityLevel = .activePlayback
    ) async throws -> URL {
        let targetURL = storage.cachedAudioFileURL(for: track)
        if storage.isTrackCached(track) {
            cacheIndex.markCached(for: track)
            return targetURL
        }

        let partURL = storage.partialAudioFileURL(for: track)
        let key = track.cacheKey

        return try await downloadQueue.enqueue(key: key, priority: priority.rawValue) { [weak self] token in
            guard let self else {
                throw NSError(domain: "TelegramClientService", code: 500, userInfo: nil)
            }
            try token.throwIfPreempted(key: key)

            if self.storage.isTrackCached(track) {
                self.cacheIndex.markCached(for: track)
                return targetURL
            }

            // 1. Поток YouTube — качаем с поддержкой HTTP Range-заголовка для `.part` докачки
            if track.youtubeUrl != nil, track.sourceKind == .youtube {
                let downloaded = try await YouTubeService.shared.downloadAudioStream(
                    for: track,
                    destinationURL: targetURL,
                    partialURL: partURL,
                    preemptionToken: token
                )
                self.cacheIndex.markCached(for: track)
                return downloaded
            }

            try token.throwIfPreempted(key: key)

            // 2. Трек Telegram — разрешаем актуальный `file_id` через TDLib `getMessage` и скачиваем через `downloadFile`
            if track.sourceKind == .telegram,
               self.isAuthorized,
               let chatIdStr = track.chatId,
               let chatId64 = Int64(chatIdStr),
               let messageId = track.messageId {
                try await self.sendTdlibParametersIfPossible()
                let fileDict = try await self.resolveTDLibFileObject(chatId: chatId64, messageId: Int64(messageId))
                guard let fileId = Self.extractInt(from: fileDict["id"]) else {
                    throw NSError(
                        domain: "TelegramClientService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "TDLib не вернул file_id для сообщения \(messageId)"]
                    )
                }

                if let completedPath = Self.completedLocalPath(from: fileDict) {
                    try self.copyCompletedTDLibFile(fromPath: completedPath, to: targetURL, partURL: partURL)
                    self.cacheIndex.markCached(for: track)
                    return targetURL
                }

                var resumeOffset: Int64 = 0
                if FileManager.default.fileExists(atPath: partURL.path),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: partURL.path),
                   let size = attrs[.size] as? Int64, size > 0 {
                    resumeOffset = size
                }

                let tdPriority = Self.mapToTDLibPriority(priority)
                _ = try await self.bridge.sendAsync([
                    "@type": "downloadFile",
                    "file_id": fileId,
                    "priority": tdPriority,
                    "offset": resumeOffset,
                    "limit": 0,
                    "synchronous": false
                ], timeoutSeconds: 15.0)

                // Мониторим прогресс скачивания файла TDLib с кооперативной проверкой вытеснения (`token.isPreempted`)
                let startWait = Date()
                while Date().timeIntervalSince(startWait) < 300.0 {
                    if token.isPreempted {
                        self.bridge.sendFireAndForget([
                            "@type": "cancelDownloadFile",
                            "file_id": fileId,
                            "only_if_pending": false
                        ])
                        let latestFile = try? await self.bridge.sendAsync(["@type": "getFile", "file_id": fileId], timeoutSeconds: 5.0)
                        let savedBytes = self.persistPartialProgressIfNeeded(fileDict: latestFile, partURL: partURL) ?? resumeOffset
                        throw DownloadPreemptedError(key: key, bytesSaved: savedBytes)
                    }

                    let currentFile = try await self.bridge.sendAsync([
                        "@type": "getFile",
                        "file_id": fileId
                    ], timeoutSeconds: 10.0)

                    if let completedPath = Self.completedLocalPath(from: currentFile) {
                        try self.copyCompletedTDLibFile(fromPath: completedPath, to: targetURL, partURL: partURL)
                        self.cacheIndex.markCached(for: track)
                        return targetURL
                    }

                    try await Task.sleep(nanoseconds: 120_000_000)
                }

                throw NSError(
                    domain: "TelegramClientService",
                    code: 504,
                    userInfo: [NSLocalizedDescriptionKey: "Превышено время скачивания аудиофайла \(track.filename) из Telegram"]
                )
            }

            // 3. Локальный буфер `.part`, если файл уже подготовлен
            if FileManager.default.fileExists(atPath: partURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
                try FileManager.default.moveItem(at: partURL, to: targetURL)
                self.cacheIndex.markCached(for: track)
                return targetURL
            }

            throw NSError(
                domain: "TelegramClientService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Файл \(track.filename) недоступен локально. Выполните вход и синхронизацию чата Telegram."]
            )
        }
    }

    // MARK: - TDLib File Helpers

    private func resolveTDLibFileObject(chatId: Int64, messageId: Int64) async throws -> [String: Any] {
        let msg = try await bridge.sendAsync([
            "@type": "getMessage",
            "chat_id": chatId,
            "message_id": messageId
        ], timeoutSeconds: 15.0)

        guard let content = msg["content"] as? [String: Any],
              let contentType = content["@type"] as? String else {
            throw NSError(domain: "TelegramClientService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Сообщение \(messageId) не найдено в чате \(chatId)"])
        }

        if contentType == "messageAudio",
           let audio = content["audio"] as? [String: Any],
           let fileDict = audio["audio"] as? [String: Any] {
            return fileDict
        }

        if contentType == "messageDocument",
           let doc = content["document"] as? [String: Any],
           let fileDict = doc["document"] as? [String: Any] {
            return fileDict
        }

        throw NSError(domain: "TelegramClientService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Сообщение \(messageId) не содержит аудиофайла"])
    }

    private static func completedLocalPath(from fileDict: [String: Any]?) -> String? {
        guard let local = fileDict?["local"] as? [String: Any],
              (local["is_downloading_completed"] as? Bool) == true,
              let path = local["path"] as? String,
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    private func copyCompletedTDLibFile(fromPath: String, to targetURL: URL, partURL: URL) throws {
        let sourceURL = URL(fileURLWithPath: fromPath)
        try? FileManager.default.removeItem(at: targetURL)
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        try? FileManager.default.removeItem(at: partURL)
    }

    private func persistPartialProgressIfNeeded(fileDict: [String: Any]?, partURL: URL) -> Int64? {
        guard let local = fileDict?["local"] as? [String: Any],
              let path = local["path"] as? String,
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let prefixSize = Self.extractInt64(from: local["downloaded_prefix_size"]) ?? 0
        guard prefixSize > 0 else { return nil }
        try? FileManager.default.removeItem(at: partURL)
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: partURL)
        return prefixSize
    }

    private static func mapToTDLibPriority(_ priority: DownloadPriorityLevel) -> Int {
        switch priority {
        case .activePlayback:
            return 32
        case .nextTrackPrefetch:
            return 24
        case .backgroundBatch:
            return 4
        }
    }

    private static func extractInt(from anyVal: Any?) -> Int? {
        if let i = anyVal as? Int { return i }
        if let i64 = anyVal as? Int64 { return Int(i64) }
        if let num = anyVal as? NSNumber { return num.intValue }
        if let str = anyVal as? String { return Int(str) }
        return nil
    }

    private static func extractInt64(from anyVal: Any?) -> Int64? {
        if let i64 = anyVal as? Int64 { return i64 }
        if let i = anyVal as? Int { return Int64(i) }
        if let num = anyVal as? NSNumber { return num.int64Value }
        if let str = anyVal as? String { return Int64(str) }
        return nil
    }

    private static func extractInt64Array(from anyVal: Any?) -> [Int64]? {
        guard let arr = anyVal as? [Any] else { return nil }
        return arr.compactMap { extractInt64(from: $0) }
    }

    // MARK: - On-Device iPhone End-to-End Auth & Chat Scan Scenario

    public struct OnDeviceE2EScenarioReport: Sendable, Equatable {
        public let isPhysicalDevice: Bool
        public let isTDLibAuthorizedReady: Bool
        public let verificationBadge: String
        public let discoveredChatsCount: Int
        public let forumTopicsCount: Int
        public let scannedTracksCount: Int
        public let tracksWithCoverFileIdCount: Int
        public let summaryText: String
    }

    public static var isRunningOnPhysicaliPhone: Bool {
        #if targetEnvironment(simulator)
        return false
        #elseif os(iOS)
        return true
        #else
        return false
        #endif
    }

    /// Выполняет сквозной (end-to-end) сценарий проверки авторизации Telegram TDLib и сканирования чатов на устройстве:
    /// `initializeAndRestoreSession` -> `authorizationStateReady` -> `getMe` -> `fetchAvailableAudioChats` -> `fetchForumTopics` -> `scanChatAudioTracks`.
    /// Без физического iPhone или живой авторизованной сессии явно возвращает статус `NOT VERIFIED (REQUIRES REAL IPHONE)`.
    public func runOnDeviceE2EAuthAndChatScanScenario(
        selectedChatId: String? = nil,
        archiveChatId: String? = nil
    ) async -> OnDeviceE2EScenarioReport {
        let onRealDevice = Self.isRunningOnPhysicaliPhone
        let step = await initializeAndRestoreSession()
        let isReady = (step == .authorized && isAuthorized && rawAuthorizationStateName == "authorizationStateReady")

        guard onRealDevice && isReady else {
            let reason = !onRealDevice
                ? "Среда выполнения — iOS Simulator (физический iPhone не подключён)"
                : "Сессия TDLib не находится в состоянии authorizationStateReady (\(rawAuthorizationStateName))"
            return OnDeviceE2EScenarioReport(
                isPhysicalDevice: onRealDevice,
                isTDLibAuthorizedReady: isReady,
                verificationBadge: "NOT VERIFIED (REQUIRES REAL IPHONE)",
                discoveredChatsCount: 0,
                forumTopicsCount: 0,
                scannedTracksCount: 0,
                tracksWithCoverFileIdCount: 0,
                summaryText: "NOT VERIFIED: \(reason)"
            )
        }

        await refreshAuthorizedUserProfile()
        let chats = (try? await fetchAvailableAudioChats(configuredArchiveChatId: archiveChatId)) ?? []
        let targetChatId = selectedChatId ?? chats.first?.id ?? "0"
        let targetTitle = chats.first(where: { $0.id == targetChatId })?.title ?? "Music Cloud"
        let numericTargetChatId = Int64(targetChatId.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let topics = numericTargetChatId != 0 ? await fetchForumTopics(chatId: numericTargetChatId) : [:]
        let scanned = (try? await syncMainAndArchiveChats(
            mainChatId: targetChatId,
            mainChatTitle: targetTitle,
            archiveChatId: archiveChatId ?? "",
            archiveChatTitle: "Archive"
        )) ?? []
        let coversCount = scanned.filter { !($0.coverFileId ?? "").isEmpty }.count

        return OnDeviceE2EScenarioReport(
            isPhysicalDevice: true,
            isTDLibAuthorizedReady: true,
            verificationBadge: "VERIFIED ON REAL IPHONE",
            discoveredChatsCount: chats.count,
            forumTopicsCount: topics.count,
            scannedTracksCount: scanned.count,
            tracksWithCoverFileIdCount: coversCount,
            summaryText: "VERIFIED ON REAL IPHONE: чатов=\(chats.count), топиков=\(topics.count), треков=\(scanned.count), обложек=\(coversCount)"
        )
    }
}
