import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

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
    private var lastAutoSubmittedClipboardCode: String? = nil
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

    public func requestCode(openTelegramAfterRequest: Bool = false) async {
        errorMessage = nil
        if !client.hasConfiguredApiCredentials || (!apiId.isEmpty && !apiHash.isEmpty) {
            saveCredentialsOnly()
            guard errorMessage == nil else { return }
        }

        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPhone.isEmpty {
            keychain.saveString(trimmedPhone, for: .telegramAuthorizedPhone)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            lastAutoSubmittedClipboardCode = nil
            let nextStep = try await client.startPhoneAuthentication(phoneNumber: phoneNumber)
            applyStep(nextStep)
            if openTelegramAfterRequest, case .awaitingCode = nextStep {
                openTelegramAppOnDevice()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Извлекает 5-значный код Telegram из произвольного текста (даже если скопировано всё сообщение целиком)
    public static func extractFiveDigitTelegramCode(from rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digitsOnly = trimmed.filter(\.isWholeNumber)
        if digitsOnly.count == 5 && trimmed.count <= 8 {
            return digitsOnly
        }
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\d)(\\d{5})(?!\\d)") else {
            return nil
        }
        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let codeRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }
        return String(trimmed[codeRange])
    }

    /// Проверяет буфер обмена iOS на наличие 5-значного кода Telegram и автоматически подставляет/отправляет его
    @discardableResult
    public func tryAutoFillCodeFromClipboard(autoSubmit: Bool = true, forceResubmitSameCode: Bool = false) -> Bool {
        #if canImport(UIKit)
        guard case .awaitingCode = step, !isLoading else { return false }
        guard let rawPaste = UIPasteboard.general.string,
              let code = Self.extractFiveDigitTelegramCode(from: rawPaste) else {
            return false
        }
        if !forceResubmitSameCode && lastAutoSubmittedClipboardCode == code {
            return false
        }
        lastAutoSubmittedClipboardCode = code
        verificationCode = code
        if autoSubmit {
            Task { await submitCode() }
        }
        return true
        #else
        return false
        #endif
    }

    public func openTelegramAppOnDevice() {
        #if canImport(UIKit)
        guard let tgURL = URL(string: "tg://") else { return }
        UIApplication.shared.open(tgURL, options: [:]) { success in
            if !success, let webFallback = URL(string: "https://t.me/") {
                UIApplication.shared.open(webFallback, options: [:], completionHandler: nil)
            }
        }
        #endif
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
