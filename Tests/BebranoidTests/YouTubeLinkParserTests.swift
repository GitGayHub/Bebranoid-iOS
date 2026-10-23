import XCTest
#if canImport(BebranoidCore)
@testable import BebranoidCore
#else
@testable import Bebranoid
#endif

final class YouTubeLinkParserTests: XCTestCase {
    func testParsePlaylistAndVideoURLs() {
        let pl = YouTubeLinkParser.parseInput("https://www.youtube.com/playlist?list=PL1234567890abcdef")
        XCTAssertEqual(pl.kind, .playlist)
        XCTAssertEqual(pl.playlistId, "PL1234567890abcdef")

        let ytMusicPl = YouTubeLinkParser.parseInput("https://music.youtube.com/playlist?list=OLAK5uy_n1234567890")
        XCTAssertEqual(ytMusicPl.kind, .playlist)
        XCTAssertEqual(ytMusicPl.playlistId, "OLAK5uy_n1234567890")

        let watchVideo = YouTubeLinkParser.parseInput("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(watchVideo.kind, .video)
        XCTAssertEqual(watchVideo.videoId, "dQw4w9WgXcQ")

        let shortVideo = YouTubeLinkParser.parseInput("https://youtube.com/shorts/dQw4w9WgXcQ?feature=share")
        XCTAssertEqual(shortVideo.kind, .video)
        XCTAssertEqual(shortVideo.videoId, "dQw4w9WgXcQ")

        let youtuBe = YouTubeLinkParser.parseInput("https://youtu.be/dQw4w9WgXcQ")
        XCTAssertEqual(youtuBe.kind, .video)
        XCTAssertEqual(youtuBe.videoId, "dQw4w9WgXcQ")

        let bareId = YouTubeLinkParser.parseInput("dQw4w9WgXcQ")
        XCTAssertEqual(bareId.kind, .video)
        XCTAssertEqual(bareId.videoId, "dQw4w9WgXcQ")
    }

    func testArtistSplitterCollaborations() {
        let split = ArtistSplitter.splitArtists("Kizaru feat. Big Baby Tape & Friendly Thug 52 NGG x Alblak 52")
        XCTAssertEqual(split, ["Kizaru", "Big Baby Tape", "Friendly Thug 52 NGG", "Alblak 52"])

        let best = ArtistSplitter.pickBestSpelling(["кино": 2, "КИНО": 1, "Кино": 1])
        XCTAssertEqual(best, "Кино")
    }

    func testPlaylistContinuationTokenExtractionAndMultiPageDeduplication() {
        let page1HTML = """
        <meta property="og:title" content="Synth &amp; Ambient">
        {"playlistVideoRenderer":{"videoId":"vid00000001","title":{"runs":[{"text":"Kino - Gruppa Krovi"}]}}}
        {"continuationCommand":{"token":"CONT_TOKEN_PAGE_2"}}
        """

        let parsedPage1 = YouTubeService.parsePlaylistFromHTML(html: page1HTML, playlistId: "PLTest01")
        XCTAssertEqual(parsedPage1.title, "Synth & Ambient")
        XCTAssertEqual(parsedPage1.tracks.count, 1)
        XCTAssertEqual(parsedPage1.tracks[0].youtubeVideoId, "vid00000001")
        XCTAssertEqual(parsedPage1.nextContinuationToken, "CONT_TOKEN_PAGE_2")

        var seen = Set(parsedPage1.tracks.compactMap { $0.youtubeVideoId })
        let page2JSON = """
        {"playlistVideoRenderer":{"videoId":"vid00000001","title":{"runs":[{"text":"Duplicate"}]}}}
        {"playlistVideoRenderer":{"videoId":"vid00000002","title":{"runs":[{"text":"M83 - Midnight City"}]}}}
        """
        let parsedPage2 = YouTubeService.extractPlaylistItemsAndToken(
            fromRawText: page2JSON,
            playlistTitle: parsedPage1.title,
            seenVideoIds: &seen,
            remainingLimit: 5000
        )
        XCTAssertEqual(parsedPage2.tracks.count, 1)
        XCTAssertEqual(parsedPage2.tracks[0].youtubeVideoId, "vid00000002")
        XCTAssertNil(parsedPage2.nextToken)
    }

    func testInspectPlayerResponseDirectAndSignatureCipherHonestError() throws {
        let directPayload: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": [
                "adaptiveFormats": [
                    [
                        "itag": 140,
                        "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
                        "url": "https://rr1---sn-test.googlevideo.com/videoplayback?itag=140"
                    ]
                ]
            ]
        ]
        let streamURL = try YouTubeService.inspectPlayerResponseJSON(directPayload)
        XCTAssertEqual(streamURL.absoluteString, "https://rr1---sn-test.googlevideo.com/videoplayback?itag=140")

        let cipherPayload: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": [
                "adaptiveFormats": [
                    [
                        "itag": 140,
                        "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
                        "signatureCipher": "s=ABCD&sp=sig&url=https://rr1.googlevideo.com/videoplayback"
                    ]
                ]
            ]
        ]
        XCTAssertThrowsError(try YouTubeService.inspectPlayerResponseJSON(cipherPayload)) { error in
            let nsErr = error as NSError
            XCTAssertEqual(nsErr.code, 424)
            XCTAssertTrue(nsErr.localizedDescription.contains("signatureCipher"))
        }
    }
}
