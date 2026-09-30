import AppKit
import SwiftUI

/// One job: see what plays and control it.
struct NowPlayingPage: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    /// Set while the user drags the slider, so reports do not fight the drag.
    @State private var scrub: Double?
    @State private var showsVolume = false
    @State private var tintBottom: CGFloat = 0
    @State private var hoveringArtwork = false
    @State private var showsLyrics = false
    @Environment(\.previewArtworkHover) private var previewArtworkHover

    var body: some View {
        if let blocked = blockingState(for: player) {
            blocked
        } else if player.hasTrack {
            content
        } else {
            nothingPlaying
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            artworkZone
                .layoutPriority(1) // the record takes the free height, not the gaps
            Spacer(minLength: Theme.Space.s)
            VStack(spacing: Theme.Space.xxs) {
                Text(title)
                    .font(Theme.Text.title)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .help(title)
                Text(subtitle)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .lineLimit(1)
                    .help(subtitle)
            }
            .padding(.horizontal, Theme.Space.m)
            Spacer(minLength: Theme.Space.m)
            progress
                .padding(.horizontal, Theme.Space.m)
            Spacer(minLength: Theme.Space.m)
            transport
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.m) // as far from the bottom as from the sides
        }
    }

    /// The zone the artwork's colour fills: from the top of the page to half
    /// way to the title. While the pointer is over it (or the lyrics are
    /// open), a dark veil covers all of it, with Like and Lyrics in the middle.
    private var artworkZone: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.m)
            ArtworkWithRecord(url: player.state.artworkURL, spinning: player.state.isPlaying)
            Spacer(minLength: Theme.Space.s)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("window")).maxY } action: { tintBottom = $0 }
        .preference(key: TintBottomKey.self, value: tintBottom)
        .overlay {
            if showsArtworkActions {
                ZStack {
                    Theme.Colors.shadow.opacity(Theme.Opacity.scrim)
                    artworkActions
                }
                .environment(\.colorScheme, .dark) // light glass and icons on the veil
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hoveringArtwork = $0 }
        .animation(.easeOut(duration: Theme.Motion.feedback), value: showsArtworkActions)
    }

    private var showsArtworkActions: Bool {
        hoveringArtwork || showsLyrics || previewArtworkHover
    }

    private var artworkActions: some View {
        HStack(spacing: Theme.Space.s) {
            TransportButton(symbol: player.state.isLiked ? "heart.fill" : "heart",
                            label: player.state.isLiked ? "Remove Like" : "Like",
                            glyph: Theme.Size.playGlyph, target: Theme.Size.artworkAction) {
                player.toggleLike()
            }
            .glass(in: Circle())
            .disabled(player.state.isAd)
            TransportButton(symbol: "quote.bubble", label: "Lyrics",
                            glyph: Theme.Size.playGlyph, target: Theme.Size.artworkAction) {
                showsLyrics = true
            }
            .glass(in: Circle())
            .popover(isPresented: $showsLyrics, arrowEdge: .bottom) {
                LyricsPanel()
            }
        }
    }

    /// An ad is named as such; its own title, if any, goes to the second line.
    private var title: String {
        if player.state.isAd { return "Advertisement" }
        return player.state.title.isEmpty ? "Loading…" : player.state.title
    }

    private var subtitle: String {
        player.state.isAd ? player.state.title : player.state.artist
    }

    /// The record alone, and the two ways to start: the same words and icons
    /// as the pages they lead to.
    private var nothingPlaying: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.m)
            Record(size: Theme.Size.artworkLarge, spinning: false)
            Spacer(minLength: Theme.Space.l)
            Text("Nothing playing")
                .font(Theme.Text.display)
                .foregroundStyle(Theme.Colors.text)
            Text(player.isGuest ? "Add a vibe from a track, or sign in" : "Pick a vibe or a playlist")
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .padding(.top, Theme.Space.xxs)
            HStack(spacing: Theme.Space.xs) {
                Button { player.playVibe() } label: {
                    Label("Play Vibe", systemImage: Page.vibe.symbol)
                }
                .buttonStyle(FilledButtonStyle())
                .disabled(player.vibeMood == nil)
                // A guest has no playlists: the way to them is signing in.
                if player.isGuest {
                    Button { player.showSignIn() } label: {
                        Label("Sign In…", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(OutlineButtonStyle())
                } else {
                    Button { navigation.page = .playlists } label: {
                        Label("Playlists", systemImage: Page.playlists.symbol)
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
            }
            .padding(.top, Theme.Space.m)
            Spacer(minLength: Theme.Space.l)
        }
        .frame(maxWidth: .infinity)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = max(player.state.duration, 1)
            let position = scrub ?? min(player.position(at: context.date), duration)
            VStack(spacing: 0) {
                Slider(
                    value: Binding(get: { position }, set: { scrub = $0 }),
                    in: 0...duration
                ) { editing in
                    if !editing, let target = scrub {
                        player.seek(to: target)
                        scrub = nil
                    }
                }
                .controlSize(.small)
                .tint(Theme.Colors.accent) // tokens-ok
                .disabled(player.state.duration <= 0 || player.state.isAd)
                .accessibilityLabel("Position")
                HStack {
                    Text(time(position))
                    Spacer()
                    Text(time(player.state.duration))
                }
                .font(Theme.Text.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textMuted)
            }
        }
    }

    /// Previous, Play and Next share one glass capsule, centred; the speaker
    /// has its own circle on the left and the track menu one on the right.
    /// All three are the same height.
    private var transport: some View {
        // Each button is as tall as the capsule, so its hover fills it and
        // the end ones follow the capsule's rounding.
        HStack(spacing: Theme.Space.xxs) {
            TransportButton(symbol: "backward.fill", label: "Previous", target: Theme.Size.transportBar) { player.previous() }
            TransportButton(symbol: player.state.isPlaying ? "pause.fill" : "play.fill",
                            label: player.state.isPlaying ? "Pause" : "Play",
                            glyph: Theme.Size.playGlyph, target: Theme.Size.transportBar) { player.togglePlayPause() }
            TransportButton(symbol: "forward.fill", label: "Next", target: Theme.Size.transportBar) { player.next() }
                .disabled(!player.state.hasNext)
        }
        .frame(height: Theme.Size.transportBar)
        .glass(in: Capsule())
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) { volumeButton }
        .overlay(alignment: .trailing) { trackMenu }
    }

    /// What can be done with the track itself. One thing so far.
    private var trackMenu: some View {
        Menu {
            Button { player.toggleLike() } label: {
                Label(player.state.isLiked ? "Remove Like" : "Like",
                      systemImage: player.state.isLiked ? "heart.slash" : "heart")
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(player.state.isAd)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: Theme.Size.transportGlyph, weight: .semibold))
                .foregroundStyle(Theme.Colors.text)
                .frame(width: Theme.Size.transportBar, height: Theme.Size.transportBar)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(PressableStyle())
        .menuIndicator(.hidden)
        .glass(in: Circle())
        .help("More")
        .accessibilityLabel("More")
    }

    /// The speaker opens a small vertical slider above it, as in YouTube Music.
    private var volumeButton: some View {
        TransportButton(symbol: volumeSymbol, label: "Volume", target: Theme.Size.transportBar) {
            // Not a toggle: a click while the popover is open already closes
            // it, and toggling would open it again.
            showsVolume = true
        }
        .glass(in: Circle())
        .help("Volume: \(Int(player.volume))%")
        .accessibilityValue("\(Int(player.volume)) percent")
        .popover(isPresented: $showsVolume, arrowEdge: .top) {
            VStack(spacing: Theme.Space.xs) {
                TransportButton(symbol: volumeSymbol, label: player.volume > 0 ? "Mute" : "Unmute") {
                    player.toggleMute()
                }
                VerticalSlider(value: $player.volume, range: 0...100)
                    .frame(width: Theme.Size.volumeGlyph, height: Theme.Size.volumeSlider)
                    .accessibilityLabel("Volume")
                    .accessibilityValue("\(Int(player.volume)) percent")
            }
            .padding(Theme.Space.s)
        }
    }

    private var volumeSymbol: String {
        switch player.volume {
        case ..<1: return "speaker.slash.fill"
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    /// SwiftUI's Slider is horizontal only on macOS; AppKit's is vertical when
    /// it is taller than wide. Its fill is the accent, fainter the quieter it
    /// plays, so the level reads at a glance.
    private struct VerticalSlider: NSViewRepresentable {
        @Binding var value: Double
        let range: ClosedRange<Double>

        func makeNSView(context: Context) -> NSSlider {
            let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                                  target: context.coordinator, action: #selector(Coordinator.changed(_:)))
            slider.isVertical = true
            slider.isContinuous = true
            slider.controlSize = .small
            Self.fill(slider)
            return slider
        }

        func updateNSView(_ slider: NSSlider, context: Context) {
            context.coordinator.parent = self
            if slider.doubleValue != value { slider.doubleValue = value }
            Self.fill(slider)
        }

        static func fill(_ slider: NSSlider) {
            let span = slider.maxValue - slider.minValue
            let level = span > 0 ? (slider.doubleValue - slider.minValue) / span : 1
            let floor = Theme.Opacity.volumeFloor
            slider.trackFillColor = NSColor(Theme.Colors.accent).withAlphaComponent(floor + (1 - floor) * level) // tokens-ok: the accent token, for AppKit
        }

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        final class Coordinator: NSObject {
            var parent: VerticalSlider
            init(_ parent: VerticalSlider) { self.parent = parent }
            @objc func changed(_ slider: NSSlider) {
                parent.value = slider.doubleValue
                VerticalSlider.fill(slider)
            }
        }
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// How far down the window the artwork's colour reaches, reported by the
/// Now Playing page.
struct TintBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// An icon-only button in `text`, with a square click target.
struct TransportButton: View {
    let symbol: String
    let label: String
    var glyph: CGFloat = Theme.Size.transportGlyph
    /// The round glass buttons pass their full size, so the hover fills them.
    var target: CGFloat = Theme.Size.transportTarget
    var color: Color = Theme.Colors.text
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: target, height: target)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Feedback for icon buttons: a soft capsule in the text colour under the
/// pointer, and a short dip in opacity while pressed. It fills the button's
/// frame: a circle on square buttons and the round glass ones, the shape of
/// the page pill on the page tabs.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration)
    }

    private struct HoverLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background {
                    Capsule()
                        .fill(Theme.Colors.text.opacity(Theme.Opacity.hover))
                        .padding(Theme.Size.hoverInset)
                        .opacity(hovering && isEnabled ? 1 : 0)
                }
                .opacity(configuration.isPressed ? Theme.Opacity.pressed : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
                .animation(.easeOut(duration: Theme.Motion.feedback), value: configuration.isPressed)
        }
    }
}

/// Large artwork as the sleeve, with the record out of it on the right while
/// music plays and inside it while paused. Both move, so the pair stays
/// centred. All of it is Core Animation (see SleeveAndRecord).
/// Grows into whatever height the page leaves, keeping the sleeve square
/// and the record's peek in proportion. `artworkLarge` is the smallest size.
struct ArtworkWithRecord: View {
    let url: URL?
    let spinning: Bool

    var body: some View {
        SleeveAndRecord(url: url, spinning: spinning)
            .aspectRatio((Theme.Size.artworkLarge + Theme.Size.recordPeek) / Theme.Size.artworkLarge, contentMode: .fit)
            .padding(Theme.Space.s) // a little smaller than the zone it sets
            .frame(maxWidth: .infinity, minHeight: Theme.Size.artworkLarge, maxHeight: .infinity)
            .padding(.horizontal, Theme.Space.m)
            .accessibilityHidden(true)
    }
}

/// CUSTOM: the vinyl record, the app's one piece of custom drawing. Grooves
/// in faint cream, an orange label with a hole, as on the icon. The turning
/// is done by `Spinning`, on the compositor.
struct Record: View {
    let size: CGFloat
    let spinning: Bool

    var body: some View {
        Spinning(spinning: spinning, period: Theme.Motion.recordTurn) {
            RecordDisc(size: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The still drawing of the record, at a given size.
struct RecordDisc: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.record)
            // Grooves only where they can be seen: none at row size.
            if size >= Theme.Size.artworkLarge / 2 {
                ForEach(1..<9) { ring in
                    Circle()
                        .strokeBorder(Theme.Colors.recordGroove.opacity(Theme.Opacity.groove), lineWidth: 1)
                        .padding(size * CGFloat(ring) * Theme.Size.recordGrooveStep)
                }
            }
            // A soft light across the surface, as on real vinyl. The disc is
            // otherwise symmetrical, and its turning would be invisible.
            if size >= Theme.Size.artworkLarge / 2 {
                Circle()
                    .fill(AngularGradient(stops: [
                        .init(color: .clear, location: 0), // tokens-ok: transparency, not a colour
                        .init(color: Theme.Colors.recordGroove.opacity(Theme.Opacity.sheen), location: 0.12),
                        .init(color: .clear, location: 0.26),
                        .init(color: .clear, location: 0.5),
                        .init(color: Theme.Colors.recordGroove.opacity(Theme.Opacity.sheen / 2), location: 0.62),
                        .init(color: .clear, location: 0.74),
                        .init(color: .clear, location: 1),
                    ], center: .center))
            }
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: size * Theme.Size.recordLabelRatio, height: size * Theme.Size.recordLabelRatio)
            Circle()
                .fill(Theme.Colors.accentOn)
                .frame(width: size * Theme.Size.recordHoleRatio, height: size * Theme.Size.recordHoleRatio)
        }
        .frame(width: size, height: size)
    }
}

/// The current track's lyrics, in a popover from the Lyrics button. Plain
/// text as YouTube Music's web client has it, with its source; fetched when
/// opened, and again when the track changes while it is open.
struct LyricsPanel: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            VStack(alignment: .leading, spacing: 0) {
                Text(player.state.title.isEmpty ? "Lyrics" : player.state.title)
                    .font(Theme.Text.label)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                if !player.state.artist.isEmpty {
                    Text(player.state.artist)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(Theme.Space.m)
        .frame(width: Theme.Size.editorWidth, height: Theme.Size.lyricsHeight)
        .task(id: player.state.videoID) { player.loadLyrics() }
    }

    @ViewBuilder
    private var content: some View {
        if player.state.isAd {
            note("No lyrics during an ad.")
        } else {
            switch player.lyricsState {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let reason):
                note(reason)
            case .loaded:
                if let lyrics = player.lyrics, !lyrics.text.isEmpty {
                    ScrollView {
                        Text(lyrics.text)
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.text)
                            .lineSpacing(Theme.Space.xxs)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !lyrics.source.isEmpty {
                            Text(lyrics.source)
                                .font(Theme.Text.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Theme.Space.s)
                        }
                    }
                    .scrollIndicators(.never)
                } else {
                    note("No lyrics for this track.")
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Text.caption)
            .foregroundStyle(Theme.Colors.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
