import XCTest
#if canImport(BebranoidCore)
@testable import BebranoidCore
#else
@testable import Bebranoid
#endif

final class TelegramParserTests: XCTestCase {
    private let testMainChatId = "-1001111111111"
    private let testMainChatTitle = "Cloud Music Main"
    private let testArchiveChatId = "-1001111111112"
    private let testArchiveChatTitle = "Cloud Music Archive"

    func testParseCaptionAndResolveAlbum() {
        let caption = """
        path=/storage/emulated/0/Music/Kino - Zvezda/01 - Песня без слов.flac
        title=Песня без слов
        artist=Кино
        album=Звезда по имени Солнце
        durationMs=306000
        year=1989
        """

        let meta = TelegramScanner.parseMetaFromCaption(caption)
        XCTAssertEqual(meta.title, "Песня без слов")
        XCTAssertEqual(meta.artist, "Кино")
        XCTAssertEqual(meta.album, "Звезда по имени Солнце")
        XCTAssertEqual(meta.durationMs, 306000)
        XCTAssertEqual(meta.year, 1989)

        let resolved = TelegramScanner.resolveAlbumName(
            captionMeta: meta,
            topicTitle: "Какой-то топик",
            trackTitle: meta.title!,
            artist: meta.artist!,
            filename: "01 - Песня без слов.flac",
            chatTitle: testMainChatTitle,
            ignoredChatTitles: [testMainChatTitle, testArchiveChatTitle]
        )
        XCTAssertEqual(resolved, "Звезда по имени Солнце")
    }

    func testSingleTrackTopicDoesNotBecomeOneTrackAlbum() {
        let emptyCap = AndroSendCaptionMetadata(path: "/storage/0/Music/Post-Punk Collection/Molchat Doma - Sudno.flac")
        let isSingle = TelegramScanner.isSingleTrackTopic(
            topicTitle: "Molchat Doma - Sudno",
            trackTitle: "Sudno",
            artist: "Molchat Doma",
            filename: "Molchat Doma - Sudno.flac"
        )
        XCTAssertTrue(isSingle)

        // Так как топик совпал с именем одного трека, альбом должен разрешиться из родительской папки пути `Post-Punk Collection`
        let album = TelegramScanner.resolveAlbumName(
            captionMeta: emptyCap,
            topicTitle: "Molchat Doma - Sudno",
            trackTitle: "Sudno",
            artist: "Molchat Doma",
            filename: "Molchat Doma - Sudno.flac",
            chatTitle: testMainChatTitle,
            ignoredChatTitles: [testMainChatTitle, testArchiveChatTitle]
        )
        XCTAssertEqual(album, "Post-Punk Collection")
    }

    func testThreeWayArchiveDeduplicationAndReadOnlyGuard() {
        let main1 = Track.makeTelegramTrack(
            chatId: testMainChatId,
            messageId: 101,
            fileUniqueId: "uid_1",
            title: "Группа крови",
            artist: "Кино",
            album: "Группа крови",
            duration: 280,
            filename: "kino_gruppa.flac",
            configuredArchiveChatId: testArchiveChatId
        )

        // Архивный дубликат по fileUniqueId
        let archDupUid = Track.makeTelegramTrack(
            chatId: testArchiveChatId,
            messageId: 501,
            fileUniqueId: "uid_1",
            title: "Other Title",
            artist: "Other",
            album: "Arch",
            duration: 280,
            filename: "other.flac",
            configuredArchiveChatId: testArchiveChatId
        )

        // Архивный дубликат по нормализованному artist + title
        let archDupArtistTitle = Track.makeTelegramTrack(
            chatId: testArchiveChatId,
            messageId: 502,
            fileUniqueId: "uid_502",
            title: "группа крови",
            artist: "КИНО",
            album: "Arch",
            duration: 280,
            filename: "different_file.mp3",
            configuredArchiveChatId: testArchiveChatId
        )

        // Уникальный трек из архива
        let archUnique = Track.makeTelegramTrack(
            chatId: testArchiveChatId,
            messageId: 503,
            fileUniqueId: "uid_503",
            title: "Спокойная ночь",
            artist: "Кино",
            album: "Группа крови",
            duration: 360,
            filename: "spokoynaya_noch.flac",
            configuredArchiveChatId: testArchiveChatId
        )

        let merged = TelegramScanner.mergeMainAndArchiveTracks(
            mainTracks: [main1],
            archiveTracks: [archDupUid, archDupArtistTitle, archUnique]
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].id, "\(testMainChatId):101")
        XCTAssertFalse(merged[0].isCloudDeletionBlocked)
        XCTAssertEqual(merged[1].id, "\(testArchiveChatId):503")
        XCTAssertTrue(merged[1].isCloudDeletionBlocked)
    }

    func testTDLibNativeMessageParsingAndBridgeExecution() {
        let sampleAudioMsg: [String: Any] = [
            "@type": "message",
            "id": Int64(777),
            "message_thread_id": 42,
            "date": Int64(1_710_000_000),
            "content": [
                "@type": "messageAudio",
                "caption": ["@type": "formattedText", "text": "album=Lossless Masters\nyear=2025"],
                "audio": [
                    "duration": 245,
                    "title": "Midnight Synthesis",
                    "performer": "Bebra Modular",
                    "file_name": "01_Midnight_Synthesis.flac",
                    "mime_type": "audio/flac",
                    "audio": [
                        "id": 91,
                        "size": Int64(34_500_000),
                        "remote": ["unique_id": "tdlib_unique_91"]
                    ]
                ]
            ]
        ]

        let parsed = TelegramClientService.parseTDLibMessage(
            sampleAudioMsg,
            chatId: testMainChatId,
            chatTitle: testMainChatTitle,
            forumTopics: [42: "Synthwave Topic"]
        )
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.messageId, 777)
        XCTAssertEqual(parsed?.topicTitle, "Synthwave Topic")
        XCTAssertEqual(parsed?.filename, "01_Midnight_Synthesis.flac")
        XCTAssertEqual(parsed?.fileUniqueId, "tdlib_unique_91")

        if TDLibJSONBridge.isNativeTDLibAvailable {
            let entities = TDLibJSONBridge.executeSync([
                "@type": "getTextEntities",
                "text": "Bebranoid #lossless @telegram"
            ])
            XCTAssertNotNil(entities)
            XCTAssertEqual(entities?["@type"] as? String, "textEntities")
        }
    }

    func testPriorityDownloadQueuePreemption() async throws {
        let queue = PriorityDownloadQueue(concurrency: 1)
        let dummyURL = URL(fileURLWithPath: "/tmp/test.flac")

        // Запускаем фоновую задачу с приоритетом 0, которая проверяет токен вытеснения
        let bgTask = Task {
            try await queue.enqueue(key: "bg_track", priority: 0) { token in
                try await Task.sleep(nanoseconds: 120_000_000)
                try token.throwIfPreempted(key: "bg_track")
                return dummyURL
            }
        }

        try await Task.sleep(nanoseconds: 25_000_000)

        // Ставим задачу активного трека с приоритетом 3 — она должна вытеснить bg_track и завершиться первой
        let activeResult = try await queue.enqueue(key: "active_track", priority: 3) { _ in
            return dummyURL
        }
        XCTAssertEqual(activeResult, dummyURL)
        bgTask.cancel()
    }

    func testDefaultTelegramCredentialsFallback() {
        XCTAssertFalse(TelegramClientService.defaultApiId.isEmpty)
        XCTAssertFalse(TelegramClientService.defaultApiHash.isEmpty)
        XCTAssertGreaterThan(Int(TelegramClientService.defaultApiId) ?? 0, 0)
        XCTAssertEqual(TelegramClientService.defaultApiHash.count, 32)
        XCTAssertTrue(TelegramClientService.shared.hasConfiguredApiCredentials)
    }

    func testTDLib1868TopicIdExtraction() {
        let msgWithNestedTopicId: [String: Any] = [
            "@type": "message",
            "id": Int64(888),
            "topic_id": [
                "@type": "messageTopicForum",
                "forum_topic_id": 12215
            ],
            "date": Int64(1_715_000_000),
            "content": [
                "@type": "messageAudio",
                "audio": [
                    "duration": 180,
                    "title": "Topic Song",
                    "performer": "Topic Artist",
                    "file_name": "Topic_Song.m4a",
                    "mime_type": "audio/mp4",
                    "audio": [
                        "id": 99,
                        "size": Int64(5_000_000),
                        "remote": ["unique_id": "uid_99"]
                    ]
                ]
            ]
        ]

        let parsed = TelegramClientService.parseTDLibMessage(
            msgWithNestedTopicId,
            chatId: AppConfig.defaultSeedMainChatId,
            chatTitle: AppConfig.defaultSeedMainChatTitle,
            forumTopics: [12215: "yeat"]
        )
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.messageThreadId, 12215)
        XCTAssertEqual(parsed?.topicTitle, "yeat")
    }
}
