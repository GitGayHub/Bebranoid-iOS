import SwiftUI

/// Единая дизайн-система **Liquid Glass** (iOS 26 / iOS 27) для всех всплывающих меню, карточек, пилюль и модальных окон Bebranoid.
/// Обеспечивает:
/// - Настоящее преломление и просвечивание живого анимированного фона `HarmonoidMeshView` сквозь окна
/// - Нативный `glassEffect` на iOS 26+ в сочетании с многослойным оптическим бликом линзы и хроматической кромкой
/// - Глубокие мягкие тени и тактильную отзывчивость для флагманских дисплеев ProMotion 120 Гц
public enum LiquidGlassDesign {
    public static let sheetCornerRadius: CGFloat = 32
    public static let cardCornerRadius: CGFloat = 22
}

public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var tintColor: Color
    public var tintOpacity: Double
    public var isInteractive: Bool
    public var isSheer: Bool

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if isSheer {
            // Внутренние плашки внутри матовых штор в стиле Apple Music:
            // мягкая полупрозрачная подложка без двойного наложения блюра и без резких белых рамок
            content
                .background {
                    shape
                        .fill(Color.white.opacity(0.075))
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    tintColor.opacity(tintOpacity * 0.85),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    tintColor.opacity(0.12),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                }
        } else {
            // Плавающие карточки (Мини-плеер, баннер загрузки, превью контекстного меню) в стиле Apple Music:
            // полноценный матовый гауссов блюр `.ultraThinMaterial` (без размытия прозрачности `.opacity(0.36)`) + мягкий акцентный отсвет
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    tintColor.opacity(tintOpacity),
                                    Color.black.opacity(0.14)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    tintColor.opacity(0.18),
                                    Color.white.opacity(0.07)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.65
                        )
                }
                .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 8)
        }
    }
}

public struct LiquidGlassCapsuleModifier: ViewModifier {
    public var tintColor: Color
    public var isProminent: Bool
    public var isInteractive: Bool

    public func body(content: Content) -> some View {
        if isProminent {
            content
                .background {
                    Capsule()
                        .fill(tintColor)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                }
                .shadow(color: tintColor.opacity(0.28), radius: 10, x: 0, y: 4)
        } else {
            content
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(tintColor.opacity(0.09))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.20),
                                    Color.white.opacity(0.07),
                                    tintColor.opacity(0.14)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                }
        }
    }
}

public struct LiquidGlassCircleModifier: ViewModifier {
    public var tintColor: Color
    public var isHighlighted: Bool

    public func body(content: Content) -> some View {
        content
            .background {
                if isHighlighted {
                    Circle()
                        .fill(tintColor.opacity(0.90))
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                    Circle()
                        .fill(Color.white.opacity(0.08))
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            }
    }
}

/// Благородный матовый фон всплывающих окон в стиле Apple Music на iOS:
/// работает поверх нативного `.presentationBackground(.ultraThinMaterial)`, мягко окрашивая матовое стекло
/// рассеянным светом текущей обложки без просвечивания резкого текста снизу и без грубых белых обводок.
public struct LiquidGlassSheetBackdrop: View {
    public var accentColor: Color
    public var cornerRadius: CGFloat

    public init(accentColor: Color, cornerRadius: CGFloat = LiquidGlassDesign.sheetCornerRadius) {
        self.accentColor = accentColor
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            Color(red: 0.06, green: 0.06, blue: 0.09)
                .opacity(0.26)

            RadialGradient(
                colors: [
                    accentColor.opacity(0.18),
                    accentColor.opacity(0.05),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 12,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    accentColor.opacity(0.09),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 360
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.clear,
                    Color.black.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// Прозрачная стеклянная карточка предпросмотра для нативных контекстных всплывающих меню Apple (`contextMenu ... preview:`).
public struct LiquidGlassContextPreviewCard: View {
    public let track: Track?
    public let localPath: String?
    public let remoteURL: String?
    public let fallbackSeed: String
    public let title: String
    public let subtitle: String
    public let badgeText: String?
    public let accentColor: Color
    public var isCircularArtwork: Bool = false

    public init(
        track: Track? = nil,
        localPath: String? = nil,
        remoteURL: String? = nil,
        fallbackSeed: String,
        title: String,
        subtitle: String,
        badgeText: String? = nil,
        accentColor: Color,
        isCircularArtwork: Bool = false
    ) {
        self.track = track
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.fallbackSeed = fallbackSeed
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.accentColor = accentColor
        self.isCircularArtwork = isCircularArtwork
    }

    public var body: some View {
        HStack(spacing: 14) {
            ArtworkThumbnailView(
                track: track,
                localPath: localPath,
                remoteURL: remoteURL,
                fallbackSeed: fallbackSeed,
                cornerRadius: isCircularArtwork ? 36 : 14,
                sizeTier: .albumGrid
            )
            .frame(width: 72, height: 72)
            .clipShape(
                isCircularArtwork
                    ? AnyShape(Circle())
                    : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 4) {
                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(accentColor.opacity(0.22), in: Capsule())
                        .foregroundStyle(accentColor)
                }

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer(minLength: 4)
        }
        .padding(16)
        .frame(width: 310, alignment: .leading)
        .liquidGlassCard(cornerRadius: 24, tint: accentColor, tintOpacity: 0.10, isInteractive: false, isSheer: false)
    }
}

public extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = LiquidGlassDesign.cardCornerRadius,
        tint: Color = .white,
        tintOpacity: Double = 0.06,
        isInteractive: Bool = false,
        isSheer: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                tintColor: tint,
                tintOpacity: tintOpacity,
                isInteractive: isInteractive,
                isSheer: isSheer
            )
        )
    }

    func liquidGlassCapsule(
        tint: Color = .white,
        isProminent: Bool = false,
        isInteractive: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassCapsuleModifier(
                tintColor: tint,
                isProminent: isProminent,
                isInteractive: isInteractive
            )
        )
    }

    func liquidGlassCircle(
        tint: Color = .white,
        isHighlighted: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassCircleModifier(
                tintColor: tint,
                isHighlighted: isHighlighted
            )
        )
    }

    func liquidGlassSheetPresentation() -> some View {
        self
            .presentationBackground(.ultraThinMaterial)
            #if os(iOS)
            .presentationCornerRadius(LiquidGlassDesign.sheetCornerRadius)
            #endif
    }
}

/// Отдельная плавающая Liquid Glass менюшка скачивающегося трека:
/// пока новый трек качается из облака, текущий трек продолжает играть и остаётся полностью доступным в плеере!
public struct DownloadingTrackGlassBanner: View {
    @ObservedObject var appState: BebranoidAppState
    public let downloadingTrack: Track

    public init(appState: BebranoidAppState, downloadingTrack: Track) {
        self.appState = appState
        self.downloadingTrack = downloadingTrack
    }

    public var body: some View {
        let pct = appState.downloadProgress(for: downloadingTrack) ?? 2
        let normProgress = min(1.0, max(0.03, Double(pct) / 100.0))

        VStack(spacing: 7) {
            HStack(spacing: 11) {
                ArtworkThumbnailView(
                    track: downloadingTrack,
                    localPath: appState.libraryState.customAlbumCovers[downloadingTrack.album] ?? downloadingTrack.coverPath,
                    remoteURL: downloadingTrack.remoteArtworkURL,
                    fallbackSeed: "\(downloadingTrack.album)|\(downloadingTrack.artist)",
                    cornerRadius: 9,
                    sizeTier: .listThumbnail,
                    enableSmoothTransition: true
                )
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(appState.accentSwiftUIColor)
                        Text("Скачивается • \(pct)%")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(appState.accentSwiftUIColor)
                    }

                    Text("\(downloadingTrack.title) — \(downloadingTrack.artist)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                ProgressView()
                    .tint(appState.accentSwiftUIColor)
                    .scaleEffect(0.78)

                Button {
                    appState.haptics.softSelection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        appState.cancelPendingTrackDownload()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(appState.accentSwiftUIColor)
                        .frame(width: max(8, geo.size.width * normProgress))
                        .animation(.easeOut(duration: 0.20), value: normProgress)
                }
            }
            .frame(height: 3.5)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 20, tint: appState.accentSwiftUIColor, tintOpacity: 0.14, isInteractive: true)
    }
}
