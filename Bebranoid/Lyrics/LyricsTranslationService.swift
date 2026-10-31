import Foundation

/// Порт модуля перевода текстов песен на русский язык (`electron/lyrics-translate.js` и `electron/main.js` 1:1).
/// Поддерживает:
/// - Пакетный перевод строк через `translateViaGoogleGtx` (с ротацией эндпоинтов `translate.googleapis.com`, `translate.google.com`, `clients5.google.com` и разбиением на батчи до 900 символов)
/// - Выравнивание переведённых строк по оригинальным таймкодам (`buildSyncedRuFromPlain`)
/// - Автоматический пропуск уже русскоязычных строк (кириллица `>= 40%`)
public final class LyricsTranslationService: @unchecked Sendable {
    public static let shared = LyricsTranslationService()

    public static let gtxEndpoints = [
        "https://translate.googleapis.com/translate_a/single",
        "https://translate.google.com/translate_a/single",
        "https://clients5.google.com/translate_a/t"
    ]

    public static let maxChunkCharacterLength = 900
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Проверяет, написан ли текст преимущественно кириллицей (на русском/украинском и др.)
    public static func isPredominantlyCyrillic(_ lines: [String]) -> Bool {
        let joined = lines.joined(separator: " ")
        var cyrillicCount = 0
        var letterCount = 0
        for scalar in joined.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                letterCount += 1
                if scalar.value >= 0x0400 && scalar.value <= 0x052F {
                    cyrillicCount += 1
                }
            }
        }
        guard letterCount > 0 else { return false }
        return Double(cyrillicCount) / Double(letterCount) >= 0.35
    }

    /// Разбивает массив строк на пакеты длиной `<= 900` символов (`electron/lyrics-translate.js`)
    public static func chunkLinesForGtx(_ lines: [String], maxChars: Int = maxChunkCharacterLength) -> [[String]] {
        var chunks: [[String]] = []
        var currentChunk: [String] = []
        var currentLength = 0

        for line in lines {
            let lineLen = line.count + 1
            if !currentChunk.isEmpty && (currentLength + lineLen > maxChars) {
                chunks.append(currentChunk)
                currentChunk = [line]
                currentLength = lineLen
            } else {
                currentChunk.append(line)
                currentLength += lineLen
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        return chunks
    }

    /// Переводит строки `ParsedLyricsDocument` на русский язык и возвращает обновлённый документ
    public func translateDocumentToRussian(_ document: ParsedLyricsDocument) async -> (document: ParsedLyricsDocument, translatedLines: [String]) {
        let sourceLines = document.lines.map { $0.text }
        guard !sourceLines.isEmpty, !Self.isPredominantlyCyrillic(sourceLines) else {
            return (document, [])
        }

        let chunks = Self.chunkLinesForGtx(sourceLines)
        var allTranslated: [String] = []

        for chunk in chunks {
            let joined = chunk.joined(separator: "\n")
            if let translatedChunk = await translateChunkViaGoogleGtx(text: joined) {
                let split = translatedChunk.components(separatedBy: "\n")
                for i in 0..<chunk.count {
                    let line = i < split.count ? split[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    allTranslated.append(line)
                }
            } else {
                allTranslated.append(contentsOf: Array(repeating: "", count: chunk.count))
            }
        }

        let updatedDoc = LyricsService.attachTranslations(allTranslated, to: document)
        return (updatedDoc, allTranslated)
    }

    private func translateChunkViaGoogleGtx(text: String) async -> String? {
        for (index, baseEndpoint) in Self.gtxEndpoints.enumerated() {
            var comps = URLComponents(string: baseEndpoint)
            if index < 2 {
                comps?.queryItems = [
                    URLQueryItem(name: "client", value: "gtx"),
                    URLQueryItem(name: "sl", value: "auto"),
                    URLQueryItem(name: "tl", value: "ru"),
                    URLQueryItem(name: "dt", value: "t"),
                    URLQueryItem(name: "q", value: text)
                ]
            } else {
                comps?.queryItems = [
                    URLQueryItem(name: "client", value: "dict-chrome-ex"),
                    URLQueryItem(name: "sl", value: "auto"),
                    URLQueryItem(name: "tl", value: "ru"),
                    URLQueryItem(name: "q", value: text)
                ]
            }

            guard let url = comps?.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8.0
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                continue
            }

            if let parsed = Self.parseGtxResponseData(data) {
                return parsed
            }
        }
        return nil
    }

    /// Парсит вложенный JSON массив ответа `translate_a/single` (`[[["перевод", "оригинал", ...], ...]]`)
    public static func parseGtxResponseData(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }

        if let outerArray = root as? [Any],
           let sentencesArray = outerArray.first as? [Any] {
            var builder = ""
            for item in sentencesArray {
                if let pair = item as? [Any], let translatedSegment = pair.first as? String {
                    builder.append(translatedSegment)
                }
            }
            let result = builder.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }

        if let stringArray = root as? [String], let first = stringArray.first {
            return first
        }
        return nil
    }

    /// Выравнивает несинхронизированный русский перевод по строкам синхронизированного оригинала (`buildSyncedRuFromPlain` в `electron/lyrics-translate.js`)
    public static func alignPlainRussianLines(originalLines: [LyricLineItem], plainRussianText: String) -> [String] {
        let ruLines = plainRussianText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !ruLines.isEmpty, !originalLines.isEmpty else { return [] }

        var result: [String] = []
        for i in 0..<originalLines.count {
            let mappedIndex = Int(floor(Double(i) * Double(ruLines.count) / Double(originalLines.count)))
            let safeIndex = min(ruLines.count - 1, max(0, mappedIndex))
            result.append(ruLines[safeIndex])
        }
        return result
    }
}
