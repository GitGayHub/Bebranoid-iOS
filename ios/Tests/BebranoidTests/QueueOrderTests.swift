import XCTest
#if canImport(BebranoidCore)
@testable import BebranoidCore
#else
@testable import Bebranoid
#endif

final class QueueOrderTests: XCTestCase {
    private func makeDummyTrack(_ id: String) -> Track {
        Track(id: id, title: "Title \(id)", artist: "Artist", album: "Album", filename: "\(id).flac")
    }

    func testReshufflePreservesPastAndRotatesOnCollision() {
        let t0 = makeDummyTrack("1")
        let t1 = makeDummyTrack("2")
        let t2 = makeDummyTrack("3")
        let t3 = makeDummyTrack("4")
        let queue = [t0, t1, t2, t3]

        // При генераторе random() = 0.999999 Фишер-Йетс оставляет каждый элемент на своём месте (j == i),
        // поэтому срабатывает защита от коллизии (циклический сдвиг предстоящих треков на 1)
        let reshuffled = QueueOrder.reshuffleUpcoming(
            queue: queue,
            currentIndex: 1,
            sourceTracks: queue,
            random: { 0.999999 }
        )

        XCTAssertEqual(reshuffled.count, 4)
        // Проигранная часть 0...1 неприкосновенна
        XCTAssertEqual(reshuffled[0].id, "1")
        XCTAssertEqual(reshuffled[1].id, "2")
        // Предстоящая часть [3, 4] сдвинулась в [4, 3]
        XCTAssertEqual(reshuffled[2].id, "4")
        XCTAssertEqual(reshuffled[3].id, "3")
    }

    func testReshuffleDeduplicatesTracks() {
        let t0 = makeDummyTrack("1")
        let t1 = makeDummyTrack("2")
        let t2 = makeDummyTrack("3")
        let sourceWithDups = [t0, t1, t1, t2, t2]

        let result = QueueOrder.reshuffleUpcoming(
            queue: [t0],
            currentIndex: 0,
            sourceTracks: sourceWithDups,
            random: { 0.25 }
        )
        XCTAssertEqual(result.count, 3)
    }
}
