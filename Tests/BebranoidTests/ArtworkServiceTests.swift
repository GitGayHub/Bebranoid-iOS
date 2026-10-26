import XCTest
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
@testable import Bebranoid

final class ArtworkServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeTestJPEGData(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Добавим контрастный внутренний квадрат для проверки цветов Harmonoid Mesh
        ctx.setFillColor(red: 1.0 - r * 0.5, green: g * 0.8, blue: min(1.0, b + 0.3), alpha: 1.0)
        ctx.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))

        #if canImport(UIKit)
        if let cgImage = ctx.makeImage() {
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92) ?? Data()
        }
        #endif
        return Data()
    }

    private func uint32BE(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    // MARK: - 1. Binary Embedded Cover Parsers (FLAC, MP3 ID3v2 APIC, M4A covr)

    func testExtractFLACMetadataBlockPicture() throws {
        let jpegData = makeTestJPEGData(width: 128, height: 128, r: 0.85, g: 0.18, b: 0.44)
        XCTAssertFalse(jpegData.isEmpty)

        // Собираем бинарный блок FLAC METADATA_BLOCK_PICTURE (type 6)
        let mimeBytes = Array("image/jpeg".utf8)
        let descBytes = Array("Front Cover".utf8)
        var picturePayload = Data()
        picturePayload.append(contentsOf: uint32BE(3)) // Picture type 3 (Front cover)
        picturePayload.append(contentsOf: uint32BE(UInt32(mimeBytes.count)))
        picturePayload.append(contentsOf: mimeBytes)
        picturePayload.append(contentsOf: uint32BE(UInt32(descBytes.count)))
        picturePayload.append(contentsOf: descBytes)
        picturePayload.append(contentsOf: uint32BE(128)) // width
        picturePayload.append(contentsOf: uint32BE(128)) // height
        picturePayload.append(contentsOf: uint32BE(24))  // depth
        picturePayload.append(contentsOf: uint32BE(0))   // colors
        picturePayload.append(contentsOf: uint32BE(UInt32(jpegData.count)))
        picturePayload.append(jpegData)

        var flacData = Data()
        flacData.append(contentsOf: "fLaC".utf8)
        // Заголовок блока: isLast=1 (0x80) | type=6 -> 0x86, затем 24-битная длина
        let len = UInt32(picturePayload.count)
        flacData.append(0x86)
        flacData.append(UInt8((len >> 16) & 0xFF))
        flacData.append(UInt8((len >> 8) & 0xFF))
        flacData.append(UInt8(len & 0xFF))
        flacData.append(picturePayload)

        let extracted = AudioMetadataReader.extractFLACPicture(from: flacData)
        XCTAssertNotNil(extracted, "FLAC METADATA_BLOCK_PICTURE должен успешно извлекать JPEG")
        XCTAssertEqual(extracted, jpegData)
    }

    func testExtractMP3ID3v2APIC() throws {
        let jpegData = makeTestJPEGData(width: 96, height: 96, r: 0.14, g: 0.66, b: 0.92)
        XCTAssertFalse(jpegData.isEmpty)

        // Собираем кадр APIC для ID3v2.3
        var apicPayload = Data()
        apicPayload.append(0x00) // ISO-8859-1 encoding
        apicPayload.append(contentsOf: "image/jpeg".utf8)
        apicPayload.append(0x00) // Null-terminated MIME
        apicPayload.append(0x03) // Picture type: Front Cover
        apicPayload.append(0x00) // Empty description + null
        apicPayload.append(jpegData)

        var id3Data = Data()
        id3Data.append(contentsOf: "ID3".utf8)
        id3Data.append(0x03) // version 2.3
        id3Data.append(0x00) // revision
        id3Data.append(0x00) // flags

        let totalTagSize = UInt32(10 + apicPayload.count)
        // Synchsafe 28-bit integer
        id3Data.append(UInt8((totalTagSize >> 21) & 0x7F))
        id3Data.append(UInt8((totalTagSize >> 14) & 0x7F))
        id3Data.append(UInt8((totalTagSize >> 7) & 0x7F))
        id3Data.append(UInt8(totalTagSize & 0x7F))

        // APIC frame header
        id3Data.append(contentsOf: "APIC".utf8)
        id3Data.append(contentsOf: uint32BE(UInt32(apicPayload.count)))
        id3Data.append(contentsOf: [0x00, 0x00]) // flags
        id3Data.append(apicPayload)

        let extracted = AudioMetadataReader.extractID3v2APIC(from: id3Data)
        XCTAssertNotNil(extracted, "ID3v2 APIC должен успешно извлекать встроенный JPEG")
        XCTAssertEqual(extracted, jpegData)
    }

    func testExtractM4ACovrAtom() throws {
        let jpegData = makeTestJPEGData(width: 96, height: 96, r: 0.92, g: 0.52, b: 0.16)
        XCTAssertFalse(jpegData.isEmpty)

        // Собираем атом `data` внутри `covr`
        var dataAtom = Data()
        let dataAtomSize = UInt32(16 + jpegData.count)
        dataAtom.append(contentsOf: uint32BE(dataAtomSize))
        dataAtom.append(contentsOf: "data".utf8)
        dataAtom.append(contentsOf: uint32BE(0x0000000D)) // flags: JPEG (13)
        dataAtom.append(contentsOf: uint32BE(0))          // reserved
        dataAtom.append(jpegData)

        var covrAtom = Data()
        let covrAtomSize = UInt32(8 + dataAtom.count)
        covrAtom.append(contentsOf: uint32BE(covrAtomSize))
        covrAtom.append(contentsOf: "covr".utf8)
        covrAtom.append(dataAtom)

        let extracted = AudioMetadataReader.extractMP4CovrAtom(from: covrAtom)
        XCTAssertNotNil(extracted, "M4A/MP4 covr->data должен успешно извлекать JPEG")
        XCTAssertEqual(extracted, jpegData)
    }

    // MARK: - 2. YouTube 16:9 & 4:3 Letterbox -> 1:1 Center-Square Crop

    @MainActor
    func testYouTube16x9And4x3LetterboxCenterSquareCrop() throws {
        // 1) 16:9 (1280x720) -> 720x720
        let jpeg16x9 = makeTestJPEGData(width: 1280, height: 720, r: 0.80, g: 0.25, b: 0.35)
        let cropped16x9 = ArtworkService.shared.cropYouTubeThumbnailToSquare(imageData: jpeg16x9)
        XCTAssertNotNil(cropped16x9)
        #if canImport(UIKit)
        if let croppedData = cropped16x9, let img = UIImage(data: croppedData)?.cgImage {
            XCTAssertEqual(img.width, 720)
            XCTAssertEqual(img.height, 720)
        }
        #endif

        // 2) 4:3 letterbox (480x360) -> side = min(360, floor(480 * 9 / 16)) = 270x270
        let jpeg4x3 = makeTestJPEGData(width: 480, height: 360, r: 0.20, g: 0.72, b: 0.55)
        let cropped4x3 = ArtworkService.shared.cropYouTubeThumbnailToSquare(imageData: jpeg4x3)
        XCTAssertNotNil(cropped4x3)
        #if canImport(UIKit)
        if let croppedData = cropped4x3, let img = UIImage(data: croppedData)?.cgImage {
            XCTAssertEqual(img.width, 270)
            XCTAssertEqual(img.height, 270)
        }
        #endif
    }

    // MARK: - 3. 7-Level Priority Resolution & Harmonoid Mesh Color Extraction

    @MainActor
    func testArtworkPriorityChainAndMeshExtraction() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("artwork_priority_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let customCoverURL = tempDir.appendingPathComponent("custom_album.jpg")
        let trackCoverURL = tempDir.appendingPathComponent("track_cover.jpg")
        try makeTestJPEGData(width: 300, height: 300, r: 0.95, g: 0.20, b: 0.30).write(to: customCoverURL)
        try makeTestJPEGData(width: 300, height: 300, r: 0.15, g: 0.85, b: 0.45).write(to: trackCoverURL)

        let track = Track(
            id: "test:priority:1",
            title: "Priority Test Track",
            artist: "Test Artist",
            album: "Priority Album",
            duration: 180,
            filename: "priority_test.flac",
            coverPath: trackCoverURL.path
        )

        // При наличии customAlbumCovers выбирается уровень 1 (customAlbumCover)
        let resolvedCustom = await ArtworkService.shared.resolveArtwork(
            for: track,
            customAlbumCovers: ["Priority Album": customCoverURL.path]
        )
        XCTAssertEqual(resolvedCustom.source, .customAlbumCover)
        XCTAssertEqual(resolvedCustom.localFileURL?.path, customCoverURL.path)

        // Без customAlbumCovers выбирается уровень 2 (localDiskCover)
        let resolvedDisk = await ArtworkService.shared.resolveArtwork(
            for: track,
            customAlbumCovers: [:]
        )
        XCTAssertEqual(resolvedDisk.source, .localDiskCover)
        XCTAssertEqual(resolvedDisk.localFileURL?.path, trackCoverURL.path)

        // Проверяем извлечение палитры HarmonoidMeshEngine из реальной обложки
        if let url = resolvedDisk.localFileURL,
           let cgImg = ArtworkService.shared.loadCGImage(from: url, tier: .meshAnalysis) {
            let analyzed = HarmonoidMeshEngine.analyzeCoverImage(cgImg)
            XCTAssertEqual(analyzed.meshColors.count, 4)
        } else {
            XCTFail("Не удалось загрузить CGImage для анализа палитры Harmonoid Mesh")
        }
    }

    // MARK: - 4. Telegram TDLib Single-Source-of-Truth Auth Guard & Cover File ID Parsing

    func testTelegramAuthorizationRequiresTDLibReadyStateNotKeychainMarker() {
        // Сохраняем маркер в Keychain и проверяем, что без TDLib authorizationStateReady
        // TelegramClientService.shared.isAuthorized остаётся FALSE (исправление бага)
        KeychainHelper.shared.saveString("legacy_saved_marker", for: .telegramSessionData)
        defer { KeychainHelper.shared.delete(.telegramSessionData) }

        if TelegramClientService.shared.rawTDLibAuthState != "authorizationStateReady" {
            XCTAssertFalse(
                TelegramClientService.shared.isAuthorized,
                "TelegramClientService.isAuthorized обязан зависеть только от TDLib authorizationStateReady, а не от маркера в Keychain"
            )
        }
    }

    func testParseTDLibMessageExtractsCoverFileId() throws {
        let msgJSON: [String: Any] = [
            "id": Int64(777_001),
            "date": 1_715_000_000,
            "content": [
                "@type": "messageAudio",
                "audio": [
                    "duration": 210,
                    "title": "Cloud Cover Song",
                    "performer": "TDLib Artist",
                    "file_name": "cloud_cover.flac",
                    "mime_type": "audio/flac",
                    "album_cover_thumbnail": [
                        "width": 320,
                        "height": 320,
                        "file": [
                            "size": 18432,
                            "remote": [
                                "id": "REMOTE_THUMB_COVER_ID_999"
                            ]
                        ]
                    ],
                    "audio": [
                        "size": 25_000_000,
                        "remote": [
                            "id": "REMOTE_AUDIO_FILE_ID_999"
                        ]
                    ]
                ]
            ]
        ]

        let raw = TelegramClientService.parseTDLibMessage(
            msgJSON,
            chatId: "-100123456",
            chatTitle: "Music Cloud",
            forumTopics: [:]
        )
        XCTAssertNotNil(raw)
        XCTAssertEqual(raw?.fileId, "REMOTE_AUDIO_FILE_ID_999")
        XCTAssertEqual(raw?.coverFileId, "REMOTE_THUMB_COVER_ID_999")

        if let raw {
            let track = TelegramScanner.buildTrack(from: raw)
            XCTAssertEqual(track?.coverFileId, "REMOTE_THUMB_COVER_ID_999")
        }
    }
}
