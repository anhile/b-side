import AppIntents
import SwiftUI
import WidgetKit

/// The Now Playing widget, small and medium. Drawn by the widget extension
/// and, for the snapshots, by the app. System text colours and the app's
/// orange from the shared asset catalog, on the system's widget background.
struct NowPlayingWidgetView: View {
    let state: WidgetState
    let family: WidgetFamily

    private static let accent = Color("accentText")
    private static let onArtwork = Color.white

    var body: some View {
        Group {
            if !state.hasTrack {
                nothingPlaying
            } else if family == .systemSmall {
                small
            } else {
                medium
            }
        }
        .widgetURL(WidgetCommand.show.url)
    }

    /// The artwork fills the square; the names and Play sit on it.
    private var small: some View {
        ZStack(alignment: .bottom) {
            artwork(radius: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text(state.artist)
                        .font(.system(size: 11))
                        .opacity(0.8)
                        .lineLimit(1)
                }
                .foregroundStyle(Self.onArtwork)
                Spacer(minLength: 0)
                control(state.isPlaying ? "pause.fill" : "play.fill", size: 14, intent: PlayPauseIntent())
                    .foregroundStyle(Self.onArtwork)
            }
            .padding(12)
        }
        .containerBackground(for: .widget) { Color.black }
    }

    /// Artwork beside the names, the source above them, the transport under.
    private var medium: some View {
        HStack(spacing: 14) {
            artwork(radius: 10)
                .frame(width: 116, height: 116)
            VStack(alignment: .leading, spacing: 3) {
                if !state.source.isEmpty {
                    Label(state.source, systemImage: state.sourceSymbol.isEmpty ? "music.note" : state.sourceSymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Self.accent)
                        .lineLimit(1)
                }
                Text(state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(state.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 18) {
                    control("backward.fill", size: 15, intent: PreviousTrackIntent())
                    control(state.isPlaying ? "pause.fill" : "play.fill", size: 22, intent: PlayPauseIntent())
                    control("forward.fill", size: 15, intent: NextTrackIntent())
                }
                .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Nothing loaded, or the app is not running: a vibe starts it either way.
    private var nothingPlaying: some View {
        VStack(spacing: 6) {
            Image(systemName: "opticaldisc.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(state.appRunning ? "Nothing playing" : "B-Side is not running")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Button(intent: PlayVibeIntent()) {
                Label("Play Vibe", systemImage: "waveform")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private func artwork(radius: CGFloat) -> some View {
        if let data = state.artwork, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func control(_ symbol: String, size: CGFloat, intent: some AppIntent) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
