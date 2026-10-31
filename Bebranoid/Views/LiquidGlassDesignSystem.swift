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

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if os(iOS) && compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .background {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    tintColor.opacity(tintOpacity),
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    tintColor.opacity(0.28),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                }
                .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 10)
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
            .background(.ultraThinMaterial, in: shape)
            .background {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.13),
                                tintColor.opacity(tintOpacity),
                                Color.black.opacity(0.12)
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
                                tintColor.opacity(0.30),
                                Color.white.opacity(0.07),
                                Color.white.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            }
            .shadow(color: Color.black.opacity(0.32), radius: 20, x: 0, y: 10)
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
                            .fill(tintColor.opacity(0.86))
                    } else {
                        Capsule()
                            .fill(tintColor.opacity(0.10))
                    }
                }
                .glassEffect(isInteractive ? .regular.interactive() : .regular, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isProminent ? 0.55 : 0.42),
                                    Color.white.opacity(0.08),
                                    tintColor.opacity(0.25)
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
                .shadow(color: tintColor.opacity(0.38), radius: 10, x: 0, y: 4)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .background(tintColor.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.42),
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
                    Circle()
                        .fill(isHighlighted ? tintColor.opacity(0.86) : Color.white.opacity(0.06))
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.48),
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
            .background(.ultraThinMaterial, in: Circle())
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

/// Прозрачный рефракционный фон для всех всплывающих штор (`Sheet`), сквозь который просвечивается живой `HarmonoidMeshView`
public struct LiquidGlassSheetBackdrop: View {
    public var accentColor: Color

    public init(accentColor: Color) {
        self.accentColor = accentColor
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            RadialGradient(
                colors: [
                    accentColor.opacity(0.20),
                    accentColor.opacity(0.05),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 12,
                endRadius: 380
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear,
                    Color.black.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

public extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = LiquidGlassDesign.cardCornerRadius,
        tint: Color = .white,
        tintOpacity: Double = 0.06,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                tintColor: tint,
                tintOpacity: tintOpacity,
                isInteractive: isInteractive
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
