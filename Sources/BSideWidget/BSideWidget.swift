import SwiftUI
import WidgetKit

/// The widget extension: one widget, Now Playing. It asks the running app
/// what plays; the app has WidgetKit redraw it whenever that changes, so
/// the timeline itself never expires.
@main
struct BSideWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetState.widgetKind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(state: entry.state, family: entry.family)
        }
        .configurationDisplayName("Now Playing")
        .description("What B-Side plays, with Play, Pause and Next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
    let family: WidgetFamily
}

struct NowPlayingProvider: TimelineProvider {
    private static let sample: WidgetState = {
        var state = WidgetState()
        state.hasTrack = true
        state.isPlaying = true
        state.title = "Blood Like Lemonade"
        state.artist = "Morcheeba"
        state.source = "Liked Music"
        state.sourceSymbol = "heart.fill"
        return state
    }()

    /// What the app says, or "not running".
    private static func current() -> WidgetState {
        if let state = WidgetPort.askState() { return state }
        var state = WidgetState()
        state.appRunning = false
        return state
    }

    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), state: Self.sample, family: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(NowPlayingEntry(date: Date(), state: context.isPreview ? Self.sample : Self.current(), family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        completion(Timeline(entries: [NowPlayingEntry(date: Date(), state: Self.current(), family: context.family)], policy: .never))
    }
}
