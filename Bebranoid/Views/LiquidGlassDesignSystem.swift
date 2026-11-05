import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Единая дизайн-система **Liquid Glass** (iOS 26 / iOS 27) для всех всплывающих меню, карточек, пилюль и модальных окон Bebranoid.
/// Обеспечивает:
/// - Настоящее преломление и просвечивание живого анимированного фона `HarmonoidMeshView` и треков сквозь плавающие панели
/// - Нативный `glassEffect(.clear)` на iOS 26+ в сочетании с тонким оптическим бликом линзы
/// - Минималистичную эстетику в стиле Apple Music без неонового пересвета
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
            content
                .background {
                    shape
                        .fill(Color.white.opacity(0.065))
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    tintColor.opacity(tintOpacity * 0.78),
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
                                    tintColor.opacity(0.11),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                }
        } else {
            // Воздушные прозрачные плавающие карточки (Мини-плеер, баннер загрузки, всплывающие карточки):
            // сквозь стекло мягко просвечивают обложки и живой фон, сохраняя читаемость текста
            let baseCard = content
                .background {
                    ZStack {
                        shape
                            .fill(.ultraThinMaterial)
                            .opacity(0.42)

                        shape
                            .fill(Color.black.opacity(0.08))

                        shape
                            .fill(tintColor.opacity(tintOpacity * 0.65))

                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.11),
                                        Color.clear,
                                        Color.black.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    tintColor.opacity(0.20),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.65
                        )
                }
                .shadow(color: Color.black.opacity(0.24), radius: 16, x: 0, y: 7)

            #if compiler(>=6.2)
            if #available(iOS 26.0, macOS 26.0, *) {
                baseCard
                    .glassEffect(
                        isInteractive
                            ? .clear.tint(tintColor.opacity(tintOpacity * 0.85)).interactive()
                            : .clear.tint(tintColor.opacity(tintOpacity * 0.85)),
                        in: shape
                    )
            } else {
                baseCard
            }
            #else
            baseCard
            #endif
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
                .shadow(color: tintColor.opacity(0.26), radius: 9, x: 0, y: 4)
        } else {
            content
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .opacity(0.56)
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(tintColor.opacity(0.08))
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
                        .opacity(0.58)
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

/// Прозрачный стеклянный фон модальных штор и всплывающих окон в стиле Apple Music на iOS:
/// мягко матирует и окрашивает подложку рассеянным светом текущей обложки, оставляя глубину сцены под окном.
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
                .opacity(0.76)

            Color(red: 0.05, green: 0.05, blue: 0.08)
                .opacity(0.22)

            RadialGradient(
                colors: [
                    accentColor.opacity(0.16),
                    accentColor.opacity(0.04),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 12,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    accentColor.opacity(0.08),
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
                    Color.black.opacity(0.16)
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

// MARK: - PC Rose Icons for Slowed (Red Rose) & Speed Up (Blue Rose)

/// Стилизация и оригинальные иконки увядшей красной розочки (`wilted-red.png`, Slowed)
/// и синей розочки (`wilted-blue.png`, Speed Up) в точном соответствии с настольной ПК-версией (`src/components/Player.jsx`).
public enum FXRoseStyle {
    public static func isSlowed(_ mode: AudioFXMode) -> Bool {
        mode == .slowed || mode == .slowedReverb
    }

    public static func isSpeedUp(_ mode: AudioFXMode) -> Bool {
        mode == .speedup || mode == .speedupReverb
    }

    public static func tintColor(for mode: AudioFXMode, fallbackAccent: Color) -> Color {
        if isSlowed(mode) {
            return Color(red: 0.94, green: 0.24, blue: 0.34)
        }
        if isSpeedUp(mode) {
            return Color(red: 0.27, green: 0.58, blue: 1.0)
        }
        return fallbackAccent
    }

    #if canImport(UIKit)
    private static let redRoseBase64 = "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"

    private static let blueRoseBase64 = "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"

    public static let cachedRedRoseImage: UIImage? = {
        if let bundled = UIImage(named: "wilted-red") {
            return bundled
        }
        guard let data = Data(base64Encoded: redRoseBase64) else { return nil }
        return UIImage(data: data)
    }()

    public static let cachedBlueRoseImage: UIImage? = {
        if let bundled = UIImage(named: "wilted-blue") {
            return bundled
        }
        guard let data = Data(base64Encoded: blueRoseBase64) else { return nil }
        return UIImage(data: data)
    }()
    #endif
}

/// Значок красной розочки для `Slowed` и синей розочки для `Speed Up` из компьютерной версии (`public/fx/wilted-red.png`, `wilted-blue.png`).
public struct FXRoseBadgeIcon: View {
    public let mode: AudioFXMode
    public var size: CGFloat = 14

    public init(mode: AudioFXMode, size: CGFloat = 14) {
        self.mode = mode
        self.size = size
    }

    public var body: some View {
        #if canImport(UIKit)
        if FXRoseStyle.isSlowed(mode), let uiImg = FXRoseStyle.cachedRedRoseImage {
            Image(uiImage: uiImg)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else if FXRoseStyle.isSpeedUp(mode), let uiImg = FXRoseStyle.cachedBlueRoseImage {
            Image(uiImage: uiImg)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: max(10, size - 2), weight: .bold))
        }
        #else
        Image(systemName: "waveform")
            .font(.system(size: max(10, size - 2), weight: .bold))
        #endif
    }
}

// MARK: - Track Metadata & Telegram Deep-Link Helpers (PC TrackInfoModal.jsx Parity)

public enum TrackMetadataActions {
    public static func canJumpToTelegram(_ track: Track) -> Bool {
        track.sourceKind == .telegram && track.chatId != nil && track.messageId != nil
    }

    /// Открывает сообщение с треком напрямую в приложении Telegram (`electron/main.js` `jumpToTelegramMessage` parity)
    public static func openInTelegram(_ track: Track) {
        guard let rawChatString = track.chatId, let rawMessageIdInt = track.messageId else { return }
        let rawMessageId = Int64(rawMessageIdInt)
        let cleanChatId: String
        if rawChatString.hasPrefix("-100") {
            cleanChatId = String(rawChatString.dropFirst(4))
        } else if rawChatString.hasPrefix("-") {
            cleanChatId = String(rawChatString.dropFirst(1))
        } else {
            cleanChatId = rawChatString
        }
        // В TDLib внутренний message.id сдвинут на 20 бит (× 1048576), а публичный пост в t.me/c/ использует серверный ID
        let postId: Int64 = (rawMessageId >= 1_048_576 && rawMessageId % 1_048_576 == 0)
            ? (rawMessageId / 1_048_576)
            : rawMessageId

        #if canImport(UIKit)
        let tgURL = URL(string: "tg://privatepost?channel=\(cleanChatId)&post=\(postId)")
        let webURL = URL(string: "https://t.me/c/\(cleanChatId)/\(postId)")
        if let tgURL {
            UIApplication.shared.open(tgURL, options: [:]) { success in
                if !success, let webURL {
                    UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
                }
            }
        } else if let webURL {
            UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
        }
        #endif
    }

    /// Форматирует дату выгрузки трека в стиле `src/lib/dates.js` (`formatRelativeStamp`):
    /// «сегодня 21:14», «вчера 18:30» или «04.11.26 21:14».
    public static func formatUploadDate(_ date: Date?) -> String {
        guard let date else { return "Неизвестно" }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ru_RU")
        timeFormatter.dateFormat = "HH:mm"
        let timePart = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "сегодня \(timePart)"
        }
        if calendar.isDateInYesterday(date) {
            return "вчера \(timePart)"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "dd.MM.yy"
        return "\(dateFormatter.string(from: date)) \(timePart)"
    }
}

/// Отдельная плавающая Liquid Glass менюшка скачивающегося трека:
/// пока новый трек качается из облака, текущий трек продолжает играть и остаётся полностью доступным в плеере,
/// а обводка и прогресс баннера окрашиваются в собственный цвет обложки скачивающегося трека!
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
        let downloadAccent = appState.downloadAccentColor(for: downloadingTrack)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

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
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(downloadAccent.opacity(0.85), lineWidth: 1.2)
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(downloadAccent)
                        Text("Скачивается • \(pct)%")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(downloadAccent)
                    }

                    Text("\(downloadingTrack.title) — \(downloadingTrack.artist)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                ProgressView()
                    .tint(downloadAccent)
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
                        .fill(downloadAccent)
                        .frame(width: max(8, geo.size.width * normProgress))
                        .animation(.easeOut(duration: 0.20), value: normProgress)
                }
            }
            .frame(height: 3.5)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 20, tint: downloadAccent, tintOpacity: 0.16, isInteractive: true)
        .overlay(
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            downloadAccent.opacity(0.88),
                            downloadAccent.opacity(0.42),
                            downloadAccent.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.35
                )
        )
    }
}
