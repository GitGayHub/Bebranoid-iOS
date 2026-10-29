import Foundation

public enum AppConfig {
    /// Заглушки до выбора пользователем собственного облачного и архивного чата в настройках Telegram
    public static let defaultMainChatPlaceholderTitle: String = "Не выбран (выберите после входа)"
    public static let defaultArchiveChatPlaceholderTitle: String = "Не выбран (опционально)"

    /// Ключевое слово и стандартные названия облачных чатов Bebranoid / AndroSend для автоподхвата после QR-входа
    public static let defaultCloudChatSearchKeyword: String = "AndroSend"
    public static let defaultSeedMainChatTitle: String = "AndroSend Облако"
    public static let defaultSeedArchiveChatTitle: String = "AndroSend Архив"

    /// Виртуальные идентификаторы альбомов и плейлистов
    public static let favoritesAlbumName: String = "Любимые"
    public static let recent30PlaylistId: String = "__recent_30__"
    public static let recent30PlaylistName: String = "Последние 30"

    /// Лимиты и параметры по умолчанию
    public static let defaultCrossfadeDuration: Double = 6.0
    public static let minCrossfadeDuration: Double = 0.5
    public static let maxCrossfadeDuration: Double = 30.0
    public static let defaultPlaylistShuffleLimit: Int = 15
    public static let maxPlaylistTrackLimit: Int = 5000
    public static let playCountListenThresholdSeconds: Double = 5.0
    public static let lyricsDurationToleranceSeconds: Double = 8.0

    /// Нормализует ID супергруппы/канала Telegram (убирает префиксы `-100` и `-` для надёжного сравнения)
    public static func normalizeTelegramChatId(_ rawChatId: String?) -> String {
        guard let raw = rawChatId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }
        if raw.hasPrefix("-100") {
            return String(raw.dropFirst(4))
        }
        if raw.hasPrefix("-") {
            return String(raw.dropFirst(1))
        }
        return raw
    }

    /// Проверка, совпадает ли `chatId` с выбранным пользователем архивным чатом (read-only: удаление строго запрещено)
    public static func isArchiveChatId(_ chatId: String?, configuredArchiveChatId: String? = nil) -> Bool {
        let normCandidate = normalizeTelegramChatId(chatId)
        guard !normCandidate.isEmpty else { return false }

        let effectiveArchive = configuredArchiveChatId ?? PlaybackSessionStore.shared.loadLibraryState().selectedTelegramArchiveChatId
        let normArchive = normalizeTelegramChatId(effectiveArchive)
        guard !normArchive.isEmpty else { return false }

        return normCandidate == normArchive
    }

    /// App Group для обмена состоянием с виджетами и Dynamic Island
    public static let appGroupIdentifier: String = "group.com.bebranoid.ios"
    public static let keychainServiceName: String = "com.bebranoid.ios.keychain"
}
