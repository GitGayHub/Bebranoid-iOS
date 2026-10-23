import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Универсальный компонент отображения обложки трека/альбома/плейлиста.
/// Поддерживает локальные файлы на диске, удалённые URL (например обложки YouTube) и стилизованный градиентный фолбэк.
public struct ArtworkThumbnailView: View {
    public let localPath: String?
    public let remoteURL: String?
    public let fallbackSeed: String
    public let cornerRadius: CGFloat
    public let showFavoriteOverlay: Bool

    public init(
        localPath: String? = nil,
        remoteURL: String? = nil,
        fallbackSeed: String = "Bebranoid",
        cornerRadius: CGFloat = 16,
        showFavoriteOverlay: Bool = false
    ) {
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.fallbackSeed = fallbackSeed
        self.cornerRadius = cornerRadius
        self.showFavoriteOverlay = showFavoriteOverlay
    }

    public var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let path = localPath, !path.isEmpty, let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let remote = remoteURL, let url = URL(string: remote) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackCover
                    }
                }
            } else {
                fallbackCover
            }
            #else
            fallbackCover
            #endif

            if showFavoriteOverlay {
                LinearGradient(
                    colors: [
                        Color(red: 0.92, green: 0.24, blue: 0.48).opacity(0.85),
                        Color(red: 0.48, green: 0.18, blue: 0.85).opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "heart.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallbackCover: some View {
        let palette = HarmonoidMeshEngine.mapPaletteToMeshColors(
            BebranoidAppState.deterministicSeedPalette(for: fallbackSeed)
        )
        let c0 = palette[0].normalizedDouble
        let c1 = palette[1].normalizedDouble
        let c2 = palette[2].normalizedDouble

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: c1.r, green: c1.g, blue: c1.b),
                    Color(red: c2.r, green: c2.g, blue: c2.b),
                    Color(red: c0.r, green: c0.g, blue: c0.b)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}
