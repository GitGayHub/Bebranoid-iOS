import Foundation
import Combine

@MainActor
public final class TelegramAuthViewModel: ObservableObject {
    @Published public var step: TelegramAuthStepState = .unauthorized
    @Published public var apiId: String = ""
    @Published public var apiHash: String = ""
    @Published public var phoneNumber: String = ""
    @Published public var verificationCode: String = ""
    @Published public var twoFactorPassword: String = ""
    @Published public var twoFactorHint: String? = nil
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?

    private let client: TelegramClientService
    public var onAuthSuccess: (() -> Void)?

    public init(client: TelegramClientService = .shared) {
        self.client = client
        self.apiId = client.configuredApiId
        self.apiHash = client.configuredApiHash
        if client.isAuthorized {
            self.step = .authorized
        }
    }

    public func requestCode() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await client.sendAuthenticationCode(
                phoneNumber: phoneNumber,
                apiId: apiId,
                apiHash: apiHash
            )
            twoFactorHint = result.requires2FAHint
            step = .awaitingCode
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func submitCode() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let nextStep = try await client.verifyAuthenticationCode(code: verificationCode)
            step = nextStep
            if nextStep == .authorized {
                onAuthSuccess?()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func submit2FAPassword() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let nextStep = try await client.verify2FAPassword(password: twoFactorPassword)
            step = nextStep
            if nextStep == .authorized {
                onAuthSuccess?()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveCredentialsOnly() {
        errorMessage = nil
        let cleanId = apiId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Int32(cleanId) != nil, !cleanHash.isEmpty else {
            errorMessage = "Укажите числовой API ID и строковый API Hash с https://my.telegram.org"
            return
        }
        client.saveApiCredentials(apiId: cleanId, apiHash: cleanHash)
    }

    public func logout() {
        client.logout()
        verificationCode = ""
        twoFactorPassword = ""
        step = .unauthorized
    }
}
