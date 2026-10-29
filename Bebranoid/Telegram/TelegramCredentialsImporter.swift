import Foundation

public extension TelegramClientService {
    /// Имя файла в `Documents/` приложения, из которого подхватываются ключи Telegram API.
    static let bundledCredentialsFileName = "telegram-credentials.json"

    /// Подхватывает `api_id` / `api_hash` из `Documents/telegram-credentials.json` и кладёт их в Keychain.
    ///
    /// Файл на iPhone кладёт скрипт с ПК по USB (`scripts/push-telegram-credentials.ps1`), поэтому секреты
    /// не попадают ни в репозиторий, ни в собранный `.ipa`, и вводить ключи руками не нужно.
    /// После успешного импорта файл удаляется. Формат: `{"apiId": 12345678, "apiHash": "0123abcd..."}`.
    @discardableResult
    func importBundledCredentialsIfPresent() -> Bool {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }

        let fileURL = documents.appendingPathComponent(Self.bundledCredentialsFileName)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        let idString: String
        if let number = json["apiId"] as? Int {
            idString = String(number)
        } else if let text = json["apiId"] as? String {
            idString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return false
        }

        let hash = ((json["apiHash"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let numericId = Int32(idString), numericId > 0, !hash.isEmpty else {
            return false
        }

        saveApiCredentials(apiId: String(numericId), apiHash: hash)
        try? fileManager.removeItem(at: fileURL)
        return true
    }
}
