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

    func testParsesPlaylistFromHTMLWithYtInitialDataLockup() throws {
        let json: [String: Any] = [
            "metadata": [
                "playlistMetadataRenderer": [
                    "title": "spotify mod free apk"
                ]
            ],
            "contents": [
                "itemSectionRenderer": [
                    "contents": [
                        lockup(id: "fOT0BUpITw8", title: "Peso Pluma - BELLAKEO", author: "Peso Pluma", duration: "3:55"),
                        lockup(id: "vNF-RTZF6bc", title: "Track Two", author: "Artist Two - Topic", duration: "2:40")
                    ]
                ]
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let html = """
        <!DOCTYPE html><html><head><title>YouTube</title></head><body>
        <script nonce="abc">var ytInitialData = \(jsonString);</script>
        </body></html>
        """

        let result = YouTubeService.parsePlaylistFromHTML(
            html: html,
            playlistId: "PL7nl9DQFBc4Ewp94w06FjUdCJdIluoxFP"
        )
        XCTAssertEqual(result.title, "spotify mod free apk")
        XCTAssertEqual(result.tracks.count, 2)
        XCTAssertEqual(result.tracks[0].youtubeVideoId, "fOT0BUpITw8")
        XCTAssertEqual(result.tracks[1].youtubeVideoId, "vNF-RTZF6bc")
    }

    func testLinkParserExtractsPlaylistFromShareTextWithSurroundingWords() {
        let shared = "Посмотрите этот плейлист на YouTube: https://www.youtube.com/playlist?list=PL7nl9DQFBc4Ewp94w06FjUdCJdIluoxFP&si=abc123!"
        let parsed = YouTubeLinkParser.parseInput(shared)
        XCTAssertEqual(parsed.kind, .playlist)
        XCTAssertEqual(parsed.playlistId, "PL7nl9DQFBc4Ewp94w06FjUdCJdIluoxFP")
    }

    func testInspectPlayerResponseRanksMaximumQualityOpusAndHighBitrateAAC() throws {
        let root: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": [
                "adaptiveFormats": [
                    [
                        "itag": 139,
                        "mimeType": "audio/mp4; codecs=\"mp4a.40.5\"",
                        "audioQuality": "AUDIO_QUALITY_LOW",
                        "averageBitrate": 48800,
                        "url": "https://example.com/139.m4a"
                    ],
                    [
                        "itag": 140,
                        "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
                        "audioQuality": "AUDIO_QUALITY_MEDIUM",
                        "averageBitrate": 129500,
                        "url": "https://example.com/140.m4a",
                        "audioTrack": ["audioIsDefault": true]
                    ],
                    [
                        "itag": 251,
                        "mimeType": "audio/webm; codecs=\"opus\"",
                        "audioQuality": "AUDIO_QUALITY_MEDIUM",
                        "averageBitrate": 136000,
                        "url": "https://example.com/251.webm",
                        "audioTrack": ["audioIsDefault": true]
                    ],
                    [
                        "itag": 251,
                        "mimeType": "audio/webm; codecs=\"opus\"",
                        "audioQuality": "AUDIO_QUALITY_MEDIUM",
                        "averageBitrate": 150000,
                        "url": "https://example.com/251_dubbed.webm",
                        "audioTrack": ["audioIsDefault": false]
                    ]
                ]
            ]
        ]

        let candidates = try YouTubeService.inspectPlayerResponseCandidates(root)
        XCTAssertEqual(candidates.count, 4)
        // Оригинальный Opus 48 kHz (itag 251) должен быть №1, оригинальный AAC (itag 140) №2, а автодубляж — в самом конце
        XCTAssertEqual(candidates[0].url.absoluteString, "https://example.com/251.webm")
        XCTAssertTrue(candidates[0].isWebMOpus)
        XCTAssertEqual(candidates[1].url.absoluteString, "https://example.com/140.m4a")
        XCTAssertFalse(candidates[1].isWebMOpus)
        XCTAssertEqual(candidates.last?.url.absoluteString, "https://example.com/251_dubbed.webm")
    }

    func testWebMOpusRemuxerProducesPlayableAppleCoreAudioCAF() throws {
        // Минимальный валидный WebM-буфер: EBML Header + Segment + OpusHead (2ch, preSkip=312) + Cluster + 3x SimpleBlock (20ms stereo CELT silence frame 0xFC 0xFF 0xFE)
        var webm = Data([
            0x1A, 0x45, 0xDF, 0xA3, 0x84, 0x42, 0x86, 0x81, 0x01, // EBML Header (4 bytes body)
            0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // Segment (unknown size)
            0x63, 0xA2, 0x93 // CodecPrivate (19 bytes): OpusHead
        ])
        webm.append(contentsOf: [
            0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64, // "OpusHead"
            0x01, 0x02, 0x38, 0x01, 0x80, 0xBB, 0x00, 0x00, 0x00, 0x00, 0x00
        ])
        // Cluster (unknown size) + 25 SimpleBlocks (0.5 sec @ 48 kHz = 24000 samples)
        webm.append(contentsOf: [0x1F, 0x43, 0xB6, 0x75, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        for i in 0..<25 {
            let tc = UInt16(i * 20)
            webm.append(contentsOf: [
                0xA3, 0x87, // SimpleBlock, size = 7 bytes
                0x81, UInt8(tc >> 8), UInt8(tc & 0xFF), 0x80, // track=1, timecode, keyframe, no lacing
                0xFC, 0xFF, 0xFE // RFC 6716 Opus 20ms stereo DTX/silence packet
            ])
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let webmURL = tmpDir.appendingPathComponent("test_yt_251_\(UUID().uuidString).webm")
        let cafURL = tmpDir.appendingPathComponent("test_yt_251_\(UUID().uuidString).caf")
        defer {
            try? FileManager.default.removeItem(at: webmURL)
            try? FileManager.default.removeItem(at: cafURL)
        }
        try webm.write(to: webmURL)

        try WebMOpusRemuxer.remuxWebMFileToVerifiedCAF(webmURL: webmURL, cafDestinationURL: cafURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cafURL.path))
    }

    func testExtractsReported2500VideoCountWithNonBreakingSpaces() throws {
        let root: [String: Any] = [
            "sidebar": [
                "playlistSidebarRenderer": [
                    "items": [
                        [
                            "playlistSidebarPrimaryInfoRenderer": [
                                "stats": [
                                    ["runs": [["text": "2\u{00A0}500"], ["text": " видео"]]]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let rawData = try JSONSerialization.data(withJSONObject: root)
        let rawJSON = String(data: rawData, encoding: .utf8)!
        XCTAssertEqual(YouTubeService.extractReportedVideoCount(fromRawJSON: rawJSON), 2500)
    }

    @MainActor
    func testAudioInterruptionNeverStartsPlaybackWhenIdleOrPaused() {
        let engine = DualStreamAudioEngine()
        XCTAssertFalse(engine.isPlaying)
        // Симулируем системное прерывание AVAudioSession (звонок / уведомление / Siri), когда плеер стоит на паузе
        engine.handleAudioSessionInterruption(began: true, shouldResume: false)
        XCTAssertFalse(engine.isPlaying)
        // Даже если iOS присылает .ended + .shouldResume, плеер НЕ должен сам включать музыку!
        engine.handleAudioSessionInterruption(began: false, shouldResume: true)
        XCTAssertFalse(engine.isPlaying)
    }

    func testProgressiveMergePrependsNewlyAddedYouTubeTracksAndFixesOrder() {
        let old1 = Track.makeYouTubeTrack(videoId: "COX6kiuRvFc", title: "Ты моя...", artist: "Artist", album: "PL", duration: 180)
        let old2 = Track.makeYouTubeTrack(videoId: "fbrz9lifcPI", title: "Hafanana", artist: "Afric Simone", album: "PL", duration: 200)
        let old3 = Track.makeYouTubeTrack(videoId: "4Jmz-OWycyk", title: "#Сумасшедшая", artist: "Алексей Воробьёв", album: "PL", duration: 195)

        // Пользователь добавил 2 новые песни в плейлист YouTube («Рыбка» и «Good Luck, Babe!»)
        let new1 = Track.makeYouTubeTrack(videoId: "4wYcbNqgwYA", title: "Рыбка", artist: "Artist", album: "PL", duration: 170)
        let new2 = Track.makeYouTubeTrack(videoId: "VZ-oGLluGAc", title: "Good Luck, Babe!", artist: "Chappell Roan", album: "PL", duration: 218)

        let merged = PlaylistPreferencesEngine.mergeProgressivePlaylistPrefix(
            existingTracks: [old2, old1, old3], // даже если раньше порядок был сбит
            prefixSnapshots: [new1, new2, old1, old2]
        )
        XCTAssertEqual(merged.newlyAddedCount, 2)
        XCTAssertEqual(merged.tracks.map(\.youtubeVideoId), [
            "4wYcbNqgwYA",
            "VZ-oGLluGAc",
            "COX6kiuRvFc",
            "fbrz9lifcPI",
            "4Jmz-OWycyk"
        ])
    }

    func testLiveYouTubePlaylistSyncFetchesLatestTracksFromUserPlaylist() async throws {
        let playlistURL = "https://youtube.com/playlist?list=PL7nl9DQFBc4Ewp94w06FjUdCJdIluoxFP"
        // Передаём известные старые ID, чтобы протестировать быстрый инкрементальный синк 1-й страницы в реальном времени
        let knownIds: Set<String> = ["COX6kiuRvFc", "fbrz9lifcPI", "4Jmz-OWycyk", "wT0SRBm0SpU"]
        let result = try await YouTubeService.shared.fetchYouTubeImport(
            input: playlistURL,
            existingKnownVideoIds: knownIds,
            allowFastIncrementalStop: true
        )
        XCTAssertEqual(result.playlistId, "PL7nl9DQFBc4Ewp94w06FjUdCJdIluoxFP")
        XCTAssertGreaterThanOrEqual(result.tracks.count, 50, "Плейлист пользователя должен возвращать актуальные треки с YouTube")
        let videoIds = Set(result.tracks.compactMap(\.youtubeVideoId))
        XCTAssertTrue(videoIds.contains("4wYcbNqgwYA"), "Должна присутствовать новая песня 'Рыбка' (4wYcbNqgwYA)")
        XCTAssertTrue(videoIds.contains("VZ-oGLluGAc"), "Должна присутствовать новая песня 'Good Luck, Babe!' (VZ-oGLluGAc)")
    }
}
