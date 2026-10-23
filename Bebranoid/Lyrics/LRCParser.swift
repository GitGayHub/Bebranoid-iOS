import Foundation

public enum ParsedLyricsSyncKind: String, Codable, Sendable {
    case word = "word"
    case line = "line"
    case plain = "plain"
}

public struct LyricWordToken: Codable, Equatable, Hashable, Sendable {
    public var text: String
    public var time: Double
    public var endTime: Double

    public init(text: String, time: Double, endTime: Double) {
        self.text = text
        self.time = time
        self.endTime = endTime
    }
}

public struct LyricLineItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var time: Double
    public var endTime: Double
    public var text: String
    public var words: [LyricWordToken]?
    public var translation: String?
    public var romanized: String?

    public init(
        id: Int,
        time: Double,
        endTime: Double,
        text: String,
        words: [LyricWordToken]? = nil,
        translation: String? = nil,
        romanized: String? = nil
    ) {
        self.id = id
        self.time = time
        self.endTime = endTime
        self.text = text
        self.words = words
        self.translation = translation
        self.romanized = romanized
    }
}

public struct ParsedLyricsDocument: Codable, Equatable, Sendable {
    public var kind: ParsedLyricsSyncKind
    public var lines: [LyricLineItem]

    public init(kind: ParsedLyricsSyncKind, lines: [LyricLineItem]) {
        self.kind = kind
        self.lines = lines
    }
}

/// Точный 1:1 порт `src/lib/lyrics.js` (`parseLrc`, `findActiveLineIndex`, `findActiveWordIndex`)
public enum LRCParser {
    private static let lineTagPattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
    private static let wordTagPattern = #"<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>([^<]*)"#

    private static func parseTimeComponents(minStr: String, secStr: String, fracStr: String?) -> Double {
        let mins = Double(minStr) ?? 0.0
        let secs = Double(secStr) ?? 0.0
        var frac = 0.0
        if let f = fracStr, !f.isEmpty {
            let val = Double(f) ?? 0.0
            frac = f.count == 3 ? (val / 1000.0) : (f.count == 2 ? (val / 100.0) : (val / 10.0))
        }
        return mins * 60.0 + secs + frac
    }

    /// Парсит LRC / Enhanced LRC или обычный текст в структурированный документ `ParsedLyricsDocument`
    public static func parseLRC(_ rawText: String?) -> ParsedLyricsDocument {
        guard let raw = rawText?.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ParsedLyricsDocument(kind: .plain, lines: [])
        }

        let lineRegex = try? NSRegularExpression(pattern: lineTagPattern, options: [])
        let wordRegex = try? NSRegularExpression(pattern: wordTagPattern, options: [])

        let rawLines = raw.components(separatedBy: "\n")
        var syncedEntries: [(time: Double, text: String, rawWords: [(time: Double, text: String)]?)] = []
        var hasWordSync = false

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let nsLine = trimmed as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            guard let lineMatches = lineRegex?.matches(in: trimmed, options: [], range: fullRange),
                  !lineMatches.isEmpty else {
                continue
            }

            // Находим конец последнего тега `[mm:ss.xx]` в начале строки
            var contentStartIndex = 0
            var lineTimestamps: [Double] = []

            for match in lineMatches {
                if match.range.location <= contentStartIndex + 1 {
                    let minStr = nsLine.substring(with: match.range(at: 1))
                    let secStr = nsLine.substring(with: match.range(at: 2))
                    let fracRange = match.range(at: 3)
                    let fracStr = fracRange.location != NSNotFound ? nsLine.substring(with: fracRange) : nil
                    lineTimestamps.append(parseTimeComponents(minStr: minStr, secStr: secStr, fracStr: fracStr))
                    contentStartIndex = match.range.location + match.range.length
                }
            }

            guard !lineTimestamps.isEmpty else { continue }
            let body = nsLine.substring(from: contentStartIndex).trimmingCharacters(in: .whitespacesAndNewlines)

            // Проверяем наличие внутристрочных караоке-тегов `<mm:ss.xx>слово`
            let nsBody = body as NSString
            let bodyRange = NSRange(location: 0, length: nsBody.length)
            let wordMatches = wordRegex?.matches(in: body, options: [], range: bodyRange) ?? []

            var extractedWords: [(time: Double, text: String)]?
            var cleanLineText = body

            if !wordMatches.isEmpty {
                var parsedWords: [(time: Double, text: String)] = []
                for wm in wordMatches {
                    let minStr = nsBody.substring(with: wm.range(at: 1))
                    let secStr = nsBody.substring(with: wm.range(at: 2))
                    let fracRange = wm.range(at: 3)
                    let fracStr = fracRange.location != NSNotFound ? nsBody.substring(with: fracRange) : nil
                    let wTime = parseTimeComponents(minStr: minStr, secStr: secStr, fracStr: fracStr)
                    let wText = nsBody.substring(with: wm.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !wText.isEmpty {
                        parsedWords.append((time: wTime, text: wText))
                    }
                }
                if !parsedWords.isEmpty {
                    hasWordSync = true
                    extractedWords = parsedWords
                    cleanLineText = parsedWords.map { $0.text }.joined(separator: " ")
                }
            }

            // Удаляем возможные оставшиеся угловые теги
            cleanLineText = cleanLineText.replacingOccurrences(
                of: #"<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>"#,
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            for ts in lineTimestamps {
                syncedEntries.append((time: ts, text: cleanLineText, rawWords: extractedWords))
            }
        }

        // Если синхронизированных строк нет — возвращаем plain-текст (отфильтровывая мета-теги [ar:...], [ti:...])
        if syncedEntries.isEmpty {
            let plainLines = rawLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("[ar:") && !$0.hasPrefix("[ti:") && !$0.hasPrefix("[al:") && !$0.hasPrefix("[by:") && !$0.hasPrefix("[length:") }
                .enumerated()
                .map { idx, text in
                    LyricLineItem(id: idx, time: 0, endTime: 0, text: text)
                }
            return ParsedLyricsDocument(kind: .plain, lines: plainLines)
        }

        syncedEntries.sort { $0.time < $1.time }

        // Отфильтровываем пустые строки-разделители, но учитываем их таймкод как конец предыдущей строки
        var builtLines: [LyricLineItem] = []
        for i in 0..<syncedEntries.count {
            let entry = syncedEntries[i]
            let nextTime: Double = (i + 1 < syncedEntries.count)
                ? max(entry.time + 0.25, syncedEntries[i + 1].time)
                : (entry.time + 5.0)

            if entry.text.isEmpty {
                continue
            }

            var finalizedWords: [LyricWordToken]?
            if let rw = entry.rawWords, !rw.isEmpty {
                var tokens: [LyricWordToken] = []
                for wi in 0..<rw.count {
                    let wStart = rw[wi].time
                    let wEnd: Double = (wi + 1 < rw.count)
                        ? max(wStart + 0.08, rw[wi + 1].time)
                        : max(wStart + 0.20, nextTime)
                    tokens.append(LyricWordToken(text: rw[wi].text, time: wStart, endTime: wEnd))
                }
                finalizedWords = tokens
            }

            let lineIndex = builtLines.count
            let romanized = Romanizer.romanizeLine(entry.text)
            builtLines.append(
                LyricLineItem(
                    id: lineIndex,
                    time: entry.time,
                    endTime: nextTime,
                    text: entry.text,
                    words: finalizedWords,
                    romanized: romanized
                )
            )
        }

        return ParsedLyricsDocument(
            kind: hasWordSync ? .word : .line,
            lines: builtLines
        )
    }

    /// Находит индекс активной строки по текущему времени воспроизведения (`findActiveLineIndex` в `src/lib/lyrics.js`)
    public static func findActiveLineIndex(lines: [LyricLineItem], currentTime: Double) -> Int {
        guard !lines.isEmpty else { return -1 }
        if currentTime < lines[0].time {
            return -1
        }
        var active = 0
        for i in 0..<lines.count {
            if currentTime >= lines[i].time {
                active = i
            } else {
                break
            }
        }
        return active
    }

    /// Находит индекс активного слова внутри строки (`findActiveWordIndex` в `src/lib/lyrics.js`)
    public static func findActiveWordIndex(words: [LyricWordToken], currentTime: Double) -> Int {
        guard !words.isEmpty else { return -1 }
        if currentTime < words[0].time {
            return -1
        }
        var active = 0
        for i in 0..<words.count {
            if currentTime >= words[i].time {
                active = i
            } else {
                break
            }
        }
        return active
    }
}
