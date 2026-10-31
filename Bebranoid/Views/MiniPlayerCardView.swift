import SwiftUI

/// Плавающий Liquid Glass мини-плеер над нижним TabBar iPhone.
/// Отображает обложку, название трека, артиста, плашку качества (`Hi-Res` / `Lossless`), плавную полоску прогресса,
/// кнопку избранного, Play/Pause и Next. При нажатии или свайпе вверх открывает `FullScreenPlayerView`.
public struct MiniPlayerCardView: View {
    @ObservedObject var appState: BebranoidAppState

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        if let track = appState.currentTrack {
            let downloadPct = appState.downloadProgress(for: track)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ArtworkThumbnailView(
                        track: track,
                        localPath: appState.libraryState.customAlbumCovers[track.album] ?? track.coverPath,
                        remoteURL: track.remoteArtworkURL,
                        fallbackSeed: "\(track.album)|\(track.artist)",
                        cornerRadius: 11,
                        sizeTier: .listThumbnail,
                        enableSmoothTransition: true
                    )
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if let pct = downloadPct {
                                Text("\(pct)%")
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(appState.accentSwiftUIColor.opacity(0.28), in: Capsule())
                                    .foregroundStyle(appState.accentSwiftUIColor)
                            } else {
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
                        }

                        if let pct = downloadPct {
                            Text("Загрузка \(pct)% • \(track.artist)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(appState.accentSwiftUIColor)
                                .lineLimit(1)
                        } else {
                            Text(track.artist)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.70))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    Button {
                        appState.toggleFavorite(track: track)
                    } label: {
                        Image(systemName: appState.isFavorite(track) ? "heart.fill" : "heart")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(appState.isFavorite(track) ? Color(red: 1.0, green: 0.34, blue: 0.52) : .white.opacity(0.78))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    if downloadPct != nil {
                        ProgressView()
                            .tint(appState.accentSwiftUIColor)
                            .frame(width: 36, height: 36)
                    } else {
                        Button {
                            appState.togglePlayPause()
                        } label: {
                            Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        appState.skipToNext(isManualUserAction: true)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                TimelineView(.animation(minimumInterval: 0.12, paused: !appState.isPlaying)) { context in
                    let _ = context.date
                    let livePos = appState.isPlaying ? appState.audioEngine.livePlaybackTime : appState.currentTime
                    let effDur = appState.duration > 0 ? appState.duration : track.duration
                    let progress: Double = {
                        if let pct = downloadPct {
                            return min(1.0, max(0.02, Double(pct) / 100.0))
                        }
                        return effDur > 0 ? min(1.0, max(0.0, livePos / effDur)) : 0.0
                    }()

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
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .liquidGlassCard(cornerRadius: 20, tint: appState.accentSwiftUIColor, tintOpacity: 0.09, isInteractive: true)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
