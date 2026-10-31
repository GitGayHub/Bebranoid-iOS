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

/// Точный парсер LRC / Enhanced LRC (включая RichSync `<mm:ss.xx> слово <mm:ss.xx>`) и TTML (YouTube Music / BetterLyrics / Apple Music).
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

    /// Универсальный парсер таймкодов TTML (`"27.395"`, `"1:04.220"`, `"0:03:21.570"`, `"250ms"`, `"14.2s"`)
    public static func parseFlexibleTimestamp(_ raw: String?) -> Double? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        if s.hasSuffix("ms") {
            s.removeLast(2)
            return (Double(s) ?? 0.0) / 1000.0
        }
        if s.hasSuffix("s") {
            s.removeLast(1)
            return Double(s)
        }
        let parts = s.split(separator: ":").map(String.init)
        switch parts.count {
        case 1:
            return Double(parts[0])
        case 2:
            guard let m = Double(parts[0]), let sec = Double(parts[1]) else { return nil }
            return m * 60.0 + sec
        case 3:
            guard let h = Double(parts[0]), let m = Double(parts[1]), let sec = Double(parts[2]) else { return nil }
            return h * 3600.0 + m * 60.0 + sec
        default:
            return nil
        }
    }

    public static func decodeXMLEntities(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Парсит TTML-документ (`lyrics-api.boidu.dev` BetterLyrics for YouTube Music / Apple Music) с миллисекундной точностью слов и слогов
    public static func parseTTML(_ rawTTML: String) -> ParsedLyricsDocument {
        let pPattern = #"<p\b([^>]*)>([\s\S]*?)</p>"#
        let spanPattern = #"<span\b([^>]*)>([\s\S]*?)</span>"#
        let attrPattern = #"([A-Za-z0-9_:-]+)\s*=\s*"([^"]*)""#

        guard let pRegex = try? NSRegularExpression(pattern: pPattern, options: [.caseInsensitive]),
              let spanRegex = try? NSRegularExpression(pattern: spanPattern, options: [.caseInsensitive]),
              let attrRegex = try? NSRegularExpression(pattern: attrPattern, options: []) else {
            return ParsedLyricsDocument(kind: .plain, lines: [])
        }

        func parseAttributes(_ rawAttrs: String) -> [String: String] {
            let ns = rawAttrs as NSString
            var dict: [String: String] = [:]
            for m in attrRegex.matches(in: rawAttrs, options: [], range: NSRange(location: 0, length: ns.length)) {
                let k = ns.substring(with: m.range(at: 1)).lowercased()
                let v = ns.substring(with: m.range(at: 2))
                dict[k] = v
            }
            return dict
        }

        let nsDoc = rawTTML as NSString
        let pMatches = pRegex.matches(in: rawTTML, options: [], range: NSRange(location: 0, length: nsDoc.length))
        guard !pMatches.isEmpty else {
            return ParsedLyricsDocument(kind: .plain, lines: [])
        }

        var builtLines: [LyricLineItem] = []
        var anyWordTokens = false

        for pm in pMatches {
            let pAttrs = parseAttributes(nsDoc.substring(with: pm.range(at: 1)))
            let pBody = nsDoc.substring(with: pm.range(at: 2))
            guard let pStart = parseFlexibleTimestamp(pAttrs["begin"]) else { continue }
            let pEndAttr = parseFlexibleTimestamp(pAttrs["end"])

            // Отделяем вложенные фоновые бэк-вокальные `<span ttm:role="x-bg">...</span>`, чтобы не смешивать их с основными словами
            var mainBody = pBody
            var bgParts: [String] = []
            let bgSpanPattern = #"<span\b[^>]*ttm:role\s*=\s*"x-bg"[^>]*>([\s\S]*?)</span>"#
            if let bgRegex = try? NSRegularExpression(pattern: bgSpanPattern, options: [.caseInsensitive]) {
                let nsBodyForBg = pBody as NSString
                let bgMatches = bgRegex.matches(in: pBody, options: [], range: NSRange(location: 0, length: nsBodyForBg.length))
                for bgm in bgMatches.reversed() {
                    let inner = nsBodyForBg.substring(with: bgm.range(at: 1))
                    let stripped = decodeXMLEntities(
                        inner.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !stripped.isEmpty {
                        let cleanedBg = stripped.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                        if !cleanedBg.isEmpty {
                            bgParts.insert("(\(cleanedBg))", at: 0)
                        }
                    }
                    if let swiftRange = Range(bgm.range, in: mainBody) {
                        mainBody.removeSubrange(swiftRange)
                    }
                }
            }

            let nsMain = mainBody as NSString
            let spanMatches = spanRegex.matches(in: mainBody, options: [], range: NSRange(location: 0, length: nsMain.length))

            var mergedWords: [LyricWordToken] = []
            if !spanMatches.isEmpty {
                var prevSpanEndLocation: Int? = nil
                for sm in spanMatches {
                    let sAttrs = parseAttributes(nsMain.substring(with: sm.range(at: 1)))
                    let rawSpanText = decodeXMLEntities(
                        nsMain.substring(with: sm.range(at: 2))
                            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    )
                    let trimmedSpan = Self.stripInstrumentalOnlyMarkers(rawSpanText)
                    guard !trimmedSpan.isEmpty else {
                        prevSpanEndLocation = sm.range.location + sm.range.length
                        continue
                    }

                    let wStart = parseFlexibleTimestamp(sAttrs["begin"]) ?? pStart
                    let wEnd = parseFlexibleTimestamp(sAttrs["end"]) ?? max(wStart + 0.18, pEndAttr ?? (wStart + 0.35))

                    // Проверяем, был ли пробел между предыдущим `</span>` и текущим `<span` (склеиваем слоги одного слова: `<span>e</span><span>nough</span>` -> `"enough"`)
                    var shouldMergeWithPrevious = false
                    if let prevEnd = prevSpanEndLocation, sm.range.location >= prevEnd, !mergedWords.isEmpty {
                        let between = nsMain.substring(with: NSRange(location: prevEnd, length: sm.range.location - prevEnd))
                        let hasSpaceBetween = between.contains(where: { $0.isWhitespace })
                            || rawSpanText.first?.isWhitespace == true
                        if !hasSpaceBetween {
                            shouldMergeWithPrevious = true
                        }
                    }

                    if shouldMergeWithPrevious {
                        let lastIdx = mergedWords.count - 1
                        mergedWords[lastIdx].text += trimmedSpan
                        mergedWords[lastIdx].endTime = max(mergedWords[lastIdx].endTime, wEnd)
                    } else {
                        mergedWords.append(LyricWordToken(text: trimmedSpan, time: wStart, endTime: max(wStart + 0.06, wEnd)))
                    }

                    prevSpanEndLocation = sm.range.location + sm.range.length
                }
            }

            let baseText: String
            if !mergedWords.isEmpty {
                anyWordTokens = true
                baseText = mergedWords.map(\.text).joined(separator: " ")
            } else {
                baseText = Self.stripInstrumentalOnlyMarkers(
                    decodeXMLEntities(
                        mainBody.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    )
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                )
            }

            let fullLineText = Self.stripInstrumentalOnlyMarkers(
                ([baseText] + bgParts)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            )

            guard !fullLineText.isEmpty else { continue }

            let effectiveEnd = pEndAttr
                ?? mergedWords.last?.endTime
                ?? (pStart + 3.0)

            let idx = builtLines.count
            builtLines.append(
                LyricLineItem(
                    id: idx,
                    time: pStart,
                    endTime: max(pStart + 0.15, effectiveEnd),
                    text: fullLineText,
                    words: mergedWords.isEmpty ? nil : mergedWords,
                    romanized: Romanizer.romanizeLine(baseText)
                )
            )
        }

        guard !builtLines.isEmpty else {
            return ParsedLyricsDocument(kind: .plain, lines: [])
        }

        builtLines.sort { $0.time < $1.time }
        for i in 0..<builtLines.count {
            builtLines[i].id = i
        }

        return ParsedLyricsDocument(
            kind: anyWordTokens ? .word : .line,
            lines: builtLines
        )
    }

    /// Парсит LRC / Enhanced LRC / RichSync / TTML или обычный текст в структурированный документ `ParsedLyricsDocument`
    public static func parseLRC(_ rawText: String?) -> ParsedLyricsDocument {
        guard let raw = rawText?.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ParsedLyricsDocument(kind: .plain, lines: [])
        }

        let trimmedWhole = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedWhole.hasPrefix("<tt") || trimmedWhole.contains("<tt ") {
            let ttmlDoc = parseTTML(trimmedWhole)
            if !ttmlDoc.lines.isEmpty {
                return ttmlDoc
            }
        }

        let lineRegex = try? NSRegularExpression(pattern: lineTagPattern, options: [])
        let wordRegex = try? NSRegularExpression(pattern: wordTagPattern, options: [])

        let rawLines = raw.components(separatedBy: "\n")
        var syncedEntries: [(time: Double, text: String, rawWords: [(time: Double, explicitEnd: Double?, text: String)]?)] = []
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

            // Проверяем наличие внутристрочных караоке-тегов `<mm:ss.xx>слово` и закрывающих `<mm:ss.xx>` (RichSync)
            let nsBody = body as NSString
            let bodyRange = NSRange(location: 0, length: nsBody.length)
            let wordMatches = wordRegex?.matches(in: body, options: [], range: bodyRange) ?? []

            var extractedWords: [(time: Double, explicitEnd: Double?, text: String)]?
            var cleanLineText = body

            if !wordMatches.isEmpty {
                var parsedWords: [(time: Double, explicitEnd: Double?, text: String)] = []
                for wm in wordMatches {
                    let minStr = nsBody.substring(with: wm.range(at: 1))
                    let secStr = nsBody.substring(with: wm.range(at: 2))
                    let fracRange = wm.range(at: 3)
                    let fracStr = fracRange.location != NSNotFound ? nsBody.substring(with: fracRange) : nil
                    let wTime = parseTimeComponents(minStr: minStr, secStr: secStr, fracStr: fracStr)
                    let rawWord = nsBody.substring(with: wm.range(at: 4))
                    let wText = rawWord
                        .replacingOccurrences(of: "♪", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !wText.isEmpty {
                        parsedWords.append((time: wTime, explicitEnd: nil, text: wText))
                    } else if !parsedWords.isEmpty && parsedWords[parsedWords.count - 1].explicitEnd == nil && wTime >= parsedWords[parsedWords.count - 1].time {
                        // Закрывающий тег `<mm:ss.xx>` из YouTube Music / SimpMusic RichSync задаёт точный конец слова
                        parsedWords[parsedWords.count - 1].explicitEnd = wTime
                    }
                }
                if !parsedWords.isEmpty {
                    hasWordSync = true
                    extractedWords = parsedWords
                    cleanLineText = parsedWords.map { $0.text }.joined(separator: " ")
                }
            }

            // Удаляем возможные оставшиеся угловые теги и декоративные ноты `♪` / троеточия пауз (`...`, `…`) из субтитров
            cleanLineText = Self.stripInstrumentalOnlyMarkers(
                cleanLineText
                    .replacingOccurrences(of: #"<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "♪", with: "")
                    .replacingOccurrences(of: "♫", with: "")
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            )
            if cleanLineText.isEmpty {
                extractedWords = nil
            }

            for ts in lineTimestamps {
                syncedEntries.append((time: ts, text: cleanLineText, rawWords: extractedWords))
            }
        }

        // Если синхронизированных строк нет — возвращаем plain-текст (отфильтровывая мета-теги [ar:...], [ti:...])
        if syncedEntries.isEmpty {
            let plainLines = rawLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("[ar:") && !$0.hasPrefix("[ti:") && !$0.hasPrefix("[al:") && !$0.hasPrefix("[by:") && !$0.hasPrefix("[length:") && !$0.hasPrefix("[offset:") }
                .enumerated()
                .map { idx, text in
                    LyricLineItem(id: idx, time: 0, endTime: 0, text: text)
                }
            return ParsedLyricsDocument(kind: .plain, lines: plainLines)
        }

        syncedEntries.sort { $0.time < $1.time }

        // Отфильтровываем технические пометки субтитров YouTube вроде `(upbeat music)` или `[Music]`, если есть реальный вокал
        let nonCaptionCount = syncedEntries.filter { !Self.isClosedCaptionNoiseLine($0.text) && !$0.text.isEmpty }.count

        var builtLines: [LyricLineItem] = []
        for i in 0..<syncedEntries.count {
            let entry = syncedEntries[i]
            let nextTime: Double = (i + 1 < syncedEntries.count)
                ? max(entry.time + 0.25, syncedEntries[i + 1].time)
                : (entry.time + 5.0)

            if entry.text.isEmpty {
                continue
            }
            if nonCaptionCount >= 3 && Self.isClosedCaptionNoiseLine(entry.text) {
                continue
            }

            var finalizedWords: [LyricWordToken]?
            var effectiveLineEndTime = nextTime
            if let rw = entry.rawWords, !rw.isEmpty {
                var tokens: [LyricWordToken] = []
                for wi in 0..<rw.count {
                    let wStart = rw[wi].time
                    let wEnd: Double
                    if let expEnd = rw[wi].explicitEnd, expEnd > wStart + 0.04 {
                        wEnd = expEnd
                    } else if wi + 1 < rw.count {
                        wEnd = max(wStart + 0.08, rw[wi + 1].time)
                    } else if nextTime - wStart >= 3.5 {
                        wEnd = wStart + 0.45
                    } else {
                        wEnd = max(wStart + 0.20, nextTime)
                    }
                    tokens.append(LyricWordToken(text: rw[wi].text, time: wStart, endTime: wEnd))
                }
                finalizedWords = tokens
                if let lastTokenEnd = tokens.last?.endTime {
                    effectiveLineEndTime = lastTokenEnd
                }
            } else {
                // Как в десктопном `transform.js`: если между line-synced строками огромный проигрыш (>= 18 с) без пустого маркера,
                // ограничиваем длительность вокальной строки естественной оценкой, чтобы показать 3 точки `Interlude`
                let rawGap = nextTime - entry.time
                if rawGap >= 18.0 {
                    let estimatedVocalSec = min(12.0, max(1.8, Double(entry.text.count) / 11.0 + 0.8))
                    if rawGap - estimatedVocalSec >= 3.5 {
                        effectiveLineEndTime = entry.time + estimatedVocalSec
                    }
                }
            }

            let lineIndex = builtLines.count
            let romanized = Romanizer.romanizeLine(entry.text)
            builtLines.append(
                LyricLineItem(
                    id: lineIndex,
                    time: entry.time,
                    endTime: effectiveLineEndTime,
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

    /// Превращает строки-заглушки инструментала (`♪`, `♫`, `...`, `…`, `•••`) в пустой маркер паузы, чтобы вместо текстовых точек рисовалась волна `Interlude`
    private static func stripInstrumentalOnlyMarkers(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let markerChars = CharacterSet(charactersIn: "♪♫♩♬.…•·-–—~* \t\n\r")
        if trimmed.unicodeScalars.allSatisfy({ markerChars.contains($0) }) {
            return ""
        }
        return trimmed
    }

    private static func isClosedCaptionNoiseLine(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard (lower.hasPrefix("(") && lower.hasSuffix(")")) || (lower.hasPrefix("[") && lower.hasSuffix("]")) else {
            return false
        }
        let noiseKeywords = ["music", "applause", "instrumental", "playing", "intro", "outro", "музыка", "инструментал", "аплодисменты"]
        return noiseKeywords.contains(where: { lower.contains($0) })
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
