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

    func testParseYouTubeMusicTTMLSyllableMergingAndBgVocals() {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml" itunes:timing="Word">
          <body dur="3:21.570">
            <div begin="27.395" end="32.529">
              <p begin="30.189" end="32.529"><span begin="30.189" end="30.396">I&apos;ve</span> <span begin="31.498" end="31.839">long</span> <span begin="31.839" end="31.996">e</span><span begin="31.996" end="32.529">nough</span> <span ttm:role="x-bg" begin="32.000" end="32.500">(yeah)</span></p>
            </div>
          </body>
        </tt>
        """
        let doc = LRCParser.parseLRC(ttml)
        XCTAssertEqual(doc.kind, .word)
        XCTAssertEqual(doc.lines.count, 1)
        XCTAssertEqual(doc.lines[0].text, "I've long enough (yeah)")
        guard let words = doc.lines[0].words else {
            XCTFail("Expected merged TTML words")
            return
        }
        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(words[0].text, "I've")
        XCTAssertEqual(words[2].text, "enough")
        XCTAssertEqual(words[2].time, 31.839, accuracy: 1e-3)
        XCTAssertEqual(words[2].endTime, 32.529, accuracy: 1e-3)
    }

    func testParseRichSyncExplicitWordEndTags() {
        let raw = """
        [00:27.17] <00:27.17> I've <00:27.46>   <00:27.49> been <00:27.63>   <00:27.88> call <00:28.00>
        [00:29.98] <00:29.98> Next <00:30.40>
        """
        let doc = LRCParser.parseLRC(raw)
        XCTAssertEqual(doc.kind, .word)
        guard let words = doc.lines[0].words else {
            XCTFail("Expected RichSync words")
            return
        }
        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(words[0].endTime, 27.46, accuracy: 1e-3)
        XCTAssertEqual(words[2].text, "call")
        XCTAssertEqual(words[2].endTime, 28.00, accuracy: 1e-3)
    }

    func testPersonalTelegramChatDefaultsAndLegacyJsonDecoding() throws {
        let fresh = UserLibraryPersistentState()
        XCTAssertEqual(fresh.selectedTelegramChatId, "-1003734947911")
        XCTAssertEqual(fresh.selectedTelegramChatTitle, "AndroSend Облако")
        XCTAssertEqual(fresh.selectedTelegramArchiveChatId, "-1003890744365")
        XCTAssertEqual(fresh.selectedTelegramArchiveChatTitle, "AndroSend Архив")
        XCTAssertTrue(fresh.isGyroscope3DCoverEnabled)
        XCTAssertEqual(PlaylistShufflePreference.defaultLimit, 15)

        let legacyJSON = #"{"tracks":[],"playlists":[]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserLibraryPersistentState.self, from: legacyJSON)
        XCTAssertEqual(decoded.selectedTelegramChatId, "-1003734947911")
        XCTAssertTrue(decoded.isGyroscope3DCoverEnabled)
    }

    func testInterludeMarbleWaveAndInstrumentalMarkerStripping() {
        let raw = """
        [00:00.00] ...
        [00:06.00] First vocal line
        [00:08.50] ♪
        [00:14.50] Second vocal line
        """
        let doc = LRCParser.parseLRC(raw)
        XCTAssertEqual(doc.lines.count, 2)
        let nodes = BeautifulLyricsTransform.transform(document: doc)
        XCTAssertEqual(nodes.count, 4)

        let midFrame = InterludeEngine.evaluate(startTime: 0.0, endTime: 6.0, timestamp: 3.0)
        XCTAssertTrue(midFrame.isVisible)
        XCTAssertEqual(midFrame.dots.count, 3)

        let finalFrame = InterludeEngine.evaluate(startTime: 0.0, endTime: 6.0, timestamp: 5.85)
        XCTAssertTrue(finalFrame.isCountdownPhase)
        XCTAssertGreaterThan(finalFrame.dots[2].opacity, finalFrame.dots[0].opacity)
    }
}
