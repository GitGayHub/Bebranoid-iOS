import SwiftUI
import WidgetKit
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

@available(iOS 16.2, *)
public struct BebranoidPlaybackAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var artist: String
        public var qualityBadge: String
        public var isPlaying: Bool
    }

    public var sessionId: String
}

@available(iOS 16.2, *)
public struct PlaybackLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: BebranoidPlaybackAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.68, green: 0.52, blue: 1.0))

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(context.state.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer()

                Text(context.state.qualityBadge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.15), in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.09, green: 0.06, blue: 0.18))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(Color(red: 0.68, green: 0.52, blue: 1.0))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.qualityBadge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.35))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(Color(red: 0.68, green: 0.52, blue: 1.0))
            } compactTrailing: {
                Text(context.state.qualityBadge)
                    .font(.system(size: 10, weight: .bold))
            } minimal: {
                Image(systemName: "music.note")
            }
        }
    }
}
#endif
