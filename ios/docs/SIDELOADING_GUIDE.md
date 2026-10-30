# Руководство по бесплатной облачной сборке, предпросмотру и установке Bebranoid iOS (`SIDELOADING_GUIDE.md`)

Данное руководство описывает полностью бесплатный цикл проверки, получения скриншотов из iOS Simulator и установки **Bebranoid iOS** на **iPhone 15 Pro Max** и **iPhone 17 Pro Max** с компьютера под управлением **Windows 11**.

---

## 1. Три контролируемых GitHub Actions Workflow

Чтобы экономно расходовать бесплатную квоту GitHub Actions (`macos-14`), сборка разделена на 3 независимых пайплайна в `.github/workflows/`:

1. **`ios-compile.yml` (Проверка компиляции и модульных тестов)**:
   - Запускается при изменении файлов в `ios/**` или вручную через `workflow_dispatch`.
   - Выполняет `verify-mesh-fixtures.mjs`, `verify-parity.mjs`, генерирует проект через `XcodeGen`, компилирует `Bebranoid` под `iphonesimulator` и запускает все модульные тесты `BebranoidTests`.
   - Артефакт: `Bebranoid-Compile-Logs`.
2. **`ios-preview.yml` (Визуальный предпросмотр в iOS Simulator и авто-скриншоты)**:
   - Запускается **только вручную** (`gh workflow run ios-preview.yml --ref feature/ios-port`) или при изменении файла `ios/.ci-trigger-preview` (не тратит минуты на каждый обычный коммит).
   - Выбирает доступный симулятор (`iPhone 17 Pro Max` -> `iPhone 16 Pro Max` -> `iPhone 15 Pro Max`), загружает его через `xcrun simctl boot`, устанавливает `Bebranoid.app` и по очереди запускает приложение в детерминированном DEBUG-режиме `--ui-testing-demo`, снимая:
     - `01-library.png` (Медиатека)
     - `02-tracks.png` (Треки)
     - `03-albums.png` (Альбомы)
     - `04-artists.png` (Артисты)
     - `05-playlists.png` (Плейлисты)
     - `06-player.png` (Полноэкранный плеер)
     - `07-lyrics.png` (Караоке-текст Beautiful Lyrics с переводом)
     - `08-queue.png` (Очередь воспроизведения)
     - `09-settings.png` (Настройки, Telegram и кеш)
     - `10-mini-player.png` (Плавающий мини-плеер)
     - `mesh-01-vivid.png` .. `mesh-04-bw.png` (Эталонные обложки `HarmonoidMeshBackground`)
     - `preview-animation.mp4` (Короткое видео живой анимации фона)
   - Артефакты: `Bebranoid-iOS-Preview` и `Bebranoid-iOS-Simulator-App`.
3. **`ios-device-package.yml` (Пакет для реального iPhone через Sideloadly)**:
   - Запускается **только вручную** (`gh workflow run ios-device-package.yml --ref feature/ios-port`) или при изменении `ios/.ci-trigger-device`.
   - Собирает `Release` для `generic/platform=iOS` (`arm64`) без платного сертификата (`CODE_SIGNING_ALLOWED=NO`) и упаковывает `Payload/Bebranoid.app` в `Bebranoid-unsigned-sideloadly.ipa`.
   - Артефакт: `Bebranoid-iOS-Unsigned-IPA`.

---

## 2. Быстрые команды на Windows 11 (`ios/scripts/`)

Все операции выполняются из корня репозитория в PowerShell:

```powershell
# 1. Диагностика установленных бесплатных инструментов на Windows 11
powershell -ExecutionPolicy Bypass -File ios\scripts\setup-windows.ps1

# 2. Локальная проверка проекта, неизменности Windows-кода и математического паритета
powershell -ExecutionPolicy Bypass -File ios\scripts\check-project.ps1

# 3. Сверка HarmonoidMeshBackground на 7 эталонных обложках 64x64 RGBA
powershell -ExecutionPolicy Bypass -File ios\scripts\verify-mesh.ps1

# 4. Проверка статуса сборок GitHub Actions
powershell -ExecutionPolicy Bypass -File ios\scripts\ci-status.ps1

# 5. Скачивание готовых скриншотов симулятора и IPA в папку ios\artifacts\
powershell -ExecutionPolicy Bypass -File ios\scripts\download-preview.ps1

# 6. Проверка целостности скачанных скриншотов и артефактов
powershell -ExecutionPolicy Bypass -File ios\scripts\verify-artifacts.ps1
```

---

## 3. Контроль бесплатного лимита GitHub Actions (`$0 Budget`)

Для приватных репозиториев GitHub предоставляет бесплатный пакет минут (2000 минут/мес в эквиваленте Linux; на macOS-раннерах применяется множитель `10x`, то есть ~200 минут macOS в месяц).

Если при запуске workflow в GitHub Actions появляется сообщение:
> `The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings`

Выполните следующие безопасные шаги в браузере (без подключения платных подписок):
1. Откройте на GitHub: **Settings → Billing and licensing → Overview** (или **Payment information**).
2. Если на аккаунте висит старая неуспешная попытка списания (`recent account payments have failed`), удалите устаревший способ оплаты или сбросьте блокировку в разделе **Billing and licensing**.
3. Перейдите в **Settings → Billing and licensing → Budgets and alerts** (или **Spending limits**) и убедитесь, что лимит расходов сверх бесплатного пакета установлен в **`$0`** (`Limit spending to $0`). Это гарантирует, что GitHub никогда не спишет деньги и будет использовать только бесплатную ежемесячную квоту.
4. После снятия блокировки запустите сборку и генерацию скриншотов командой:
   ```powershell
   gh workflow run ios-compile.yml --ref feature/ios-port
   gh workflow run ios-preview.yml --ref feature/ios-port
   ```

---

## 4. Бесплатная установка на iPhone 15 Pro Max / iPhone 17 Pro Max через Sideloadly

> **Важно**: Файл `Bebranoid-unsigned-sideloadly.ipa` из артефакта `Bebranoid-iOS-Unsigned-IPA` является **неподписанным** (Unsigned IPA). На iOS нельзя установить неподписанный `.ipa` напрямую без переподписи. Программа **Sideloadly** на Windows 11 бесплатно подписывает его вашим обычным личным Apple ID (без платной подписки Apple Developer Program `$99/год`).

### Пошаговая инструкция:
1. На Windows 11 установите официальные десктопные версии **iTunes** и **iCloud** с сайта Apple (не из Microsoft Store) и бесплатную утилиту **Sideloadly** (`https://sideloadly.io`).
2. Запустите workflow `ios-device-package.yml` и скачайте артефакт `Bebranoid-iOS-Unsigned-IPA` (`Bebranoid-unsigned-sideloadly.ipa`).
3. Подключите ваш **iPhone 15 Pro Max** или **iPhone 17 Pro Max** кабелем USB-C к компьютеру и нажмите на экране iPhone **«Доверять этому компьютеру»**.
4. Откройте **Sideloadly**:
   - Перетащите файл `Bebranoid-unsigned-sideloadly.ipa` в окно Sideloadly.
   - В поле **Apple account** введите ваш обычный бесплатный Apple ID.
   - Нажмите **Start** (при первом входе введите код двухфакторной аутентификации Apple).
5. На iPhone после завершения установки:
   - Перейдите в **Настройки → Основные → VPN и управление устройством** → выберите ваш профиль разработчика (`Apple Development: <ваш email>`) → нажмите **«Доверять»**.
   - Перейдите в **Настройки → Конфиденциальность и безопасность → Режим разработчика (Developer Mode)** → включите переключатель, перезагрузите iPhone и подтвердите включение на экране.
6. Запустите **Bebranoid** с домашнего экрана iPhone. При бесплатном Apple ID сертификат действует 7 дней; для продления достаточно раз в неделю подключить iPhone к Sideloadly (или включить Wi-Fi refresh в Sideloadly) — вся медиатека, кеш и настройки на iPhone при этом полностью сохраняются.
