import XCTest
#if canImport(BebranoidCore)
@testable import BebranoidCore
#else
@testable import Bebranoid
#endif

final class LRCParserTests: XCTestCase {
    func testParseLineSyncedLRC() {
        let raw = """
        [ar:Кино]
        [ti:Группа крови]
        [00:15.20] Тёплыйтрикотажный свет
        [00:19.50] На рукаве мой порядковый номер
        [00:24.00] На рукаве
        """

        let doc = LRCParser.parseLRC(raw)
        XCTAssertEqual(doc.kind, .line)
        XCTAssertEqual(doc.lines.count, 3)
        XCTAssertEqual(doc.lines[0].time, 15.20, accuracy: 1e-3)
        XCTAssertEqual(doc.lines[0].endTime, 19.50, accuracy: 1e-3)
        XCTAssertEqual(doc.lines[1].text, "На рукаве мой порядковый номер")

        XCTAssertEqual(LRCParser.findActiveLineIndex(lines: doc.lines, currentTime: 5.0), -1)
        XCTAssertEqual(LRCParser.findActiveLineIndex(lines: doc.lines, currentTime: 16.0), 0)
        XCTAssertEqual(LRCParser.findActiveLineIndex(lines: doc.lines, currentTime: 21.0), 1)
        XCTAssertEqual(LRCParser.findActiveLineIndex(lines: doc.lines, currentTime: 30.0), 2)
    }

    func testParseWordSyncedEnhancedLRC() {
        let raw = """
        [00:05.00] <00:05.00>Stay <00:05.80>with <00:06.40>me <00:08.00>tonight
        [00:10.50] <00:10.50>In <00:11.00>the <00:11.60>city
        """

        let doc = LRCParser.parseLRC(raw)
        XCTAssertEqual(doc.kind, .word)
        XCTAssertEqual(doc.lines.count, 2)
        guard let words = doc.lines[0].words else {
            XCTFail("Expected word tokens")
            return
        }
        XCTAssertEqual(words.count, 4)
        XCTAssertEqual(words[0].text, "Stay")
        XCTAssertEqual(words[0].time, 5.0, accuracy: 1e-3)
        XCTAssertEqual(words[0].endTime, 5.8, accuracy: 1e-3)
        XCTAssertEqual(LRCParser.findActiveWordIndex(words: words, currentTime: 6.5), 2)
    }

    func testParsePlainLyricsFallback() {
        let raw = """
        First plain line
        Second plain line
        """
        let doc = LRCParser.parseLRC(raw)
        XCTAssertEqual(doc.kind, .plain)
        XCTAssertEqual(doc.lines.count, 2)
        XCTAssertEqual(doc.lines[0].text, "First plain line")
    }
}
