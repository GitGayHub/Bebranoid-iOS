import XCTest
#if canImport(BebranoidCore)
@testable import BebranoidCore
#else
@testable import Bebranoid
#endif

final class PlaylistPreferencesTests: XCTestCase {
    private func makeYTTrack(_ idx: Int) -> Track {
        let vid = String(format: "vid_%07d", idx)
        return Track.makeYouTubeTrack(videoId: vid, title: "Song \(idx)", artist: "Artist")
    }

    func testDefaultLimitAndEligibleTracksWithOverrides() {
        let tracks = (0..<30).map { makeYTTrack($0) }
        var pref = PlaylistShufflePreference()
        XCTAssertEqual(pref.limit, 15)

        // Исключаем 2-й трек (внутри лимита 15) и принудительно включаем 25-й трек (за пределами лимита 15)
        pref.toggleExclude(filename: tracks[2].cacheKey)
        pref.toggleInclude(filename: tracks[25].cacheKey)

        let eligible = PlaylistPreferencesEngine.eligiblePlaylistTracks(tracks: tracks, preference: pref)
        // 15 базовых - 1 исключённый + 1 принудительно включённый = 15 треков
        XCTAssertEqual(eligible.count, 15)
        XCTAssertFalse(eligible.contains(where: { $0.cacheKey == tracks[2].cacheKey }))
        XCTAssertTrue(eligible.contains(where: { $0.cacheKey == tracks[25].cacheKey }))

        pref.adjustLimit(by: -10)
        XCTAssertEqual(pref.limit, 5)
        pref.adjustLimit(by: -10)
        XCTAssertEqual(pref.limit, 0)
    }

    func testReconcilePlaylistPreservesManualLocalTracks() {
        let yt1 = makeYTTrack(1)
        let yt2 = makeYTTrack(2)
        let manualLocal = Track(
            id: "local_bonus.flac",
            title: "Bonus Local",
            artist: "Local Artist",
            album: "Local",
            filename: "bonus.flac",
            sourceKind: .local
        )

        let existing = [yt1, manualLocal, yt2]
        let newRemoteSnapshot = [yt2, makeYTTrack(3)]

        let reconciled = PlaylistPreferencesEngine.reconcilePlaylist(
            existingTracks: existing,
            remoteSnapshots: newRemoteSnapshot
        )

        XCTAssertEqual(reconciled.count, 3)
        XCTAssertEqual(reconciled[0].cacheKey, yt2.cacheKey)
        XCTAssertEqual(reconciled[1].cacheKey, makeYTTrack(3).cacheKey)
        XCTAssertEqual(reconciled[2].id, "local_bonus.flac")
    }

    func testMergeProgressivePlaylistPrefixPrependsNewestAndNeverTruncates2500Tracks() {
        let existing2500 = (1...2500).map { makeYTTrack($0) }
        let page1Prefix = [makeYTTrack(9991), makeYTTrack(9992)] + Array(existing2500.prefix(98))

        let merged = PlaylistPreferencesEngine.mergeProgressivePlaylistPrefix(
            existingTracks: existing2500,
            prefixSnapshots: page1Prefix
        )

        XCTAssertEqual(merged.newlyAddedCount, 2)
        XCTAssertEqual(merged.tracks.count, 2502)
        XCTAssertEqual(merged.tracks[0].cacheKey, makeYTTrack(9991).cacheKey)
        XCTAssertEqual(merged.tracks[1].cacheKey, makeYTTrack(9992).cacheKey)
        XCTAssertEqual(merged.tracks.last?.cacheKey, makeYTTrack(2500).cacheKey)
    }
}
