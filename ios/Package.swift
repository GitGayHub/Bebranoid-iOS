// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bebranoid",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BebranoidCore",
            targets: ["BebranoidCore"]
        )
    ],
    targets: [
        .target(
            name: "BebranoidCore",
            path: "Bebranoid",
            exclude: [
                "Info.plist",
                "Bebranoid.entitlements",
                "App/BebranoidApp.swift",
                "MeshBackground/HarmonoidMeshShader.metal",
                "Widgets/BebranoidWidgetBundle.swift",
                "Widgets/NowPlayingWidget.swift",
                "Widgets/PlaybackLiveActivity.swift"
            ]
        ),
        .testTarget(
            name: "BebranoidTests",
            dependencies: ["BebranoidCore"],
            path: "Tests/BebranoidTests"
        )
    ]
)
