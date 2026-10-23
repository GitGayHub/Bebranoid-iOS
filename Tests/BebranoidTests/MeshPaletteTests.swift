import XCTest
#if canImport(BebranoidCore)
@testable import BebranoidCore
#else
@testable import Bebranoid
#endif

final class MeshPaletteTests: XCTestCase {
    func testRGBToHSVDegreesAndBackIdentity() {
        let samples = [
            MeshRGB(20, 30, 50),
            MeshRGB(96, 165, 250),
            MeshRGB(218, 44, 136),
            MeshRGB(242, 168, 36)
        ]

        for sample in samples {
            let hsv = HarmonoidMeshEngine.rgbToHsv(sample.r, sample.g, sample.b)
            XCTAssertGreaterThanOrEqual(hsv.h, 0.0)
            XCTAssertLessThan(hsv.h, 360.0)
            let roundtrip = HarmonoidMeshEngine.hsvToRgb(hsv.h, hsv.s, hsv.v)
            XCTAssertLessThanOrEqual(abs(sample.r - roundtrip.r), 1)
            XCTAssertLessThanOrEqual(abs(sample.g - roundtrip.g), 1)
            XCTAssertLessThanOrEqual(abs(sample.b - roundtrip.b), 1)
        }
    }

    func testSevenReferenceCoverFixturesAndExactJSReferenceParity() {
        // Exact JS reference outputs from `HarmonoidMeshBackground.jsx` for all 7 64×64 RGBA fixtures
        let expectedJSReference: [HarmonoidMeshFixtureKind: (bucketCount: Int, mesh0: MeshRGB, accent: MeshRGB, fillBase: MeshRGB)] = [
            .solid: (1, MeshRGB(11, 25, 56), MeshRGB(51, 104, 230), MeshRGB(4, 8, 22)),
            .blackAndWhite: (1, MeshRGB(74, 63, 63), MeshRGB(163, 101, 101), MeshRGB(25, 22, 25)),
            .darkWithRedAccent: (2, MeshRGB(22, 25, 36), MeshRGB(230, 51, 76), MeshRGB(7, 8, 14)),
            .vividMulticolor: (4, MeshRGB(8, 52, 56), MeshRGB(199, 147, 56), MeshRGB(4, 18, 22)),
            .pastel: (2, MeshRGB(30, 54, 66), MeshRGB(82, 146, 179), MeshRGB(10, 18, 26)),
            .transparent: (0, MeshRGB(20, 30, 50), MeshRGB(96, 165, 250), MeshRGB(7, 10, 20)),
            .neutralDominant: (2, MeshRGB(56, 60, 66), MeshRGB(46, 184, 138), MeshRGB(19, 21, 26))
        ]

        for kind in HarmonoidMeshFixtureKind.allCases {
            let rgba = HarmonoidMeshFixtures.makeRGBA64x64(for: kind)
            XCTAssertEqual(rgba.count, 64 * 64 * 4)

            let rawPalette = HarmonoidMeshEngine.extractCoverPalette(fromRGBA: rgba)
            let meshColors = HarmonoidMeshEngine.mapPaletteToMeshColors(rawPalette)
            let accent = HarmonoidMeshEngine.pickAccentFromPalette(rawPalette)
            let fillBase = HarmonoidMeshEngine.computeBaseFillColor(from: meshColors)

            XCTAssertEqual(meshColors.count, 4, "Fixture \(kind.rawValue) must produce 4 mesh colors")
            for i in 0..<4 {
                let hsv = HarmonoidMeshEngine.rgbToHsv(meshColors[i].r, meshColors[i].g, meshColors[i].b)
                XCTAssertGreaterThanOrEqual(hsv.v, 0.08, "Fixture \(kind.rawValue) slot \(i) v too low")
                XCTAssertLessThanOrEqual(hsv.v, 0.44, "Fixture \(kind.rawValue) slot \(i) v too high")
            }

            let accentLum = HarmonoidMeshEngine.luminance(accent)
            XCTAssertGreaterThanOrEqual(accentLum, 0.41, "Fixture \(kind.rawValue) accent luminance must be readable")

            if let ref = expectedJSReference[kind] {
                XCTAssertEqual(rawPalette.count, ref.bucketCount, "Bucket count mismatch for \(kind.rawValue)")
                XCTAssertLessThanOrEqual(abs(meshColors[0].r - ref.mesh0.r), 1, "meshColors[0].r mismatch for \(kind.rawValue)")
                XCTAssertLessThanOrEqual(abs(meshColors[0].g - ref.mesh0.g), 1, "meshColors[0].g mismatch for \(kind.rawValue)")
                XCTAssertLessThanOrEqual(abs(meshColors[0].b - ref.mesh0.b), 1, "meshColors[0].b mismatch for \(kind.rawValue)")
                XCTAssertLessThanOrEqual(abs(accent.r - ref.accent.r), 1, "uiAccent.r mismatch for \(kind.rawValue)")
                XCTAssertLessThanOrEqual(abs(accent.g - ref.accent.g), 1, "uiAccent.g mismatch for \(kind.rawValue)")
                XCTAssertLessThanOrEqual(abs(accent.b - ref.accent.b), 1, "uiAccent.b mismatch for \(kind.rawValue)")
                XCTAssertEqual(fillBase, ref.fillBase, "fillBase mismatch for \(kind.rawValue)")
            }
        }
    }

    func testEnsureReadableAccentBoostsDarkColorsTo042Luminance() {
        let veryDark = MeshRGB(18, 12, 34)
        let readable = HarmonoidMeshEngine.ensureReadableAccent(veryDark)
        let lum = HarmonoidMeshEngine.luminance(readable)
        XCTAssertGreaterThanOrEqual(lum, 0.41)
    }

    func testSmoothstepAndLerpPaletteAndFourFixedTimeFrames() {
        XCTAssertEqual(HarmonoidMeshEngine.smoothstep(0.0, 1.0, 0.0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(HarmonoidMeshEngine.smoothstep(0.0, 1.0, 0.25), 0.15625, accuracy: 1e-9)
        XCTAssertEqual(HarmonoidMeshEngine.smoothstep(0.0, 1.0, 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HarmonoidMeshEngine.smoothstep(0.0, 1.0, 0.75), 0.84375, accuracy: 1e-9)
        XCTAssertEqual(HarmonoidMeshEngine.smoothstep(0.0, 1.0, 1.0), 1.0, accuracy: 1e-9)

        let palette = HarmonoidMeshEngine.defaultPalette
        let base = HarmonoidMeshEngine.computeBaseFillColor(from: palette)
        XCTAssertEqual(base.r, max(4, Int(floor(Double(palette[0].r) * 0.35))))
        XCTAssertEqual(base.g, max(4, Int(floor(Double(palette[0].g) * 0.35))))
        XCTAssertEqual(base.b, max(6, Int(floor(Double(palette[0].b) * 0.40))))

        for t in [0.0, 3.5, 7.0, 10.0] {
            let blobs = HarmonoidMeshEngine.blobCenters(
                at: t,
                width: 430.0,
                height: 932.0,
                meshColors: palette
            )
            XCTAssertEqual(blobs.count, 4)
            let expectedR0 = 932.0 * (0.55 + 0.08 * sin(t * 0.35 + 0.0))
            XCTAssertEqual(blobs[0].radius, expectedR0, accuracy: 1e-6)
            XCTAssertTrue(blobs[0].isSourceOver)
            XCTAssertFalse(blobs[1].isSourceOver)
            XCTAssertFalse(blobs[2].isSourceOver)
            XCTAssertFalse(blobs[3].isSourceOver)
        }
    }
}
