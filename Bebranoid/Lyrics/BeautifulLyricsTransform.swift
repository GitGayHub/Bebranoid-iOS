import Foundation

public struct BeautifulSyllableMetadata: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var text: String
    public var startTime: Double
    public var endTime: Double
    public var isPartOfWord: Bool
    public var isEmphasized: Bool

    public var duration: Double {
        max(0.05, endTime - startTime)
    }

    public init(
        id: Int,
        text: String,
        startTime: Double,
        endTime: Double,
        isPartOfWord: Bool = false,
        isEmphasized: Bool = false
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isPartOfWord = isPartOfWord
        self.isEmphasized = isEmphasized
    }
}

public struct BeautifulVocalLineGroup: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var lineIndex: Int
    public var startTime: Double
    public var endTime: Double
    public var mainText: String
    public var backgroundText: String?
    public var syllables: [BeautifulSyllableMetadata]
    public var romanizedText: String?
    public var translatedText: String?
    public var isRightAligned: Bool

    public init(
        id: String,
        lineIndex: Int,
        startTime: Double,
        endTime: Double,
        mainText: String,
        backgroundText: String? = nil,
        syllables: [BeautifulSyllableMetadata] = [],
        romanizedText: String? = nil,
        translatedText: String? = nil,
        isRightAligned: Bool = false
    ) {
        self.id = id
        self.lineIndex = lineIndex
        self.startTime = startTime
        self.endTime = endTime
        self.mainText = mainText
        self.backgroundText = backgroundText
        self.syllables = syllables
        self.romanizedText = romanizedText
        self.translatedText = translatedText
        self.isRightAligned = isRightAligned
    }
}

public enum BeautifulTimelineNode: Codable, Equatable, Hashable, Sendable, Identifiable {
    case interlude(id: String, startTime: Double, endTime: Double)
    case vocal(BeautifulVocalLineGroup)

    public var id: String {
        switch self {
        case .interlude(let id, _, _): return id
        case .vocal(let group): return group.id
        }
    }

    public var startTime: Double {
        switch self {
        case .interlude(_, let start, _): return start
        case .vocal(let group): return group.startTime
        }
    }

    public var endTime: Double {
        switch self {
        case .interlude(_, _, let end): return end
        case .vocal(let group): return group.endTime
        }
    }
}

/// Точный 1:1 порт `src/beautiful-lyrics/transform.js` и `SyllableVocals.js` (`IsEmphasized`).
/// - Выделяет инструментальные паузы (`Interlude`) перед первой строкой (`>= 2.2s`) и между строками (`>= 3.0s`)
/// - Отделяет бэк-вокал в круглых скобках в конце строки (`BackgroundText`)
/// - Формирует послоговые метаданные и помечает ударные долгие слова (`duration >= 1.25s`, длина `2...10` букв) флагом `isEmphasized = true` для посимвольного рендеринга
public enum BeautifulLyricsTransform {
    public static let initialInterludeThresholdSec: Double = 2.2
    public static let betweenLinesInterludeThresholdSec: Double = 3.0
    public static let emphasisMinDurationSec: Double = 1.25
    public static let emphasisMinLetters: Int = 2
    public static let emphasisMaxLetters: Int = 10

    /// Разделяет текст строки на основной вокал и фоновый бэк-вокал в скобках в конце строки (`splitBackgroundVocals` в `transform.js`)
    public static func splitBackgroundVocals(_ rawText: String) -> (main: String, background: String?) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(.*?)\s*\(([^()]+)\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return (trimmed, nil)
        }

        let ns = trimmed as NSString
        let mainPart = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        let bgPart = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)

        if mainPart.isEmpty || bgPart.isEmpty {
            return (trimmed, nil)
        }
        return (mainPart, "(\(bgPart))")
    }

    /// Проверяет, должно ли слово получить посимвольный `Emphasized` эффект (`SyllableVocals.js`)
    public static func shouldEmphasizeWord(text: String, duration: Double, allowEmphasis: Bool = true) -> Bool {
        guard allowEmphasis, duration >= emphasisMinDurationSec else { return false }
        let cleanLetters = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        let count = cleanLetters.count
        return count >= emphasisMinLetters && count <= emphasisMaxLetters
    }

    /// Преобразует `ParsedLyricsDocument` в последовательность узлов `BeautifulTimelineNode` (`Interlude` + `Vocal`)
    public static func transform(document: ParsedLyricsDocument, allowEmphasis: Bool = true) -> [BeautifulTimelineNode] {
        let lines = document.lines
        guard !lines.isEmpty else { return [] }

        var nodes: [BeautifulTimelineNode] = []

        if document.kind != .plain {
            let firstStart = lines[0].time
            if firstStart >= initialInterludeThresholdSec {
                nodes.append(
                    .interlude(
                        id: "interlude_intro",
                        startTime: 0.0,
                        endTime: firstStart
                    )
                )
            }
        }

        for (index, line) in lines.enumerated() {
            // Проверяем паузу между предыдущей строкой и текущей
            if document.kind != .plain && index > 0 {
                let prevEnd = lines[index - 1].endTime
                let gap = line.time - prevEnd
                if gap >= betweenLinesInterludeThresholdSec {
                    nodes.append(
                        .interlude(
                            id: "interlude_\(index - 1)_\(index)",
                            startTime: prevEnd,
                            endTime: line.time
                        )
                    )
                }
            }

            let split = splitBackgroundVocals(line.text)
            let syllables = buildSyllables(for: line, mainText: split.main, syncKind: document.kind, allowEmphasis: allowEmphasis)

            let group = BeautifulVocalLineGroup(
                id: "vocal_\(index)_\(Int(line.time * 1000))",
                lineIndex: index,
                startTime: line.time,
                endTime: max(line.time + 0.3, line.endTime),
                mainText: split.main,
                backgroundText: split.background,
                syllables: syllables,
                romanizedText: line.romanized ?? Romanizer.romanizeLine(split.main),
                translatedText: line.translation,
                isRightAligned: false
            )
            nodes.append(.vocal(group))
        }

        return nodes
    }

    private static func buildSyllables(
        for line: LyricLineItem,
        mainText: String,
        syncKind: ParsedLyricsSyncKind,
        allowEmphasis: Bool
    ) -> [BeautifulSyllableMetadata] {
        if let words = line.words, !words.isEmpty {
            return words.enumerated().map { idx, token in
                let dur = max(0.05, token.endTime - token.time)
                let emph = shouldEmphasizeWord(text: token.text, duration: dur, allowEmphasis: allowEmphasis)
                return BeautifulSyllableMetadata(
                    id: idx,
                    text: token.text,
                    startTime: token.time,
                    endTime: token.endTime,
                    isPartOfWord: false,
                    isEmphasized: emph
                )
            }
        }

        // Для Line-synced строк синтезируем плавное распределение времени по словам пропорционально их длине (`transform.js`)
        let rawWords = mainText
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawWords.isEmpty, syncKind != .plain else {
            return []
        }

        let lineDuration = max(0.4, line.endTime - line.time)
        let totalWeight = Double(max(1, rawWords.reduce(0) { $0 + max(1, $1.count) }))

        var cursor = line.time
        var result: [BeautifulSyllableMetadata] = []

        for (idx, word) in rawWords.enumerated() {
            let weight = Double(max(1, word.count))
            let wordDur = lineDuration * (weight / totalWeight)
            let start = cursor
            let end = (idx == rawWords.count - 1) ? max(start + 0.08, line.endTime) : (start + wordDur)
            cursor = end

            let emph = shouldEmphasizeWord(text: word, duration: end - start, allowEmphasis: allowEmphasis && syncKind == .word)
            result.append(
                BeautifulSyllableMetadata(
                    id: idx,
                    text: word,
                    startTime: start,
                    endTime: end,
                    isPartOfWord: false,
                    isEmphasized: emph
                )
            )
        }

        return result
    }
}
