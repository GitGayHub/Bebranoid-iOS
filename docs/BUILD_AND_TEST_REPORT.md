# Отчёт о разработке, проверке и тестировании Bebranoid iOS (`BUILD_AND_TEST_REPORT.md`)

- **Целевой публичный репозиторий**: `https://github.com/GitGayHub/Bebranoid-iOS` (`main`, `PUBLIC`)
- **Исходный приватный репозиторий**: `https://github.com/GitGayHub/Bebranoid` (`PRIVATE`, сохранён без изменений)
- **Происхождение версии**: портировано из десктопной версии Bebranoid (базовый коммит алгоритмов `d98c88d14a1c66f5d9907551521347d52aa187a6`)
- **Целевые устройства**: iPhone 15 Pro Max, iPhone 16 Pro Max, iPhone 17 Pro Max и современные модели iPhone (iOS 17.0+)

---

## 1. Аудит безопасности и защита персональных данных

Перед каждой публикацией в `GitGayHub/Bebranoid-iOS` выполняется автоматический и ручной аудит безопасности:
- В репозитории, логах CI, артефактах и публичных отчётах отсутствуют сессии TDLib (`db.sqlite`, `td.binlog`), браузерные cookies YouTube, токены, `api_hash`, номера телефонов и персональные идентификаторы/названия приватных чатов.
- Каталог `local-reports/` и временные файлы локальных smoke-тестов добавлены в `.gitignore`.
- Скрипт `scripts/verify-parity.mjs` автоматически проверяет отсутствие `TODO`/`FIXME` и захардкоженных персональных ID супергрупп во всех Swift-файлах.

---

## 2. Точный состав тестового набора `XCTest` (`36 XCTest` в 10 классах)

В проекте ровно **36 тестовых методов `XCTest`** (множественные проверки `XCTAssert*` внутри одного метода не считаются отдельными тестами):

| Тестовый класс | Файл | Кол-во методов `XCTest` | Что проверяется |
|---|---|---:|---|
| `ArtworkServiceTests` | `Tests/BebranoidTests/ArtworkServiceTests.swift` | **7 XCTest** | 1) Извлечение бинарного блока `METADATA_BLOCK_PICTURE` (RFC 9639) из FLAC;<br>2) Извлечение `ID3v2 APIC` из MP3;<br>3) Извлечение атома `covr -> data` из M4A/MP4/ALAC;<br>4) Центрированный кроп превью YouTube `16:9` (`1280×720 → 720×720`) и `4:3` letterbox (`480×360 → 270×270`);<br>5) 7-уровневая цепочка приоритетов `ArtworkService` и извлечение 4 цветов `HarmonoidMeshEngine`;<br>6) Защита `TelegramClientService.isAuthorized` (единственный источник истины — `authorizationStateReady`, игнорирование маркера Keychain + проверка `NOT VERIFIED` для E2E сценария в Simulator);<br>7) Извлечение `coverFileId` и `fileUniqueId` из `messageAudio` TDLib. |
| `AudioEngineIntegrationTests` | `Tests/BebranoidTests/AudioEngineIntegrationTests.swift` | **3 XCTest** | 1) `testMultiFormatAudioInspectionAndDecoding`: генерация, инспекция `AudioMetadataReader`, **реальное декодирование PCM-фреймов (`AVAudioFile.read(into:)`, проверка `framesDecoded > 10_000` и ненулевой амплитуды `RMS`)** и загрузка в `DualStreamAudioEngine` для **WAV**, **M4A (ALAC)**, **M4A (AAC)**, **FLAC** и **MP3**;<br>2) `testDualStreamEnginePlaybackSeekAndAudioFX`: `loadAndPlay`, `seek`, `pause`/`play`, режимы `normal`/`slowed`/`slowedReverb`/`speedup`, `Bass Boost (+8 dB @ 180 Hz)`, синтетический IR `2.8s` и кривая громкости `u^2.75`;<br>3) `testAppStateQueueNavigationShuffleRepeatAndLyricsSync`: очередь, `Next`/`Previous`, `Repeat` (`.none → .all → .one`), `Shuffle` и синхронизация караоке `LRCParser`. |
| `TelegramParserTests` | `Tests/BebranoidTests/TelegramParserTests.swift` | **5 XCTest** | Парсинг `key=value` подписи, фильтрация служебных топиков (`isSingleTrackTopic`), построение трека, 3-уровневая дедупликация архива (`fileUniqueId`, `filename::fileSize`, `title\|\|artist`) и защита архива от удаления. |
| `MeshPaletteTests` | `Tests/BebranoidTests/MeshPaletteTests.swift` | **4 XCTest** | Дефолтная палитра `HarmonoidMeshEngine`, 64×64 квантование по 36 корзинам оттенков с `pastelBoost = 1.35`, `toMeshTint`, `pickAccentFromPalette` и интерполяция `lerpPalette`. |
| `BeautifulLyricsTransformTests` | `Tests/BebranoidTests/BeautifulLyricsTransformTests.swift` | **4 XCTest** | Аналитический пружинный солвер `Spring`, сплайн `CubicSpline`, волна из 3 точек `InterludeEngine` и выделение `Emphasized` слогов (`>= 1.25s`). |
| `YouTubeLinkParserTests` | `Tests/BebranoidTests/YouTubeLinkParserTests.swift` | **4 XCTest** | Извлечение `videoId`/`playlistId`, парсинг `ytInitialData`, многостраничная пагинация `continuationCommand` и диагностика `inspectPlayerResponseJSON`. |
| `LRCParserTests` | `Tests/BebranoidTests/LRCParserTests.swift` | **3 XCTest** | Парсинг построчных и пословных LRC-таймкодов `<mm:ss.xx>`, поиск активной строки и активного слова. |
| `QueueOrderTests` | `Tests/BebranoidTests/QueueOrderTests.swift` | **2 XCTest** | Перемешивание предстоящих треков `reshuffleUpcoming` без сброса текущего индекса и анти-повтор первого трека при рецикле. |
| `PlaylistPreferencesTests` | `Tests/BebranoidTests/PlaylistPreferencesTests.swift` | **2 XCTest** | Clamp лимита автоплейлиста (`15..5000`, дефолт `15`) и сортировка/реконсиляция `reconcilePlaylist`. |
| `VolumeCurveTests` | `Tests/BebranoidTests/VolumeCurveTests.swift` | **2 XCTest** | Перцептивная кривая громкости `uiToGain(u) = u^2.75` и обратное преобразование `gainToUi`. |
| **ИТОГО** | **10 файлов** | **36 XCTest** | **Все 36 XCTest выполняются в iOS Simulator на macOS CI (`0 failures`)** |

---

## 3. Матрица верификации: `VERIFIED ON WINDOWS` / `VERIFIED IN IOS SIMULATOR` / `REQUIRES REAL IPHONE`

### A. `VERIFIED ON WINDOWS` (Реальный LIVE Smoke Test на авторизованном Windows Bebranoid)

Проверено путём прямого запуска живых запросов через `tdjson.dll` (TDLib) и авторизованную сессию YouTube на рабочей машине разработчика (детальный отчёт с замаскированными ID сохранён только локально в `local-reports/local-integration-report.json`, исключённом из Git):
1. **Telegram TDLib Live API**:
   - `getAuthorizationState`: подтверждено состояние `"authorizationStateReady"`.
   - `getMe`: успешно получен профиль авторизованного пользователя (`userTypeRegular`, фото профиля присутствует).
   - `getChats` (`chatListMain` + `chatListArchive`): успешно получено `235` реальных чатов.
   - `getChat` и `getSupergroup`: подтверждён доступ к основному музыкальному облаку и read-only архивному супергрупп-чату (`isForum = true`).
   - `getForumTopics`: успешно получено по `25` топиков форума в основном облаке и архиве.
   - `getChatHistory`: успешно прочитана живая история сообщений (`21` сообщение в выборке).
   - `searchChatMessages` (`searchMessagesFilterAudio`): найдено `2 987` аудиосообщений в основном облаке и `3 070` в архиве; на выборке из `30` треков `30/30` корректно распознаны `title`, `artist`, `album`, `duration`, `format`, у `29/30` присутствует `coverFileId`; подтверждена 3-уровневая дедупликация архива (`30/30`).
   - `downloadFile` (обложки и аудио): вживую скачаны `3/3` обложек из TDLib и `2/2` реальных аудиофайлов (`50 413 930` байт на диске, проверены заголовки `fLaC`/`ID3`/`ftyp` и встроенные метаданные).
2. **YouTube Live Account & Playlist Discovery**:
   - `GET https://www.youtube.com/feed/library`: HTTP `200`, подтверждён `"LOGGED_IN": true`.
   - `POST /youtubei/v1/account/account_menu`: HTTP `200`, подтверждён `activeAccountHeaderRenderer`.
   - `POST /youtubei/v1/browse` (`browseId: "FEplaylist_aggregation"`): HTTP `200`, обнаружены `2` пользовательских плейлиста аккаунта.
   - Живой импорт плейлиста через `yt-dlp --flat-playlist`: успешно получено `2 485` треков с положительной длительностью и проверен центрированный квадратный кроп обложек `480×360 → 270×270`.

### B. `VERIFIED IN IOS SIMULATOR` (Проверено на macOS 14 / Xcode 15.4 / симулятор `iPhone 16 Pro Max`)

1. **Компиляция и модульные/интеграционные тесты (`ios-compile.yml`)**:
   - Кросс-языковая верификация `HarmonoidMeshEngine` (`node scripts/verify-mesh-fixtures.mjs --require-swift`): скомпилирован и выполнен через `swiftc`, `maxChannelDelta = ±0` на всех 7 фикстурах (`docs/mesh-parity-report.json`).
   - Сборка `Bebranoid.app` с `TDLibFramework` (`1.8.68-18c8f7a0`) и Metal-шейдером `HarmonoidMeshShader.metal` → `default.metallib`.
   - Выполнены все **36 XCTest** (`ArtworkServiceTests = 7 XCTest`, `AudioEngineIntegrationTests = 3 XCTest`, плюс `26 XCTest` в остальных 8 классах), включая реальное декодирование **FLAC**, **MP3**, **WAV**, **M4A (ALAC)** и **M4A (AAC)** в PCM-буферы с проверкой ненулевого `RMS`.
2. **Визуальный и UI-аудит в симуляторе (`ios-preview.yml`)**:
   - В `QueueSheetView.swift` отображаются настоящие миниатюры обложек (`ArtworkThumbnailView`, `44×44`, `.listThumbnail`) и отформатированная длительность для каждого трека очереди (`08-queue.png`).
   - В `FullScreenPlayerView.swift` и `BebranoidAppState.swift` исправлено отображение длительности и прогресса текущего трека в Simulator Demo Mode (`0:46` / `4:04` и активная полоса прогресса вместо `0:00` на `06-player.png`).
   - На всех экранах (`01-library.png` .. `10-mini-player.png`) проверена работа реальных обложек из кеша и рендеринг `HarmonoidMeshView`.
3. **Сборка пакета для установки на устройство (`ios-device-package.yml`)**:
   - Собран свежий `Release` (`arm64`) пакет `Bebranoid-unsigned-sideloadly.ipa` со встроенным `Frameworks/TDLibFramework.framework` и `default.metallib`.

### C. `REQUIRES REAL IPHONE` (`NOT VERIFIED` без подключённого физического iPhone)

Следующие сценарии реализованы в коде (`TelegramClientService.runOnDeviceE2EAuthAndChatScanScenario`, `NowPlayingSessionManager`, `HapticsManager`, `BackgroundDownloadManager`), но помечены как **`NOT VERIFIED (REQUIRES REAL IPHONE)`**, так как в публичном облачном CI отсутствует физический iPhone и интерактивный ввод SMS/2FA-кода пользователя:
1. **Сквозной (End-to-End) сценарий авторизации Telegram и сканирования чатов непосредственно на физическом iPhone**:
   - Установка `Bebranoid-unsigned-sideloadly.ipa` через Sideloadly / AltStore на физический iPhone.
   - Интерактивный вход в Telegram (`API ID` + `API Hash` → номер телефона / QR → код из Telegram → облачный пароль 2FA) до получения `authorizationStateReady` на устройстве.
   - Живое выполнение `TelegramClientService.shared.runOnDeviceE2EAuthAndChatScanScenario()` на iPhone (кнопка «Запустить E2E сценарий Telegram (iPhone)» в `DiagnosticsView`). В симуляторе данный сценарий детерминированно возвращает `NOT VERIFIED (REQUIRES REAL IPHONE)`.
2. **Системная интеграция на физическом устройстве iOS**:
   - Управление воспроизведением и обложкой на реальном экране блокировки iOS / Dynamic Island (`MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`) при выключенном экране.
   - Физический тактильный отклик Taptic Engine (`UIImpactFeedbackGenerator` / `UISelectionFeedbackGenerator`).
   - Продолжительное фоновое воспроизведение и фоновая докачка при свёрнутом приложении на реальном оборудовании.
