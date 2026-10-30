import Foundation
import MediaPlayer
#if canImport(UIKit)
import UIKit
#endif

/// Интеграция с экраном блокировки iOS, Control Center, Dynamic Island и гарнитурой (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`).
@MainActor
public final class NowPlayingSessionManager {
    public static let shared = NowPlayingSessionManager()

    private var isConfigured = false

    public var onPlayCommand: (() -> Void)?
    public var onPauseCommand: (() -> Void)?
    public var onTogglePlayPauseCommand: (() -> Void)?
    public var onNextTrackCommand: (() -> Void)?
    public var onPreviousTrackCommand: (() -> Void)?
    public var onSeekCommand: ((Double) -> Void)?
    public var onToggleLikeCommand: (() -> Void)?

    private init() {}

    public func configureRemoteCommandsIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPlayCommand?() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPauseCommand?() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onTogglePlayPauseCommand?() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onNextTrackCommand?() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPreviousTrackCommand?() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let targetTime = posEvent.positionTime
            Task { @MainActor [weak self] in self?.onSeekCommand?(targetTime) }
            return .success
        }

        center.likeCommand.isEnabled = true
        center.likeCommand.localizedTitle = "В Любимые"
        center.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onToggleLikeCommand?() }
            return .success
        }
    }

    public func updateNowPlaying(
        track: Track?,
        isPlaying: Bool,
        currentTime: Double,
        duration: Double,
        playbackRate: Float,
        artworkData: Data? = nil
    ) {
        guard let track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: max(0.0, duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0.0, currentTime),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        #if canImport(UIKit)
        if let artworkData, let image = UIImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        } else if let coverPath = track.coverPath, let image = UIImage(contentsOfFile: coverPath) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        #endif

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
