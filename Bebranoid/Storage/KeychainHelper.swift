import Foundation
import Security

/// Безопасное хранилище iOS Keychain для сессии Telegram, API-ключей и учётных данных.
/// Гарантирует отсутствие секретов в открытом виде на диске или в Git.
public final class KeychainHelper: @unchecked Sendable {
    public static let shared = KeychainHelper()
    private let service = AppConfig.keychainServiceName
    private let lock = NSLock()

    private init() {}

    public enum Key: String {
        case telegramSessionData = "telegram_session_data_v1"
        case telegramApiId = "telegram_api_id_v1"
        case telegramApiHash = "telegram_api_hash_v1"
        case telegramBotTokenOrAuthKey = "telegram_auth_key_v1"
        case telegramAuthorizedPhone = "telegram_authorized_phone_v1"
        case telegramDatabaseEncryptionKey = "telegram_tdlib_db_key_v1"
    }

    /// Возвращает существующий или генерирует новый 256-битный ключ шифрования локальной БД TDLib в Keychain
    public func getOrCreateDatabaseEncryptionKey() -> String {
        if let existing = readString(for: .telegramDatabaseEncryptionKey), !existing.isEmpty {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let base64Key = Data(bytes).base64EncodedString()
        saveString(base64Key, for: .telegramDatabaseEncryptionKey)
        return base64Key
    }

    @discardableResult
    public func saveString(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return saveData(data, for: key)
    }

    public func readString(for key: Key) -> String? {
        guard let data = readData(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func saveData(_ data: Data, for key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func readData(for key: Key) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    public func delete(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public func clearAllTelegramCredentials() {
        delete(.telegramSessionData)
        delete(.telegramBotTokenOrAuthKey)
        delete(.telegramAuthorizedPhone)
    }
}
