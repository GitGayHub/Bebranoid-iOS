# Отчёт о разработке, проверке и тестировании Bebranoid iOS (`BUILD_AND_TEST_REPORT.md`)

- **Репозиторий**: `GitGayHub/Bebranoid` (приватный репозиторий)
- **Базовая ветка Windows**: `master` (`d98c88d14a1c66f5d9907551521347d52aa187a6`)
- **Рабочая ветка iOS**: `feature/ios-port` (опубликована в `origin/feature/ios-port`)
- **Целевые устройства**: iPhone 15 Pro Max, iPhone 17 Pro Max и современные модели iPhone (iOS 17.0+)

---

## 1. Диагностика среды Windows 11 и состояние Git (Этапы 1 и 2)

На рабочей машине Windows 11 выполнена полная диагностика бесплатного инструментария (`ios/scripts/setup-windows.ps1`):

| Инструмент | Фактическая версия | Статус |
|---|---|---|
| **Git** | `git version 2.55.0.windows.2` | Установлен и проверен |
| **Node.js LTS** | `v24.18.0` (`npm 12.0.2`) | Установлен и проверен |
| **Python 3** | `Python 3.12.10` | Установлен и проверен |
| **PowerShell** | `5.1.26100.9444` | Установлен и проверен |
| **GitHub CLI (`gh`)** | `gh version 2.102.0` | Авторизован (`GitGayHub`, права `repo`, `workflow`) |
| **Удалённая ветка** | `origin/feature/ios-port` | Опубликована на GitHub (`git ls-remote --heads origin feature/ios-port`) |
| **Неприкосновенность Windows-кода** | `git diff d98c88d14a1c66f5d9907551521347d52aa187a6 -- src electron package.json` | `0` изменений (Windows/Electron-код не затронут) |

Созданы 6 вспомогательных PowerShell-скриптов в `ios/scripts/`:
- `ios/scripts/setup-windows.ps1` — диагностика и установка недостающих бесплатных утилит через `winget`.
- `ios/scripts/check-project.ps1` — проверка неизменности Windows-файлов, статическая проверка всех Swift-файлов, запуск `verify-parity.mjs` и `verify-mesh-fixtures.mjs`.
- `ios/scripts/verify-mesh.ps1` — сверка математической модели `HarmonoidMeshBackground` на 7 эталонных обложках `64×64 RGBA`.
- `ios/scripts/ci-status.ps1` — проверка статуса и логов удалённых сборок GitHub Actions (`gh run list`, `gh run view`).
- `ios/scripts/download-preview.ps1` — скачивание артефактов `Bebranoid-iOS-Preview`, `Bebranoid-iOS-Simulator-App` и `Bebranoid-iOS-Unsigned-IPA` в `ios/artifacts/`.
- `ios/scripts/verify-artifacts.ps1` — проверка наличия и размера всех 10 скриншотов симулятора (`01-library.png`..`10-mini-player.png`) и `.ipa`.

---

## 2. Критическое исправление `HarmonoidMeshBackground` 1:1 (Этап 3)

Проведена полная сверка `src/components/HarmonoidMeshBackground.jsx` и `docs/MESH_BACKGROUND.md` с нативной iOS-реализацией (`ios/Bebranoid/MeshBackground/HarmonoidMeshEngine.swift`, `HarmonoidMeshShader.metal`, `HarmonoidMeshView.swift`, `HarmonoidMeshFixtures.swift`).

Все выявленные ранее расхождения полностью устранены:
1. **Downscale обложки**: строго `64×64` (`analysisDimension = 64`).
2. **Фильтрация пикселей**: отбрасываются `a < 32`, `lum < 0.025 || lum > 0.985`, `sat < 0.035`.
3. **Квантование по 10° корзинам оттенка**: `key = Int(floor(hsv.h / 10.0))` (`h` в градусах `0..360`).
4. **Скоринг корзины и поддержка пастельных обложек**:
   - `pastelBoost = (lum > 0.55 && sat >= 0.04 && sat < 0.4) ? 1.35 : 1.0`
   - `satScore = max(0.12, sat)`
   - `score += satScore * (0.45 + (1.0 - abs(lum - 0.42))) * pastelBoost`
   - Сортировка по `score` по убыванию, выбор топ-8 цветов (`maxExtractedPaletteColors = 8`).
   - При пустом результате (чёрно-белая / монохромная обложка) — усреднение каждого 4-го пикселя (`i += 16`) со `score = 1.0`.
5. **Преобразование в 4 тёмных Mesh-тона (`toMeshTint`)**:
   - `depth = 0.22 + Double(idx) * 0.04` (`0.22, 0.26, 0.30, 0.34`).
   - Пастельная ветка: `pastel = v > 0.6 && s > 0.04 && s < 0.28`, `ns = min(0.55, max(0.32, s * 2.2 + 0.14))`, `nv = 0.26`.
   - При `< 4` цветах в палитре: добивка через `toMeshTint(list[0], depth: 0.2 + Double(picks.count) * 0.05)`.
   - Дефолтная палитра: `[20, 30, 50], [30, 22, 48], [18, 36, 44], [24, 20, 40]`.
6. **Выбор и читаемость UI-акцента (`pickAccentFromPalette` + `ensureReadableAccent`)**:
   - Бусты для золотых (`28°..72°`, `×2.0`), тёплых красных (`<30° || >330°`, `×1.65`) и пурпурных (`300°..350°`, `×1.25`) оттенков.
   - Гарантия читаемости `luminance(out) >= 0.42` (при меньшей яркости `v` поднимается шагами `+0.06` до `0.90`).
   - Дефолтный акцент: `DEFAULT_UI_ACCENT = rgb(96, 165, 250)`.
7. **Геометрия, радиусы, режимы наложения и виньетка**:
   - `fillBase`: `r = max(4, floor(c0.r * 0.35))`, `g = max(4, floor(c0.g * 0.35))`, `b = max(6, floor(c0.b * 0.40))`.
   - 4 контрольные точки (`motionSpeed = 0.45`), динамический радиус `max(w, h) * (0.55 + 0.08 * sin(t * 0.35 + i))`.
   - Пятно `0`: `source-over` (`.normal`), пятна `1..3`: `lighter` (`.plusLighter`), радиальные стопы `0.0 -> 0.95`, `0.45 -> 0.45`, `1.0 -> 0.0`.
   - Внутреннее затемнение холста `12%`, вертикальная виньетка `0.22 (0%) -> 0.0 (20%..55%) -> 0.28 (100%)` и финальный слой `.harmonoid-mesh__overlay` `0.18`.
   - Длительность перехода `1650 мс` (минимум `1400 мс`) через `smoothstep(0, 1, raw)`.

Подробная таблица сравнения на всех 7 эталонных обложках (`solid`, `bw`, `dark-red`, `vivid`, `pastel`, `transparent`, `neutral`) сохранена в `ios/docs/MESH_PARITY_TABLE.md` и `ios/docs/mesh-parity-report.json` (максимальное расхождение цветовых каналов JS vs Swift: `±0`).

---

## 3. Честный аудит подсистем iOS-порта (Этапы 4, 5 и 7)

| Подсистема | Что работает полностью и проверено тестами | Что требует внешних учётных данных / окружения устройства |
|---|---|---|
| **HarmonoidMeshBackground** (`HarmonoidMeshEngine.swift`, `HarmonoidMeshView.swift`, `HarmonoidMeshShader.metal`) | Полный 1:1 расчёт палитры `64×64`, `toMeshTint`, `pickAccentFromPalette`, `ensureReadableAccent`, `fillBase`, 4 блоба, виньетка и морфинг. Проверено на 7 эталонных фикстурах | Не требует внешних ключей |
| **Аудио-движок и DSP** (`DualStreamAudioEngine.swift`, `AudioFXProcessor.swift`, `AudioMetadataReader.swift`, `VolumeCurve.swift`) | Двухпоточный `AVAudioEngine` (`primary` + `secondary`), реальный перекрывающийся кроссфейд (`0.5–30s`), мгновенный hard-cut при ручном скипе, отмена кроссфейда при паузе, кривая громкости `u^2.75`, пресеты `normal`/`slowed`/`slowed_reverb`/`speedup`/`speedup_reverb`, `Bass Boost` (`180 Hz`, `+8 dB`), парсер заголовков `FLAC/WAV/M4A/MP3` и бейджи `Hi-Res`/`Lossless`/`HQ` | Для реального вывода звука требуется запуск в iOS Simulator (macOS runner) или на физическом iPhone |
| **Лирика и перевод** (`LRCParser.swift`, `BeautifulLyricsTransform.swift`, `Spring.swift`, `CubicSpline.swift`, `InterludeEngine.swift`, `Romanizer.swift`, `LyricsService.swift`, `LyricsTranslationService.swift`) | Парсинг Line/Word/Plain LRC, пружинная физика `Spring`, `CubicSpline`, 3-точечный `InterludeEngine`, `Emphasized >= 1.25s`, романизация JP/KR/CN, поиск в LRCLIB со скорингом кандидатов, перевод на русский через Google GTX + Amalgama | Онлайн-запросы к `lrclib.net` и `translate.googleapis.com` требуют интернет-соединения на устройстве |
| **Telegram** (`TelegramScanner.swift`, `PriorityDownloadQueue.swift`, `TelegramClientService.swift`, `KeychainHelper.swift`) | Парсер подписей AndroSend (`parseMetaFromCaption`), определение альбомов и защита от топиков одного трека (`isSingleTrackTopic >= 75%`), 3-уровневая дедупликация `AndroSend Архив` (`-1003890744365`) относительно `AndroSend Облако` (`-1003734947911`), read-only блокировка удаления из архива, `PriorityDownloadQueue` (`3 / 1 / 0`) с вытеснением и докачкой `.part`, хранение сессии в Keychain | Для живого MTProto-сокета с серверами Telegram требуется ввод личных `api_id`/`api_hash` (`my.telegram.org`) и подключение бинарного фреймворка `TDLibKit` (`libtdjson.xcframework`) либо проксирование потока файлов |
| **YouTube** (`YouTubeLinkParser.swift`, `YouTubeService.swift`, `PlaylistPreferences.swift`) | Парсинг всех видов ссылок YouTube / YouTube Music / Shorts / Playlists, лимит шаффла `15..5000` (`±10`), ручные `include/exclude`, `reconcilePlaylist`, нативный запрос к YouTube Innertube API (`ANDROID`/`IOS` client) и парсинг `ytInitialData` без `yt-dlp`/`ffmpeg` | Прямая скачка аудиопотока `itag=140 (m4a)` через Innertube работает для открытых видео без `signatureCipher`; видео с шифрованной подписью YouTube требуют внешнего экстрактора |
| **Simulator Demo Mode (`#if DEBUG`)** (`UITestingDemoSeeder.swift`) | По аргументу `--ui-testing-demo` и `--screen=library\|tracks\|albums\|artists\|playlists\|player\|lyrics\|queue\|settings\|mini-player` + `--mesh-fixture=...` детерминированно открывает любой экран с эталонными данными для автоматических скриншотов в CI | Включается строго в `DEBUG` при наличии флага `--ui-testing-demo`; не влияет на `Release` |

---

## 4. Статус GitHub Actions и квоты аккаунта (Этапы 5 и 8)

В репозитории настроены 3 контролируемых бесплатных workflow:
1. `.github/workflows/ios-compile.yml` — компиляция `xcodebuild build-for-testing` и прогон модульных тестов `BebranoidTests` на `iphonesimulator`.
2. `.github/workflows/ios-preview.yml` — запуск только вручную (`workflow_dispatch`) или через `ios/.ci-trigger-preview`; собирает приложение для симулятора, запускает `xcrun simctl`, снимает 10 скриншотов всех экранов (`01-library.png`..`10-mini-player.png`), 4 кадра `HarmonoidMeshBackground` (`mesh-01..04.png`) и видео `preview-animation.mp4`, публикуя артефакт `Bebranoid-iOS-Preview`.
3. `.github/workflows/ios-device-package.yml` — запуск только вручную (`workflow_dispatch`) или через `ios/.ci-trigger-device`; собирает `Release` под `generic/platform=iOS` без платного сертификата и упаковывает `Payload/Bebranoid.app` в `Bebranoid-unsigned-sideloadly.ipa`.

### Фактический результат проверки запуска GitHub Actions на аккаунте `GitGayHub`

При пуше ветки `feature/ios-port` в приватный репозиторий `GitGayHub/Bebranoid` GitHub Actions создаёт workflow run, однако запуск задачи на стороне GitHub в данный момент блокируется системным ограничением биллинга аккаунта:

> `The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings`

В соответствии с правилами безопасности (Этап 8):
- Настройки оплаты аккаунта не изменялись.
- Приватный репозиторий не переводился в публичный.
- Как только лимит бесплатных минут или статус оплаты в `GitHub Settings → Billing and licensing → Budgets and alerts` будет разблокирован владельцем аккаунта, все 3 workflow (`ios-compile.yml`, `ios-preview.yml`, `ios-device-package.yml`) сразу готовы к запуску одной командой:
  - `gh workflow run ios-compile.yml --ref feature/ios-port`
  - `gh workflow run ios-preview.yml --ref feature/ios-port`
  - `gh workflow run ios-device-package.yml --ref feature/ios-port`
