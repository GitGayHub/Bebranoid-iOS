# Bebranoid iOS

Нативный автономный музыкальный проигрыватель **Bebranoid** для iPhone (iOS 17.0+, адаптирован под iPhone 15 Pro Max, iPhone 17 Pro Max и современные модели iPhone).

- **Происхождение версии**: портировано из десктопной версии Bebranoid (базовый коммит алгоритмов `d98c88d14a1c66f5d9907551521347d52aa187a6`, ревизия iOS-кода при выделении в отдельный репозиторий `d0676c5b0b3522edbc26758fe1da56fcb3736f0f`).
- **Целевая ветка**: `main`.

---

## Ключевые возможности

1. **Нативный двухпоточный аудио-движок (`DualStreamAudioEngine`)**:
   - Два независимых графа `AVAudioPlayerNode` (`Deck A` + `Deck B`) внутри `AVAudioEngine`.
   - Настоящий перекрывающийся кроссфейд (`0.5–30 с`, по умолчанию `6.0 с`), мгновенный hard-cut при ручном переключении и корректная отмена кроссфейда при паузе.
   - Перцептивная кривая громкости `uiToGain(u) = u^2.75`.
   - Атмосферные режимы `Audio FX` (`normal`, `slowed`, `slowed_reverb`, `speedup`, `speedup_reverb`) с натуральным питч-шифтом (`AVAudioUnitVarispeed`), реверберацией и `Bass Boost` (`+8 dB @ 180 Hz`).
   - Поддержка `FLAC`, `ALAC`, `WAV`, `M4A/AAC`, `MP3`, `OPUS` и автоматический расчёт плашек качества (`Hi-Res`, `Lossless`, `HQ`).
2. **Фирменный живой фон `HarmonoidMeshBackground` 1:1**:
   - Точный математический порт алгоритма квантования обложки `64×64 RGBA` по 10-градусным корзинам оттенка, `pastelBoost = 1.35`, `toMeshTint`, `pickAccentFromPalette` и `ensureReadableAccent` (`luminance >= 0.42`).
   - 4 плавающих радиальных блоба (`source-over` для блоба 0 и `lighter` для блобов 1..3), 12% затемнение, вертикальная виньетка и `smoothstep`-морфинг палитры длительностью `1650 мс`.
3. **Караоке-движки `Beautiful Lyrics` и `Classic Karaoke` + перевод на русский**:
   - Поддержка построчных (`Line`) и послоговых (`Word/Syllable`) LRC.
   - Физический пружинный солвер `Spring`, натуральный кубический сплайн `CubicSpline`, анимация проигрыша `Interlude` (3 точки с волной «marble roll») и посимвольный подъём долгих ударных слов (`>= 1.25 с`).
   - Автоматическая романизация японского, корейского и китайского текста (`Romanizer`).
   - Поиск синхронизированной лирики в `LRCLIB` и перевод на русский язык (`RU`).
4. **Автономная интеграция с Telegram (`TDLibFramework`)**:
   - Реальный нативный клиент Telegram на базе `SwiftGram/TDLibFramework` (`1.8.68-18c8f7a0`).
   - Пошаговая авторизация (`setTdlibParameters`, `setAuthenticationPhoneNumber`, `checkAuthenticationCode`, `checkAuthenticationPassword`) с хранением `api_id`, `api_hash` и ключа шифрования локальной БД TDLib в защищённом iOS Keychain.
   - Загрузка реального списка диалогов (`getChats`, `getChat`) и топиков форума (`getForumTopics`), выбор основного и архивного (read-only) чата в настройках.
   - Сканирование аудиосообщений и lossless-документов (`searchChatMessages`), 3-уровневая дедупликация архива и скачивание через `PriorityDownloadQueue` с докачкой `.part` и кооперативным вытеснением.
5. **Интеграция с YouTube**:
   - Импорт плейлистов YouTube / YouTube Music (до 5000 треков с многостраничной пагинацией Innertube `browse` `continuationCommand`).
   - Настройки шаффла плейлистов (лимит по умолчанию 15 треков, шаг `±10`, индивидуальные `include/exclude` правила).

---

## Структура репозитория

- `Bebranoid/` — исходный код iOS-приложения и виджетов (`SwiftUI`, `AVFAudio`, `Metal`, `TDLibFramework`, `WidgetKit`).
- `Tests/BebranoidTests/` — модульные тесты `XCTest`.
- `scripts/` — кросс-языковые верификаторы (`verify-mesh-fixtures.mjs`, `dump-mesh-swift.swift`, `verify-parity.mjs`) и PowerShell-скрипты для управления CI из Windows 11.
- `.github/workflows/` — бесплатные macOS GitHub Actions пайплайны:
  - `ios-compile.yml` — компиляция и модульные тесты `XCTest` + кросс-языковой тест `JS ↔ Swift`.
  - `ios-preview.yml` — запуск в iOS Simulator и автоматическая съёмка 10 скриншотов экранов + 4 фиксированных кадров `HarmonoidMeshBackground`.
  - `ios-device-package.yml` — сборка неподписанного `Bebranoid-unsigned-sideloadly.ipa` для установки через Sideloadly / AltStore.
- `docs/` — архитектурная документация, матрица функционального соответствия и инструкции по сборке.
