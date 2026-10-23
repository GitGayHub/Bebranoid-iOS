import SwiftUI

/// Плавающий стеклянный мини-плеер над нижним TabBar iPhone.
/// Отображает обложку, название трека, артиста, плашку качества (`Hi-Res` / `Lossless`), тонкую полоску прогресса,
/// кнопку избранного, Play/Pause и Next. При нажатии или свайпе вверх открывает `FullScreenPlayerView`.
public struct MiniPlayerCardView: View {
    @ObservedObject var appState: BebranoidAppState

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        if let track = appState.currentTrack {
            let progress = appState.duration > 0 ? min(1.0, max(0.0, appState.currentTime / appState.duration)) : 0.0

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ArtworkThumbnailView(
                        localPath: appState.libraryState.customAlbumCovers[track.album] ?? track.coverPath,
                        remoteURL: track.remoteArtworkURL,
                        fallbackSeed: "\(track.album)|\(track.artist)",
                        cornerRadius: 10
                    )
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            let badge = appState.currentQualityBadge
                            if badge.tier == .hiRes || badge.tier == .lossless {
                                Text(badge.tier == .hiRes ? "Hi-Res" : "Lossless")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(appState.accentSwiftUIColor.opacity(0.24), in: Capsule())
                                    .foregroundStyle(appState.accentSwiftUIColor)
                            }
                        }

                        Text(track.artist)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        appState.toggleFavorite(track: track)
                    } label: {
                        Image(systemName: appState.isFavorite(track) ? "heart.fill" : "heart")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(appState.isFavorite(track) ? Color(red: 1.0, green: 0.34, blue: 0.52) : .white.opacity(0.75))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.togglePlayPause()
                    } label: {
                        Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.skipToNext(isManualUserAction: true)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                        Rectangle()
                            .fill(appState.accentSwiftUIColor)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 2.5)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {
                appState.haptics.lightTap()
                appState.isFullScreenPlayerPresented = true
            }
            .gesture(
                DragGesture(minimumDistance: 16)
                    .onEnded { value in
                        if value.translation.height < -20 {
                            appState.haptics.lightTap()
                            appState.isFullScreenPlayerPresented = true
                        } else if value.translation.width < -40 {
                            appState.skipToNext(isManualUserAction: true)
                        } else if value.translation.width > 40 {
                            appState.skipToPrevious()
                        }
                    }
            )
        }
    }
}
