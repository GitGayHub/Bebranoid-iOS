import Foundation
import Combine

/// ViewModel авторизации Telegram (`src/views/Auth.jsx` + `electron/main.js`).
/// Управляет вводом `API ID`, `API Hash`, номера телефона, кода подтверждения, QR-входа (`requestQrCodeAuthentication`) и облачного пароля 2FA.
/// Подписан на события `TelegramClientService` (`telegramAuthStateDidChange` / `telegramConnectionStateDidChange`),
/// где единственным источником статуса авторизации является `authorizationStateReady` от TDLib.
@MainActor
public final class TelegramAuthViewModel: ObservableObject {
    @Published public var apiId: String = ""
    @Published public var apiHash: String = ""
    @Published public var phoneNumber: String = ""
    @Published public var verificationCode: String = ""
    @Published public var twoFactorPassword: String = ""
    @Published public var qrCodeConfirmLink: String? = nil

    @Published public var step: TelegramAuthStepState = .unauthorized
    @Published public var connectionState: TelegramConnectionState = .uninitialized
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var twoFactorHint: String? = nil
    @Published public var codeDeliveryHint: String? = nil

    private let client: TelegramClientService
    private let keychain: KeychainHelper
    private var cancellables = Set<AnyCancellable>()
    public var onAuthSuccess: (() -> Void)?

    public init(
        client: TelegramClientService = .shared,
        keychain: KeychainHelper = .shared
    ) {
        self.client = client
        self.keychain = keychain
        client.importBundledCredentialsIfPresent()
        self.apiId = client.configuredApiId
        self.apiHash = client.configuredApiHash
        self.phoneNumber = keychain.readString(for: .telegramAuthorizedPhone) ?? ""
        self.step = client.authStep
        self.connectionState = client.connectionState

        NotificationCenter.default.publisher(for: .telegramAuthStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let newStep = note.object as? TelegramAuthStepState else { return }
                self.applyStep(newStep)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .telegramConnectionStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let newConn = note.object as? TelegramConnectionState else { return }
                self.connectionState = newConn
            }
            .store(in: &cancellables)
    }

    private func applyStep(_ newStep: TelegramAuthStepState) {
        self.step = newStep
        switch newStep {
        case .awaitingCode:
            self.codeDeliveryHint = client.codeDeliveryHint
        case .awaiting2FAPassword(let hint):
            self.twoFactorHint = hint
        case .awaitingQRConfirmation(let link):
            self.qrCodeConfirmLink = link
        case .authorized:
            self.qrCodeConfirmLink = nil
            self.onAuthSuccess?()
        default:
            break
        }
    }

    /// `true`, если api_id/api_hash уже настроены (встроенные или в Keychain) и пользователю не нужно их искать.
    public var hasStoredCredentials: Bool {
        client.hasConfiguredApiCredentials
    }

    public func saveCredentialsOnly() {
        errorMessage = nil
        let cleanId = apiId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanId.isEmpty && cleanHash.isEmpty && client.hasConfiguredApiCredentials {
            return
        }
        guard let numericId = Int(cleanId), numericId > 0 else {
            errorMessage = "API ID должен быть положительным числом (получите на https://my.telegram.org)"
            return
        }
        guard !cleanHash.isEmpty else {
            errorMessage = "Введите API Hash (32-символьная строка с https://my.telegram.org)"
            return
        }
        client.saveApiCredentials(apiId: "\(numericId)", apiHash: cleanHash)
    }

    public func requestCode() async {
        errorMessage = nil
        if !client.hasConfiguredApiCredentials || (!apiId.isEmpty && !apiHash.isEmpty) {
            saveCredentialsOnly()
            guard errorMessage == nil else { return }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let nextStep = try await client.startPhoneAuthentication(phoneNumber: phoneNumber)
            applyStep(nextStep)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func requestQRLogin() async {
        errorMessage = nil
        if !client.hasConfiguredApiCredentials || (!apiId.isEmpty && !apiHash.isEmpty) {
            saveCredentialsOnly()
            guard errorMessage == nil else { return }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let nextStep = try await client.requestQRCodeAuthentication()
            applyStep(nextStep)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func submitCode() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let nextStep = try await client.submitVerificationCode(verificationCode)
            applyStep(nextStep)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func resendCode() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let nextStep = try await client.resendAuthenticationCode()
            applyStep(nextStep)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func resetToPhoneInput() async {
        errorMessage = nil
        verificationCode = ""
        twoFactorPassword = ""
        qrCodeConfirmLink = nil
        isLoading = true
        defer { isLoading = false }
        await client.resetTDLibSession()
        self.step = .unauthorized
    }

    public func submit2FAPassword() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let nextStep = try await client.submitTwoFactorPassword(twoFactorPassword)
            applyStep(nextStep)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func logout() {
        client.logout()
        verificationCode = ""
        twoFactorPassword = ""
        qrCodeConfirmLink = nil
        step = .unauthorized
    }
}
