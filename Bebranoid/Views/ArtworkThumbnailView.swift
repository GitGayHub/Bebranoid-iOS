import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Универсальный компонент отображения обложки трека/альбома/плейлиста (`src/components/Cover.jsx` 1:1).
/// Интегрирован с 7-уровневой цепочкой приоритетов `ArtworkService`:
/// 1. Пользовательская обложка (`customAlbumCovers` / `customCoverPath`)
/// 2. Локальный файл на диске (`Covers/<track>.jpg` или `Covers/albums/<album>.jpg`)
/// 3. Встроенная обложка внутри локального аудиофайла (`FLAC METADATA_BLOCK_PICTURE`, `ID3v2 APIC`, `M4A covr`)
/// 4. Миниатюра аудиосообщения Telegram (`coverFileId` через `downloadCoverFromTelegram`)
/// 5. Обложка соседнего трека того же альбома
/// 6. Миниатюра YouTube с квадратной обрезкой 16:9 / 4:3 -> 1:1 (`cropYouTubeThumbnailToSquare`)
/// 7. Детерминированный градиентный плейсхолдер (только при полном отсутствии реальной обложки)
public struct ArtworkThumbnailView: View {
    public var track: Track?
    public var localPath: String?
    public var remoteURL: String?
    public var fallbackSeed: String
    public var cornerRadius: CGFloat
    public var showFavoriteOverlay: Bool
    public var sizeTier: ArtworkSizeTier

    @State private var resolvedLocalPath: String?
    @State private var refreshTrigger: Int = 0

    public init(
        track: Track? = nil,
        localPath: String? = nil,
        remoteURL: String? = nil,
        fallbackSeed: String,
        cornerRadius: CGFloat = 12,
        showFavoriteOverlay: Bool = false,
        sizeTier: ArtworkSizeTier = .albumGrid
    ) {
        self.track = track
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.fallbackSeed = fallbackSeed
        self.cornerRadius = cornerRadius
        self.showFavoriteOverlay = showFavoriteOverlay
        self.sizeTier = sizeTier
    }

    private var effectiveLocalPath: String? {
        if let resolvedLocalPath, ArtworkService.shared.isValidImageFile(atPath: resolvedLocalPath) {
            return resolvedLocalPath
        }
        if let localPath, ArtworkService.shared.isValidImageFile(atPath: localPath) {
            return localPath
        }
        if let track,
           let syncHit = ArtworkService.shared.resolveLocalCoverURLSync(for: track) {
            return syncHit.url.path
        }
        return nil
    }

    public var body: some View {
        ZStack {
            if let path = effectiveLocalPath,
               let cgImage = ArtworkService.shared.loadCGImage(from: URL(fileURLWithPath: path), tier: sizeTier) {
                Image(decorative: cgImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else if let remoteStr = remoteURL ?? track?.remoteArtworkURL,
                      let url = URL(string: remoteStr) {
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

            if showFavoriteOverlay {
                ZStack {
                    Color.black.opacity(0.28)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.36, blue: 0.52))
                        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
                }
            }
        }
        .id("\(effectiveLocalPath ?? fallbackSeed)_\(refreshTrigger)")
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .task(id: track?.id ?? localPath ?? remoteURL ?? fallbackSeed) {
            guard effectiveLocalPath == nil, let track else { return }
            if let resolved = await ArtworkService.shared.resolveArtwork(for: track),
               let fileURL = resolved.fileURL {
                resolvedLocalPath = fileURL.path
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .artworkDidResolve)) { note in
            guard let info = note.userInfo else { return }
            let noteTrackId = info["trackId"] as? String
            let noteAlbum = info["albumName"] as? String
            let notePath = info["path"] as? String
            if (track != nil && noteTrackId == track?.id) ||
               (track != nil && noteAlbum == track?.album && !(noteAlbum ?? "").isEmpty) {
                if let notePath, !notePath.isEmpty {
                    resolvedLocalPath = notePath
                }
                refreshTrigger &+= 1
            }
        }
    }

    private var fallbackCover: some View {
        let pair = Self.gradientColors(for: fallbackSeed)
        return ZStack {
            LinearGradient(
                colors: [pair.0, pair.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private static func gradientColors(for seed: String) -> (Color, Color) {
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 7 + 48) % 360) / 360.0
        return (
            Color(hue: hue1, saturation: 0.62, brightness: 0.42),
            Color(hue: hue2, saturation: 0.72, brightness: 0.24)
        )
    }
}
