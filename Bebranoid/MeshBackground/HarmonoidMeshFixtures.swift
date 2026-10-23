import Foundation

/// Эталонные 64×64 RGBA фикстуры обложек для верификации 1:1 паритета `HarmonoidMeshBackground.jsx` ↔ `HarmonoidMeshEngine.swift`.
/// Используются в модульных тестах (`MeshPaletteTests`), скрипте `verify-mesh.ps1` и DEBUG-режиме симулятора (`--mesh-fixture=...`).
public enum HarmonoidMeshFixtureKind: String, CaseIterable, Sendable {
    case solid = "solid"
    case blackAndWhite = "bw"
    case darkWithRedAccent = "dark-red"
    case vividMulticolor = "vivid"
    case pastel = "pastel"
    case transparent = "transparent"
    case neutralDominant = "neutral"
}

public enum HarmonoidMeshFixtures {
    public static let size = HarmonoidMeshEngine.analysisDimension // 64

    /// Генерирует детерминированный буфер `64×64×4` (`16384` байт RGBA) для заданной эталонной фикстуры
    public static func makeRGBA64x64(for kind: HarmonoidMeshFixtureKind) -> [UInt8] {
        let w = size
        let h = size
        var bytes = [UInt8](repeating: 0, count: w * h * 4)

        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let r: UInt8
                let g: UInt8
                let b: UInt8
                let a: UInt8

                switch kind {
                case .solid:
                    // 1. Однотонная обложка (глубокий кобальтовый синий)
                    r = 42
                    g = 92
                    b = 210
                    a = 255

                case .blackAndWhite:
                    // 2. Чёрно-белая обложка (градиент серого без насыщенности -> проверка grayscale fallback шагом i += 16)
                    let v = UInt8(clamping: 28 + ((x + y) * 180) / (w + h))
                    r = v
                    g = v
                    b = v
                    a = 255

                case .darkWithRedAccent:
                    // 3. Тёмная обложка с ярким красным акцентом в центре
                    let dx = x - 32
                    let dy = y - 32
                    if dx * dx + dy * dy <= 100 {
                        r = 232
                        g = 38
                        b = 66
                    } else {
                        r = 16
                        g = 18
                        b = 26
                    }
                    a = 255

                case .vividMulticolor:
                    // 4. Яркая многоцветная обложка (4 квадранта: пурпурный, бирюзовый, золотистый, фиолетовый)
                    if x < 32 && y < 32 {
                        r = 218; g = 44; b = 136
                    } else if x >= 32 && y < 32 {
                        r = 24; g = 196; b = 212
                    } else if x < 32 && y >= 32 {
                        r = 242; g = 168; b = 36
                    } else {
                        r = 116; g = 56; b = 228
                    }
                    a = 255

                case .pastel:
                    // 5. Пастельная обложка (lum > 0.55 && sat in [0.04, 0.40) -> проверка pastelBoost = 1.35 и pastel-ветки в toMeshTint)
                    if (x + y) % 2 == 0 {
                        r = 214; g = 176; b = 224 // пастельно-лавандовый
                    } else {
                        r = 176; g = 212; b = 230 // пастельно-небесный
                    }
                    a = 255

                case .transparent:
                    // 6. Полностью прозрачная обложка (a < 32 -> пустая палитра -> DEFAULT_PALETTE + DEFAULT_UI_ACCENT)
                    r = 0; g = 0; b = 0; a = 0

                case .neutralDominant:
                    // 7. Преобладание нейтральных оттенков (85% тёплый серый, 15% умеренный янтарно-изумрудный акцент)
                    if x >= 24 && x < 40 && y >= 24 && y < 40 {
                        r = 46; g = 184; b = 138
                    } else {
                        r = 96; g = 98; b = 102
                    }
                    a = 255
                }

                bytes[idx] = r
                bytes[idx + 1] = g
                bytes[idx + 2] = b
                bytes[idx + 3] = a
            }
        }
        return bytes
    }
}
