import XCTest
#if canImport(BebranoidCore)
@testable import BebranoidCore
#else
@testable import Bebranoid
#endif

final class VolumeCurveTests: XCTestCase {
    func testVolumeCurveExponent275AndRoundtrip() {
        XCTAssertEqual(VolumeCurve.uiToGain(0.0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(VolumeCurve.uiToGain(1.0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(VolumeCurve.uiToGain(0.5), pow(0.5, 2.75), accuracy: 1e-12)
        XCTAssertEqual(VolumeCurve.uiToGain(0.8), pow(0.8, 2.75), accuracy: 1e-12)

        for sample in [0.1, 0.25, 0.5, 0.75, 0.9] {
            let gain = VolumeCurve.uiToGain(sample)
            let recovered = VolumeCurve.gainToUi(gain)
            XCTAssertEqual(recovered, sample, accuracy: 1e-9)
        }
    }

    func testQualityBadgeClassification() {
        let hiRes = AudioFormatInfo(codec: "FLAC", sampleRateHz: 96000, bitsPerSample: 24, lossless: true)
        XCTAssertEqual(hiRes.computeQualityBadge().tier, .hiRes)
        XCTAssertEqual(hiRes.computeQualityBadge().label, "FLAC Hi-Res")
        XCTAssertEqual(hiRes.computeQualityBadge().hexColor, "#ffc85a")

        let cdLossless = AudioFormatInfo(codec: "FLAC", sampleRateHz: 44100, bitsPerSample: 16, lossless: true)
        XCTAssertEqual(cdLossless.computeQualityBadge().tier, .lossless)
        XCTAssertEqual(cdLossless.computeQualityBadge().label, "FLAC Lossless")
        XCTAssertEqual(cdLossless.computeQualityBadge().hexColor, "#d08bff")

        let hqAac = AudioFormatInfo(codec: "AAC", bitrateKbps: 256, sampleRateHz: 44100, lossless: false)
        XCTAssertEqual(hqAac.computeQualityBadge().tier, .hq)
        XCTAssertEqual(hqAac.computeQualityBadge().hexColor, "#60a5fa")
    }
}
