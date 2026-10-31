import AppIntents
import SwiftUI
import WidgetKit

/// The Now Playing widget, small and medium. Drawn by the widget extension
/// and, for the snapshots, by the app.
///
/// In full colour the widget sits on its own artwork, blurred and darkened,
/// with the cover in front and the record half out of it, as Now Playing
/// has them, and everything on it in white. On the desktop macOS draws
/// widgets "vibrant" while windows are in front: every picture becomes a
/// flat silhouette, so there the cover gives way to a drawn record and the
/// text keeps the system's colours.
struct NowPlayingWidgetView: View {
    let state: WidgetState
    let family: WidgetFamily
    /// Snapshots: the vibrant layout, which a renderer cannot be put in.
    var previewVibrant = false

    @Environment(\.widgetRenderingMode) private var renderingMode

    private static let accent = Color("accentText")
    private static let label = Color("accent")
    private static let onArtwork = Color.white

    private var vibrant: Bool { previewVibrant || renderingMode != .fullColor }

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
        .containerBackground(for: .widget) { Self.backdrop(for: state, vibrant: vibrant) }
    }

    /// Behind everything: the artwork blurred and darkened while a track
    /// has one, the system's fill otherwise. Public for the snapshots,
    /// whose renderer does not draw a container background.
    @ViewBuilder static func backdrop(for state: WidgetState, vibrant: Bool) -> some View {
        if !vibrant, state.hasTrack {
            ZStack {
                Color.black
                if let image = state.artwork.flatMap(NSImage.init(data:)) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 28)
                        .saturation(1.3)
                        .opacity(0.85)
                } else {
                    LinearGradient(colors: [label, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            }
        } else {
            Rectangle().fill(.fill.tertiary)
        }
    }

    // MARK: Small

    /// Full colour: the cover fills the square, the names and Play on it.
    /// Vibrant: the record, the names under it, Play beside them.
    private var small: some View {
        ZStack(alignment: .bottom) {
            if vibrant {
                VStack(alignment: .leading, spacing: 0) {
                    Self.record(size: 52)
                    Spacer(minLength: 6)
                    names(title: 13, artist: 11, lines: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topTrailing) { playButton(size: 30) }
            } else {
                artwork(radius: 0)
                    .padding(-16) // to the widget's edges, past its content margins
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    .padding(-16)
                HStack(alignment: .bottom, spacing: 8) {
                    names(title: 13, artist: 11, lines: 2)
                    Spacer(minLength: 0)
                    playButton(size: 30)
                }
            }
        }
    }

    // MARK: Medium

    /// The cover with the record half out of it, the source, the names and
    /// the transport beside it.
    private var medium: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .leading) {
                // Alone, the record stands in the middle of its room; with
                // the cover, half out of it.
                Self.record(size: 104)
                    .offset(x: vibrant ? 16 : 32)
                if !vibrant {
                    artwork(radius: 8)
                        .frame(width: 104, height: 104)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                }
            }
            .frame(width: 136, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                if !state.source.isEmpty {
                    Label(state.source, systemImage: state.sourceSymbol.isEmpty ? "music.note" : state.sourceSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(vibrant ? AnyShapeStyle(Self.accent) : AnyShapeStyle(Self.onArtwork.opacity(0.75)))
                        .lineLimit(1)
                        .padding(.bottom, 4)
                }
                names(title: 15, artist: 13, lines: 2)
                Spacer(minLength: 6)
                HStack(spacing: 14) {
                    control("backward.fill", size: 14, intent: PreviousTrackIntent())
                    playButton(size: 34)
                    control("forward.fill", size: 14, intent: NextTrackIntent())
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Nothing playing

    /// Nothing loaded, or the app is not running: a vibe starts it either way.
    private var nothingPlaying: some View {
        VStack(spacing: 8) {
            Self.record(size: family == .systemSmall ? 56 : 64)
            VStack(spacing: 2) {
                Text(state.appRunning ? "Nothing playing" : "B-Side is not running")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if family != .systemSmall {
                    Text("A vibe starts the music.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Button(intent: PlayVibeIntent()) {
                Label("Play Vibe", systemImage: "waveform")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Self.label)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Parts

    private func names(title: CGFloat, artist: CGFloat, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.title)
                .font(.system(size: title, weight: .semibold))
                .lineLimit(lines)
            Text(state.artist)
                .font(.system(size: artist))
                .opacity(vibrant ? 1 : 0.75)
                .foregroundStyle(vibrant ? .secondary : .primary)
                .lineLimit(1)
        }
        .foregroundStyle(vibrant ? AnyShapeStyle(.primary) : AnyShapeStyle(Self.onArtwork))
    }

    /// Play or Pause in a filled circle: the one control that matters most.
    private func playButton(size: CGFloat) -> some View {
        Button(intent: PlayPauseIntent()) {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(vibrant ? AnyShapeStyle(.background) : AnyShapeStyle(Color.black))
                .frame(width: size, height: size)
                .background(vibrant ? AnyShapeStyle(.primary) : AnyShapeStyle(Self.onArtwork), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func control(_ symbol: String, size: CGFloat, intent: some AppIntent) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(vibrant ? AnyShapeStyle(.primary) : AnyShapeStyle(Self.onArtwork))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func artwork(radius: CGFloat) -> some View {
        if let data = state.artwork, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Self.label, .black.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Self.onArtwork.opacity(0.85))
                }
        }
    }

    /// The app's record, drawn with shapes: black with a few grooves and the
    /// orange label, as on the icon. Shapes keep their form in vibrant mode.
    static func record(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.08))
            ForEach([0.92, 0.8, 0.68, 0.56], id: \.self) { ratio in
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: max(size / 160, 0.5))
                    .frame(width: size * ratio, height: size * ratio)
            }
            Circle().fill(label).frame(width: size * 0.36, height: size * 0.36)
            Circle().fill(Color(white: 0.08)).frame(width: size * 0.05, height: size * 0.05)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: size / 20, y: size / 40)
        .accessibilityHidden(true)
    }
}
