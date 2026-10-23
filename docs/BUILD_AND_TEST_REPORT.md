# Отчёт о разработке, проверке и тестировании Bebranoid iOS (`BUILD_AND_TEST_REPORT.md`)

- **Целевой публичный репозиторий**: `GitGayHub/Bebranoid-iOS` (`main`)
- **Происхождение версии**: портировано из десктопной версии Bebranoid (базовый коммит алгоритмов `d98c88d14a1c66f5d9907551521347d52aa187a6`, ревизия iOS-кода при выделении в автономный репозиторий `d0676c5b0b3522edbc26758fe1da56fcb3736f0f`)
- **Целевые устройства**: iPhone 15 Pro Max, iPhone 17 Pro Max и современные модели iPhone (iOS 17.0+)

---

## 1. Аудит безопасности перед публикацией

Перед инициализацией публичного репозитория `GitGayHub/Bebranoid-iOS` проведён полный аудит кода и документации:
- Удалены все персональные идентификаторы и названия чатов из исходного кода (`AppConfig.swift`, `PlaybackSessionStore.swift`, `TelegramClientService.swift`, `TelegramScanner.swift`, `SettingsView.swift`, `UITestingDemoSeeder.swift`, `TelegramParserTests.swift`) и документации.
- Выбор основного облачного чата и read-only архивного чата вынесен в пользовательские настройки (`SettingsView.swift`) после авторизации в Telegram.
- Создана чистая история Git (`git init -b main`) без переноса истории приватного репозитория.

---

## 2. Ключевые архитектурные и функциональные исправления

1. **Нативная интеграция с Telegram (`TDLibFramework`)**:
   - Подключён `SwiftGram/TDLibFramework` (`1.8.68-18c8f7a0`) в `Package.swift` и `project.yml`.
   - В `TelegramClientService.swift` реализован `TDLibJSONBridge` (`td_create_client_id`, `td_send`, `td_receive`, `td_execute`) с реальными запросами `setTdlibParameters`, `setAuthenticationPhoneNumber`, `checkAuthenticationCode`, `checkAuthenticationPassword`, `loadChats`/`getChats`/`getChat`, `getForumTopics`, `searchChatMessages` (`searchMessagesFilterAudio` и `searchMessagesFilterDocument`), `downloadFile`/`getFile`/`cancelDownloadFile` и `deleteMessages`.
2. **Кросс-языковая верификация `HarmonoidMeshBackground` (`JS ↔ Swift`)**:
   - Создан Swift CLI-скрипт `scripts/dump-mesh-swift.swift`, который компилируется вместе с `HarmonoidMeshEngine.swift` и `HarmonoidMeshFixtures.swift` через `swiftc` и выводит JSON с результатами расчётов всех примитивов, 7 эталонных обложек `64×64 RGBA`, `lerpPalette` и 4 блобов на таймкодах `t = 0.0, 3.5, 7.0, 10.0s`.
   - Верификатор `scripts/verify-mesh-fixtures.mjs` выполняет реальный бинарник Swift и сверяет каждое числовое значение с эталонным алгоритмом JS (`maxChannelDelta = ±0`).
3. **Многостраничная пагинация YouTube и честная инспекция потоков (`YouTubeService.swift`)**:
   - Реализована пагинация плейлистов свыше первой HTML-страницы через Innertube `/youtubei/v1/browse` (`continuationCommand.token`) до 5000 треков с дедупликацией по `videoId`.
   - В `inspectPlayerResponseJSON` добавлена честная диагностика `playabilityStatus` и `signatureCipher` без создания фальшивых потоков.
