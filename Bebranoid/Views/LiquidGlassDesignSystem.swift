import SwiftUI

/// Единая дизайн-система **Liquid Glass** (iOS 26 / iOS 27) для всех всплывающих меню, карточек, пилюль и модальных окон Bebranoid.
/// Обеспечивает:
/// - Настоящее преломление и просвечивание живого анимированного фона `HarmonoidMeshView` сквозь окна
/// - Нативный `glassEffect` на iOS 26+ в сочетании с многослойным оптическим бликом линзы и хроматической кромкой
/// - Глубокие мягкие тени и тактильную отзывчивость для флагманских дисплеев ProMotion 120 Гц
public enum LiquidGlassDesign {
    public static let sheetCornerRadius: CGFloat = 36
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
        #if os(iOS) && compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .background {
                    if !isSheer {
                        shape
                            .fill(.ultraThinMaterial)
                            .opacity(0.36)
                    }
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isSheer ? 0.08 : 0.11),
                                    tintColor.opacity(tintOpacity),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .glassEffect(isInteractive ? .clear.interactive() : .clear, in: shape)
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.50),
                                    tintColor.opacity(0.30),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                }
                .shadow(color: Color.black.opacity(isSheer ? 0.12 : 0.22), radius: isSheer ? 10 : 16, x: 0, y: isSheer ? 5 : 8)
        } else {
            fallbackGlassBody(content: content, shape: shape)
        }
        #else
        fallbackGlassBody(content: content, shape: shape)
        #endif
    }

    @ViewBuilder
    private func fallbackGlassBody(content: Content, shape: RoundedRectangle) -> some View {
        content
            .background {
                if !isSheer {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.76)
                }
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSheer ? 0.09 : 0.13),
                                tintColor.opacity(tintOpacity),
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
                                Color.white.opacity(0.48),
                                tintColor.opacity(0.28),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.95
                    )
            }
            .shadow(color: Color.black.opacity(isSheer ? 0.14 : 0.24), radius: isSheer ? 10 : 18, x: 0, y: isSheer ? 5 : 9)
    }
}

public struct LiquidGlassCapsuleModifier: ViewModifier {
    public var tintColor: Color
    public var isProminent: Bool
    public var isInteractive: Bool

    public func body(content: Content) -> some View {
        #if os(iOS) && compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .background {
                    if isProminent {
                        Capsule()
                            .fill(tintColor.opacity(0.88))
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.28)
                        Capsule()
                            .fill(tintColor.opacity(0.08))
                    }
                }
                .glassEffect(isInteractive ? .clear.interactive() : .clear, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isProminent ? 0.58 : 0.46),
                                    Color.white.opacity(0.08),
                                    tintColor.opacity(0.26)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.85
                        )
                }
        } else {
            fallbackCapsule(content: content)
        }
        #else
        fallbackCapsule(content: content)
        #endif
    }

    @ViewBuilder
    private func fallbackCapsule(content: Content) -> some View {
        if isProminent {
            content
                .background(tintColor, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.85)
                )
                .shadow(color: tintColor.opacity(0.34), radius: 10, x: 0, y: 4)
        } else {
            content
                .background(.ultraThinMaterial.opacity(0.72), in: Capsule())
                .background(tintColor.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.44),
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.85
                        )
                )
        }
    }
}

public struct LiquidGlassCircleModifier: ViewModifier {
    public var tintColor: Color
    public var isHighlighted: Bool

    public func body(content: Content) -> some View {
        #if os(iOS) && compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .background {
                    if isHighlighted {
                        Circle()
                            .fill(tintColor.opacity(0.88))
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.28)
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    }
                }
                .glassEffect(.clear.interactive(), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.50),
                                    Color.white.opacity(0.10),
                                    tintColor.opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.85
                        )
                }
        } else {
            fallbackCircle(content: content)
        }
        #else
        fallbackCircle(content: content)
        #endif
    }

    @ViewBuilder
    private func fallbackCircle(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.72), in: Circle())
            .background(isHighlighted ? tintColor.opacity(0.85) : Color.white.opacity(0.06), in: Circle())
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            )
    }
}

/// Кристально прозрачный рефракционный фон Apple Liquid Glass для всех всплывающих штор (`Sheet`) и модальных меню,
/// сквозь который отчётливо просвечивается обложка, текст или живой `HarmonoidMeshView` под окном.
public struct LiquidGlassSheetBackdrop: View {
    public var accentColor: Color
    public var cornerRadius: CGFloat

    public init(accentColor: Color, cornerRadius: CGFloat = LiquidGlassDesign.sheetCornerRadius) {
        self.accentColor = accentColor
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let sheetShape = UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: cornerRadius,
            style: .continuous
        )

        #if os(iOS) && compiler(>=6.2)
        if #available(iOS 26.0, *) {
            ZStack {
                sheetShape
                    .fill(.ultraThinMaterial)
                    .opacity(0.42)

                RadialGradient(
                    colors: [
                        accentColor.opacity(0.13),
                        accentColor.opacity(0.03),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 360
                )
                .clipShape(sheetShape)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.02),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(sheetShape)
            }
            .glassEffect(.clear, in: sheetShape)
            .overlay {
                sheetShape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.56),
                                accentColor.opacity(0.30),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            }
            .ignoresSafeArea()
        } else {
            fallbackSheetBackdrop(sheetShape: sheetShape)
        }
        #else
        fallbackSheetBackdrop(sheetShape: sheetShape)
        #endif
    }

    @ViewBuilder
    private func fallbackSheetBackdrop(sheetShape: UnevenRoundedRectangle) -> some View {
        ZStack {
            sheetShape
                .fill(.ultraThinMaterial)
                .opacity(0.68)

            RadialGradient(
                colors: [
                    accentColor.opacity(0.13),
                    accentColor.opacity(0.03),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 8,
                endRadius: 360
            )
            .clipShape(sheetShape)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(sheetShape)
        }
        .overlay {
            sheetShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.50),
                            accentColor.opacity(0.26),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
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
            .presentationBackground(.clear)
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
