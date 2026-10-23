# Отчёт о разработке, проверке и тестировании Bebranoid iOS (`BUILD_AND_TEST_REPORT.md`)

- **Целевой публичный репозиторий**: `https://github.com/GitGayHub/Bebranoid-iOS` (`main`, `PUBLIC`)
- **Исходный приватный репозиторий**: `https://github.com/GitGayHub/Bebranoid` (`PRIVATE`, сохранён без изменений)
- **Происхождение версии**: портировано из десктопной версии Bebranoid (базовый коммит алгоритмов `d98c88d14a1c66f5d9907551521347d52aa187a6`, ревизия iOS-кода при выделении в автономный репозиторий `d0676c5b0b3522edbc26758fe1da56fcb3736f0f`)
- **Целевые устройства**: iPhone 15 Pro Max, iPhone 16 Pro Max, iPhone 17 Pro Max и современные модели iPhone (iOS 17.0+)

---

## 1. Аудит безопасности перед публикацией

Перед инициализацией публичного репозитория `GitGayHub/Bebranoid-iOS` проведён полный аудит кода и документации:
- Удалены все персональные идентификаторы и названия чатов из исходного кода (`AppConfig.swift`, `PlaybackSessionStore.swift`, `TelegramClientService.swift`, `TelegramScanner.swift`, `SettingsView.swift`, `UITestingDemoSeeder.swift`, `TelegramParserTests.swift`) и документации.
- Выбор основного облачного чата и read-only архивного чата вынесен в пользовательские настройки (`SettingsView.swift`) после авторизации в Telegram.
- Создана чистая история Git (`git init -b main`) без переноса истории приватного репозитория.
- Скрипт `scripts/verify-parity.mjs` автоматически проверяет отсутствие `TODO`/`FIXME` и захардкоженных персональных ID супергрупп во всех Swift-файлах.

---

## 2. Ключевые архитектурные и функциональные исправления

1. **Нативная интеграция с Telegram (`TDLibFramework`)**:
   - Подключён `SwiftGram/TDLibFramework` (`1.8.68-18c8f7a0`) в `Package.swift` и `project.yml`.
   - В `TelegramClientService.swift` реализован `TDLibJSONBridge` (`td_create_client_id`, `td_send`, `td_receive`, `td_execute`) с реальными запросами `setTdlibParameters`, `setAuthenticationPhoneNumber`, `checkAuthenticationCode`, `checkAuthenticationPassword`, `loadChats`/`getChats`/`getChat`/`getSupergroup`, `getForumTopics`, `searchChatMessages` (`searchMessagesFilterAudio` и `searchMessagesFilterDocument`), `downloadFile`/`getFile`/`cancelDownloadFile`, `deleteMessages` и `logOut`.
2. **Кросс-языковая верификация `HarmonoidMeshBackground` (`JS ↔ Swift`)**:
   - Создан Swift CLI-скрипт `scripts/dump-mesh-swift.swift`, который компилируется вместе с `HarmonoidMeshEngine.swift` и `HarmonoidMeshFixtures.swift` через `swiftc` и выводит JSON с результатами расчётов всех примитивов, 7 эталонных обложек `64×64 RGBA`, `lerpPalette` и 4 блобов на таймкодах `t = 0.0, 3.5, 7.0, 10.0s`.
   - При реальном запуске кросс-языкового теста `node scripts/verify-mesh-fixtures.mjs --require-swift` обнаружены и исправлены две ошибки в `HarmonoidMeshEngine.swift`:
     - Направление сортировки корзин по `score` в `quantizeFromImageData`, `mapPaletteToMeshColors` и `pickAccentFromPalette` исправлено с восходящего (`<`) на нисходящее (`>`), что устранило расхождение на фикстуре `dark-red`.
     - В grayscale-фоллбэке `extractCoverPalette` добавлен пропуск прозрачных пикселей (`alpha < 32`), что обеспечило точное совпадение на фикстуре `transparent` (`0` корзин → `DEFAULT_PALETTE`).
   - После исправления реальный запуск `node scripts/verify-mesh-fixtures.mjs --require-swift` на macOS подтвердил `maxChannelDelta = ±0` по всем 7 фикстурам (`docs/mesh-parity-report.json`, `"swiftRuntimeExecuted": true`).
3. **Многостраничная пагинация YouTube и честная инспекция потоков (`YouTubeService.swift`)**:
   - Реализована пагинация плейлистов свыше первой HTML-страницы через Innertube `/youtubei/v1/browse` (`continuationCommand.token`) до 5000 треков с дедупликацией по `videoId`.
   - В `inspectPlayerResponseJSON` добавлена честная диагностика `playabilityStatus` и `signatureCipher` без создания фальшивых потоков.
4. **Исправления в парсере караоке (`LRCParser.swift`) и сплиттере артистов (`ArtistSplitter.swift`)**:
   - В `LRCParser.swift` ограничено растягивание последнего слова караоке-строки при длинной инструментальной паузе (`>= 3.5s`), благодаря чему `BeautifulLyricsTransform` корректно выделяет промежуточные инструментальные `Interlude` между вокальными строками.
   - В `ArtistSplitter.swift` исправлено определение `ALL CAPS` для коротких названий артистов (`trimmed.count > 1`, например `"КИНО"` против `"Кино"`).

---

## 3. Сборка, тестирование и артефакты GitHub Actions (`GitGayHub/Bebranoid-iOS`)

Все 3 workflow автоматически выполняются на бесплатных `macos-14` раннерах GitHub Actions (`Xcode 15.4 Build version 15F31d`, симулятор `iPhone 16 Pro Max`, `UDID: D93350B9-61EE-4432-BD8E-E25978972F13`):

1. **`ios-compile.yml` (`iOS Compile & Unit Tests`)**:
   - Выполняет `node scripts/verify-mesh-fixtures.mjs --require-swift` (с компиляцией через `swiftc`) и `node scripts/verify-parity.mjs`.
   - Генерирует `Bebranoid.xcodeproj` через `XcodeGen`, разрешает зависимость `TDLibFramework` (`1.8.68-18c8f7a0`) и собирает проект с компиляцией Metal-шейдера `HarmonoidMeshShader.metal` -> `default.metallib`.
   - Запускает все 26 модульных тестов `XCTest` (`BebranoidTests`) в iOS Simulator.
2. **`ios-preview.yml` (`iOS Simulator Preview & Screenshots`)**:
   - Загружает симулятор `iPhone 16 Pro Max`, устанавливает `Bebranoid.app` и снимает 10 скриншотов всех экранов приложения (`01-library.png` .. `10-mini-player.png`), 4 кадра `HarmonoidMeshBackground` в фиксированные моменты времени (`t = 0.0, 3.5, 7.0, 10.0s`) и 4 референсных кадра палитр (`vivid`, `pastel`, `dark-red`, `bw`), а также упаковывает `Bebranoid-iOS-Simulator-App.zip`.
3. **`ios-device-package.yml` (`iOS Device Unsigned IPA Package (Sideloadly)`)**:
   - Собирает `Release` arm64 бинарник для физического iPhone (`generic/platform=iOS`), включая встроенный `Frameworks/TDLibFramework.framework` и `default.metallib`, и упаковывает `Bebranoid-unsigned-sideloadly.ipa` (~14.1 МБ) для бесплатной установки с Windows 11 через Sideloadly / AltStore.
