import XCTest
#if canImport(BebranoidCore)
@testable import BebranoidCore
#else
@testable import Bebranoid
#endif

final class YouTubeServiceParsingTests: XCTestCase {
    private func lockup(id: String, title: String, author: String, duration: String) -> [String: Any] {
        [
            "lockupViewModel": [
                "contentId": id,
                "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "contentImage": [
                    "thumbnailViewModel": [
                        "overlays": [
                            ["thumbnailBottomOverlayViewModel": [
                                "badges": [["thumbnailBadgeViewModel": ["text": duration]]]
                            ]]
                        ]
                    ]
                ],
                "metadata": [
                    "lockupMetadataViewModel": [
                        "title": ["content": title],
                        "metadata": [
                            "contentMetadataViewModel": [
                                "metadataRows": [["metadataParts": [["text": ["content": author]]]]]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    func testParsesLockupViewModelPageWithContinuation() {
        let continuation: [String: Any] = [
            "continuationItemViewModel": [
                "continuationCommand": [
                    "innertubeCommand": [
                        "continuationCommand": ["token": "TOKEN123"]
                    ]
                ]
            ]
        ]
        let json: [String: Any] = [
            "contents": [
                "itemSectionRenderer": [
                    "contents": [
                        lockup(id: "fOT0BUpITw8", title: "Peso Pluma - BELLAKEO", author: "Peso Pluma", duration: "3:55"),
                        lockup(id: "vNF-RTZF6bc", title: "Some Song", author: "Some Artist - Topic", duration: "1:02:03"),
                        lockup(id: "L7mSNTMb5sY", title: "Deleted video", author: "", duration: "0:10"),
                        continuation
                    ]
                ]
            ]
        ]

        let page = YouTubeService.parsePlaylistPage(json: json, albumTitle: "РњРѕР№ РїР»РµР№Р»РёСЃС‚")

        XCTAssertEqual(page.tracks.count, 2)
        XCTAssertEqual(page.continuationToken, "TOKEN123")

        XCTAssertEqual(page.tracks[0].youtubeVideoId, "fOT0BUpITw8")
        XCTAssertEqual(page.tracks[0].artist, "Peso Pluma")
        XCTAssertEqual(page.tracks[0].title, "BELLAKEO")
        XCTAssertEqual(page.tracks[0].duration, 235, accuracy: 0.01)
        XCTAssertEqual(page.tracks[0].album, "РњРѕР№ РїР»РµР№Р»РёСЃС‚")

        XCTAssertEqual(page.tracks[1].artist, "Some Artist")
        XCTAssertEqual(page.tracks[1].title, "Some Song")
        XCTAssertEqual(page.tracks[1].duration, 3723, accuracy: 0.01)
    }

    func testParsesLegacyPlaylistVideoRenderer() {
        let json: [String: Any] = [
            "items": [
                ["playlistVideoRenderer": [
                    "videoId": "fOT0BUpITw8",
                    "title": ["runs": [["text": "Old Format"]]],
                    "shortBylineText": ["runs": [["text": "Old Channel"]]],
                    "lengthSeconds": "200"
                ]]
            ]
        ]
        let page = YouTubeService.parsePlaylistPage(json: json, albumTitle: "PL")
        XCTAssertEqual(page.tracks.count, 1)
        XCTAssertEqual(page.tracks[0].artist, "Old Channel")
        XCTAssertEqual(page.tracks[0].duration, 200, accuracy: 0.01)
        XCTAssertNil(page.continuationToken)
    }

    func testClockDurationParsing() {
        XCTAssertEqual(YouTubeService.parseClockDuration("3:55"), 235, accuracy: 0.01)
        XCTAssertEqual(YouTubeService.parseClockDuration("1:02:03"), 3723, accuracy: 0.01)
        XCTAssertEqual(YouTubeService.parseClockDuration("LIVE"), 0, accuracy: 0.01)
    }
}
