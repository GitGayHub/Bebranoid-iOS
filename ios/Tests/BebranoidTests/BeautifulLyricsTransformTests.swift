import XCTest
#if canImport(BebranoidCore)
@testable import BebranoidCore
#else
@testable import Bebranoid
#endif

final class BeautifulLyricsTransformTests: XCTestCase {
    func testSpringAnalyticalConvergence() {
        var criticallyDamped = Spring(initialValue: 0.0, dampingRatio: 1.0, frequency: 2.5)
        criticallyDamped.setGoal(1.0)

        var underDamped = Spring(initialValue: 0.0, dampingRatio: 0.65, frequency: 2.0)
        underDamped.setGoal(1.0)

        var overDamped = Spring(initialValue: 0.0, dampingRatio: 1.4, frequency: 2.0)
        overDamped.setGoal(1.0)

        for _ in 0..<240 {
            criticallyDamped.update(deltaTime: 1.0 / 60.0)
            underDamped.update(deltaTime: 1.0 / 60.0)
            overDamped.update(deltaTime: 1.0 / 60.0)
        }

        XCTAssertEqual(criticallyDamped.position, 1.0, accuracy: 1e-3)
        XCTAssertEqual(underDamped.position, 1.0, accuracy: 1e-3)
        XCTAssertEqual(overDamped.position, 1.0, accuracy: 1e-3)
        XCTAssertTrue(criticallyDamped.sleeping)
    }

    func testCubicSplineInterpolation() {
        let spline = CubicSpline(points: [
            .init(time: 0.0, value: 0.0),
            .init(time: 0.5, value: 0.5),
            .init(time: 1.0, value: 1.0)
        ])
        XCTAssertEqual(spline.evaluate(at: 0.0), 0.0, accuracy: 1e-6)
        XCTAssertEqual(spline.evaluate(at: 0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(spline.evaluate(at: 1.0), 1.0, accuracy: 1e-6)
        XCTAssertEqual(spline.evaluate(at: 0.25), 0.25, accuracy: 0.05)
    }

    func testTransformInterludesBackgroundVocalsAndEmphasis() {
        let raw = """
        [00:04.00] <00:04.00>Hello <00:04.50>shine <00:06.10>world (yeah yeah)
        [00:11.00] <00:11.00>Next <00:11.50>line
        """
        let doc = LRCParser.parseLRC(raw)
        let nodes = BeautifulLyricsTransform.transform(document: doc, allowEmphasis: true)

        // Ожидаем:
        // 0: Intro interlude (0.0 .. 4.0 >= 2.2s)
        // 1: Vocal line 0 ("Hello shine world", background "(yeah yeah)", слово "shine" длится 1.6s >= 1.25s -> isEmphasized = true)
        // 2: Mid interlude (between 00:06.30 and 00:11.00 >= 3.0s)
        // 3: Vocal line 1
        XCTAssertEqual(nodes.count, 4)

        if case .interlude(_, let s0, let e0) = nodes[0] {
            XCTAssertEqual(s0, 0.0, accuracy: 1e-3)
            XCTAssertEqual(e0, 4.0, accuracy: 1e-3)
        } else {
            XCTFail("Expected intro interlude at index 0")
        }

        if case .vocal(let group0) = nodes[1] {
            XCTAssertEqual(group0.mainText, "Hello shine world")
            XCTAssertEqual(group0.backgroundText, "(yeah yeah)")
            let shineSyl = group0.syllables.first { $0.text == "shine" }
            XCTAssertNotNil(shineSyl)
            XCTAssertTrue(shineSyl?.isEmphasized == true)
        } else {
            XCTFail("Expected vocal group at index 1")
        }
    }

    func testHangulAndCJKRomanization() {
        let hangul = "사랑해"
        let rom = Romanizer.romanizeLine(hangul)
        XCTAssertEqual(rom, "saranghae")
        XCTAssertNil(Romanizer.romanizeLine("Already Latin Text"))
    }
}
