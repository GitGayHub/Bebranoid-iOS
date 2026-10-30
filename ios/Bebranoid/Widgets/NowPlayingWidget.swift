import WidgetKit
import SwiftUI

public struct NowPlayingWidgetEntry: TimelineEntry {
    public let date: Date
    public let title: String
    public let artist: String
    public let album: String
    public let qualityBadge: String
}

public struct NowPlayingTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> NowPlayingWidgetEntry {
        NowPlayingWidgetEntry(
            date: Date(),
            title: "Звезда по имени Солнце",
            artist: "Кино",
            album: "Звезда по имени Солнце",
            qualityBadge: "FLAC Hi-Res"
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (NowPlayingWidgetEntry) -> Void) {
        completion(loadCurrentEntry())
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingWidgetEntry>) -> Void) {
        let entry = loadCurrentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadCurrentEntry() -> NowPlayingWidgetEntry {
        let defaults = UserDefaults(suiteName: "group.com.bebranoid.ios")
        let title = defaults?.string(forKey: "widget_track_title") ?? "Bebranoid"
        let artist = defaults?.string(forKey: "widget_track_artist") ?? "Готов к воспроизведению"
        let album = defaults?.string(forKey: "widget_track_album") ?? "Медиатека"
        let badge = defaults?.string(forKey: "widget_quality_badge") ?? "Lossless"
        return NowPlayingWidgetEntry(date: Date(), title: title, artist: artist, album: album, qualityBadge: badge)
    }
}

public struct NowPlayingWidget: Widget {
    public let kind: String = "BebranoidNowPlayingWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingTimelineProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.66, green: 0.51, blue: 1.0))
                    Spacer()
                    Text(entry.qualityBadge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(entry.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(entry.artist)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(14)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color(red: 0.14, green: 0.09, blue: 0.28),
                        Color(red: 0.07, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .configurationDisplayName("Bebranoid Плеер")
        .description("Быстрый доступ к текущему треку и качеству аудио.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
