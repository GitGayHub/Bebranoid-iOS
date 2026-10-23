import Foundation

struct PrimitiveSampleOut: Codable {
    let input: [Int]
    let lum: Double
    let chr: Double
    let hsv: [Double]
    let roundtripRGB: [Int]
    let tint028: [Int]
    let readableAccent: [Int]
}

struct ColorOut: Codable {
    let r: Int
    let g: Int
    let b: Int
    let score: Double?
}

struct BlobOut: Codable {
    let index: Int
    let x: Double
    let y: Double
    let radius: Double
    let composite: String
    let color: ColorOut
}

struct FixtureDumpOut: Codable {
    let id: String
    let rawPalette: [ColorOut]
    let meshColors: [ColorOut]
    let uiAccent: ColorOut
    let fillBase: ColorOut
    let blobsAtT0: [BlobOut]
    let blobsAtT3_5: [BlobOut]
    let blobsAtT7_0: [BlobOut]
    let blobsAtT10_0: [BlobOut]
}

struct LerpSampleOut: Codable {
    let progress: Double
    let smoothstep: Double
    let colors: [ColorOut]
}

struct FullSwiftMeshDump: Codable {
    let engineVersion: String
    let primitives: [PrimitiveSampleOut]
    let fixtures: [FixtureDumpOut]
    let lerpSamples: [LerpSampleOut]
}

func toColorOut(_ c: MeshRGB, includeScore: Bool = false) -> ColorOut {
    ColorOut(r: c.r, g: c.g, b: c.b, score: includeScore ? c.score : nil)
}

func toBlobsOut(timeSec: Double, meshColors: [MeshRGB]) -> [BlobOut] {
    HarmonoidMeshEngine.blobCenters(at: timeSec, width: 430.0, height: 932.0, meshColors: meshColors).map { b in
        BlobOut(
            index: b.index,
            x: (b.x * 10000.0).rounded() / 10000.0,
            y: (b.y * 10000.0).rounded() / 10000.0,
            radius: (b.radius * 10000.0).rounded() / 10000.0,
            composite: b.isSourceOver ? "source-over" : "lighter",
            color: toColorOut(b.color)
        )
    }
}

func runDumpMesh() throws {
    let sampleInputs: [[Int]] = [
        [20, 30, 50],
        [96, 165, 250],
        [218, 44, 136],
        [242, 168, 36],
        [18, 12, 34],
        [214, 176, 224]
    ]

    let primitivesOut: [PrimitiveSampleOut] = sampleInputs.map { rgb in
        let r = rgb[0], g = rgb[1], b = rgb[2]
        let lum = HarmonoidMeshEngine.luminance(r, g, b)
        let chr = HarmonoidMeshEngine.chroma(r, g, b)
        let hsv = HarmonoidMeshEngine.rgbToHsv(r, g, b)
        let rt = HarmonoidMeshEngine.hsvToRgb(hsv.h, hsv.s, hsv.v)
        let tint = HarmonoidMeshEngine.toMeshTint(MeshRGB(r, g, b), depth: 0.28)
        let acc = HarmonoidMeshEngine.ensureReadableAccent(MeshRGB(r, g, b))
        return PrimitiveSampleOut(
            input: rgb,
            lum: lum,
            chr: chr,
            hsv: [hsv.h, hsv.s, hsv.v],
            roundtripRGB: [rt.r, rt.g, rt.b],
            tint028: [tint.r, tint.g, tint.b],
            readableAccent: [acc.r, acc.g, acc.b]
        )
    }

    var fixturesOut: [FixtureDumpOut] = []
    var vividMesh: [MeshRGB] = HarmonoidMeshEngine.defaultPalette
    var pastelMesh: [MeshRGB] = HarmonoidMeshEngine.defaultPalette

    for kind in HarmonoidMeshFixtureKind.allCases {
        let rgba = HarmonoidMeshFixtures.makeRGBA64x64(for: kind)
        let rawPalette = HarmonoidMeshEngine.extractCoverPalette(fromRGBA: rgba)
        let meshColors = HarmonoidMeshEngine.mapPaletteToMeshColors(rawPalette)
        let uiAccent = HarmonoidMeshEngine.pickAccentFromPalette(rawPalette)
        let fillBase = HarmonoidMeshEngine.computeBaseFillColor(from: meshColors)

        if kind == .vividMulticolor { vividMesh = meshColors }
        if kind == .pastel { pastelMesh = meshColors }

        fixturesOut.append(
            FixtureDumpOut(
                id: kind.rawValue,
                rawPalette: rawPalette.map { toColorOut($0, includeScore: true) },
                meshColors: meshColors.map { toColorOut($0) },
                uiAccent: toColorOut(uiAccent),
                fillBase: toColorOut(fillBase),
                blobsAtT0: toBlobsOut(timeSec: 0.0, meshColors: meshColors),
                blobsAtT3_5: toBlobsOut(timeSec: 3.5, meshColors: meshColors),
                blobsAtT7_0: toBlobsOut(timeSec: 7.0, meshColors: meshColors),
                blobsAtT10_0: toBlobsOut(timeSec: 10.0, meshColors: meshColors)
            )
        )
    }

    let progressPoints: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
    let lerpOut: [LerpSampleOut] = progressPoints.map { p in
        let ss = HarmonoidMeshEngine.smoothstep(0.0, 1.0, p)
        let lerped = HarmonoidMeshEngine.lerpPalette(vividMesh, pastelMesh, progress: p)
        return LerpSampleOut(
            progress: p,
            smoothstep: ss,
            colors: lerped.map { toColorOut($0) }
        )
    }

    let fullDump = FullSwiftMeshDump(
        engineVersion: "HarmonoidMeshEngine-Swift-1.0",
        primitives: primitivesOut,
        fixtures: fixturesOut,
        lerpSamples: lerpOut
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(fullDump)
    if let jsonStr = String(data: jsonData, encoding: .utf8) {
        print(jsonStr)
    }
}

try runDumpMesh()
