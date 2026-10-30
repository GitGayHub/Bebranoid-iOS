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

    @State private var asyncLoadedCGImage: CGImage?

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

    private var taskIdentifier: String {
        if let id = track?.id { return id }
        if let lp = localPath, !lp.isEmpty { return lp }
        if let ru = remoteURL, !ru.isEmpty { return ru }
        return fallbackSeed
    }

    public var body: some View {
        ZStack {
            artworkImageLayer
            if showFavoriteOverlay {
                favoriteOverlayLayer
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(borderOverlay)
        .task(id: taskIdentifier) {
            await loadArtworkOffMainThreadIfNeeded()
        }
    }

    @ViewBuilder
    private var artworkImageLayer: some View {
        if let cgImage = asyncLoadedCGImage ?? ArtworkService.shared.memoryCachedImage(forKey: taskIdentifier, tier: sizeTier) {
            Image(decorative: cgImage, scale: 1.0, orientation: .up)
                .resizable()
                .scaledToFill()
        } else {
            fallbackCover
        }
    }

    private var favoriteOverlayLayer: some View {
        ZStack {
            Color.black.opacity(0.28)
            Image(systemName: "heart.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.36, blue: 0.52))
                .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
        }
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
    }

    private func loadArtworkOffMainThreadIfNeeded() async {
        let key = taskIdentifier
        let tier = sizeTier
        if let cached = ArtworkService.shared.memoryCachedImage(forKey: key, tier: tier) {
            if asyncLoadedCGImage !== cached {
                asyncLoadedCGImage = cached
            }
            return
        }

        let capturedTrack = track
        let capturedLocalPath = localPath
        let cgResult: CGImage? = await Task.detached(priority: .utility) {
            if let lp = capturedLocalPath, !lp.isEmpty, ArtworkService.shared.isValidImageFile(atPath: lp) {
                if let cg = ArtworkService.shared.loadCGImage(from: URL(fileURLWithPath: lp), tier: tier) {
                    ArtworkService.shared.storeMemoryCachedImage(cg, forKey: key, tier: tier)
                    return cg
                }
            }
            if let tr = capturedTrack {
                if let syncHit = ArtworkService.shared.resolveLocalCoverURLSync(for: tr),
                   let cg = ArtworkService.shared.loadCGImage(from: syncHit.url, tier: tier) {
                    ArtworkService.shared.storeMemoryCachedImage(cg, forKey: key, tier: tier)
                    return cg
                }
                if let resolved = await ArtworkService.shared.resolveArtwork(for: tr),
                   let fileURL = resolved.fileURL,
                   let cg = ArtworkService.shared.loadCGImage(from: fileURL, tier: tier) {
                    ArtworkService.shared.storeMemoryCachedImage(cg, forKey: key, tier: tier)
                    return cg
                }
            }
            return nil
        }.value

        if !Task.isCancelled, let cgResult {
            asyncLoadedCGImage = cgResult
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
