# Bebranoid iOS — Руководство по разработке, сборке и проверке из Windows 11 (`DEV_WORKFLOW_WINDOWS.md`)

Данный документ описывает бесплатный конвейер разработки, компиляции, запуска iOS Simulator и упаковки `.ipa` для **Bebranoid iOS** (`GitGayHub/Bebranoid-iOS`) при работе на Windows 11 без локального Mac.

---

## 1. Локальные скрипты проверки (Windows 11)

Все скрипты расположены в папке `scripts/` в корне репозитория `Bebranoid-iOS`:

- `.\scripts\setup-windows.ps1` — диагностика установленных бесплатных инструментов (`git`, `node`, `npm`, `python`, `gh`).
- `.\scripts\check-project.ps1` — полная локальная проверка Swift-файлов, `verify-parity.mjs` и `verify-mesh-fixtures.mjs`.
- `.\scripts\verify-mesh.ps1` — кросс-языковая проверка `HarmonoidMeshBackground` на 7 эталонных обложках `64×64 RGBA` (на macOS автоматически компилирует и запускает реальный Swift-код `scripts/dump-mesh-swift.swift` через `swiftc`).
- `.\scripts\verify-parity.ps1` — проверка структуры проекта, математических констант, интеграции `TDLibFramework` и отсутствия секретов/заглушек.

---

## 2. Удалённая компиляция, Simulator Preview и сборка IPA в GitHub Actions

В публичном репозитории `GitGayHub/Bebranoid-iOS` macOS runners GitHub Actions предоставляются бесплатно:

1. **Компиляция и модульные тесты (`ios-compile.yml`)**:
   - Генерирует проект через `xcodegen generate`.
   - Запускает `node scripts/verify-mesh-fixtures.mjs --require-swift` (реальное выполнение Swift CLI `dump-mesh-swift.swift` и сверка с JS-эталоном).
   - Подтягивает `SwiftGram/TDLibFramework` (`1.8.68-18c8f7a0`) и собирает `Bebranoid` для `iphonesimulator`.
   - Выполняет все модульные тесты `BebranoidTests` через `xcodebuild test-without-building`.
2. **Симулятор iPhone и автоматическое снятие скриншотов (`ios-preview.yml`)**:
   - Запускается при пуше в `main` или вручную через `.\scripts\run-free-preview.ps1`.
   - Загружает симулятор iPhone Pro Max (`xcrun simctl boot`), устанавливает `Bebranoid.app` и снимает:
     - 10 скриншотов экранов (`01-library.png` .. `10-mini-player.png`)
     - 4 фиксированных кадра времени `HarmonoidMeshBackground` (`mesh-time-0.0s.png`, `mesh-time-3.5s.png`, `mesh-time-7.0s.png`, `mesh-time-10.0s.png`)
     - 4 эталонные обложки (`mesh-01-vivid.png` .. `mesh-04-bw.png`)
     - Видео анимации `preview-animation.mp4`
3. **Сборка неподписанного `.ipa` для Sideloadly (`ios-device-package.yml`)**:
   - Собирает `Release` для `generic/platform=iOS` (`iphoneos`) без платного сертификата Apple Developer.
   - Упаковывает `Payload/Bebranoid.app` в `Bebranoid-unsigned-sideloadly.ipa`.

---

## 3. Команды управления CI и скачивания артефактов на ПК

```powershell
# 1. Проверить статус сборок GitHub Actions
.\scripts\ci-status.ps1

# 2. Запустить Simulator Preview вручную
.\scripts\run-free-preview.ps1

# 3. Скачать скриншоты симулятора и неподписанный .ipa в папку artifacts/
.\scripts\download-preview-artifacts.ps1

# 4. Проверить скачанные скриншоты и .ipa
.\scripts\verify-artifacts.ps1

# 5. Открыть папку со свежими скриншотами симулятора в Проводнике Windows
.\scripts\open-latest-screenshots.ps1
```
