import Foundation

/// Точный порт `src/beautiful-lyrics/romanize.js` (`romanizeLine`).
/// Автоматически определяет японский (Kana/Kanji), корейский (Hangul) и китайский (Hanzi) скрипты
/// и возвращает латинскую транслитерацию (Hepburn / Revised Romanization / Pinyin).
public enum Romanizer {
    private static let hangulLeads = [
        "g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s",
        "ss", "", "j", "jj", "ch", "k", "t", "p", "h"
    ]
    private static let hangulVowels = [
        "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa",
        "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"
    ]
    private static let hangulTails = [
        "", "k", "k", "ks", "n", "nj", "nh", "t", "l", "lg",
        "lm", "lb", "ls", "lt", "lp", "lh", "m", "p", "bs", "t",
        "t", "ng", "t", "t", "k", "t", "p", "h"
    ]

    /// Проверяет, содержит ли строка символы CJK / Kana / Hangul
    public static func containsCJKOrKanaOrHangul(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (v >= 0x3040 && v <= 0x30FF) ||
               (v >= 0x4E00 && v <= 0x9FFF) ||
               (v >= 0xAC00 && v <= 0xD7AF) ||
               (v >= 0x3130 && v <= 0x318F) {
                return true
            }
        }
        return false
    }

    public static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }
    }

    /// Романизирует строку, если она содержит японские, корейские или китайские символы.
    /// Если строка уже на латинице/кириллице — возвращает `nil`.
    public static func romanizeLine(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, containsCJKOrKanaOrHangul(trimmed) else {
            return nil
        }

        if containsHangul(trimmed) {
            let hangulResult = romanizeHangul(trimmed)
            if !hangulResult.isEmpty && hangulResult != trimmed {
                return hangulResult
            }
        }

        guard let latin = trimmed.applyingTransform(.toLatin, reverse: false),
              let stripped = latin.applyingTransform(.stripCombiningMarks, reverse: false) else {
            return nil
        }

        let transformed = stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transformed.isEmpty, transformed.lowercased() != trimmed.lowercased() else {
            return nil
        }
        return transformed
    }

    /// Точный порт декомпозиции слогов Хангыля (`0xAC00 ... 0xD7A3`) из `src/beautiful-lyrics/romanize.js`
    public static func romanizeHangul(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            let code = Int(scalar.value)
            if code >= 0xAC00 && code <= 0xD7A3 {
                let syllableIndex = code - 0xAC00
                let leadIndex = syllableIndex / (21 * 28)
                let vowelIndex = (syllableIndex % (21 * 28)) / 28
                let tailIndex = syllableIndex % 28

                let lead = hangulLeads[leadIndex]
                let vowel = hangulVowels[vowelIndex]
                let tail = hangulTails[tailIndex]
                output.append(lead + vowel + tail)
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
