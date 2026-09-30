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
            Spacer(minLength: Theme.Space.m)
            ArtworkWithRecord(url: player.state.artworkURL, spinning: player.state.isPlaying)
            Spacer(minLength: Theme.Space.l)
                // Where the artwork's colour ends: just above the title.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("window")).midY } action: { tintBottom = $0 }
                .preference(key: TintBottomKey.self, value: tintBottom)
            VStack(spacing: Theme.Space.xxs) {
                Text(title)
                    .font(Theme.Text.title)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .help(title)
                Text(subtitle)
                    .font(Theme.Text.caption)
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
                .padding(.bottom, Theme.Space.xs)
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

    private var nothingPlaying: some View {
        VStack(spacing: Theme.Space.xs) {
            Spacer()
            Record(size: Theme.Size.artworkLarge, spinning: false)
                .padding(.bottom, Theme.Space.m)
            Text("Nothing playing")
                .font(Theme.Text.title)
                .foregroundStyle(Theme.Colors.text)
            Text("Pick a mood or a playlist.")
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
            HStack(spacing: Theme.Space.xs) {
                Button("Play Vibe") { player.playVibe() }
                    .buttonStyle(FilledButtonStyle())
                    .disabled(!player.account.isSignedIn)
                Button("Choose a Playlist") { navigation.page = .playlists }
                    .buttonStyle(OutlineButtonStyle())
            }
            .padding(.top, Theme.Space.xs)
            Spacer()
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

    /// Previous, Play and Next share one glass capsule; the speaker has its
    /// own circle on the left. The capsule is centred in the page.
    private var transport: some View {
        HStack(spacing: Theme.Space.m) {
            TransportButton(symbol: "backward.fill", label: "Previous") { player.previous() }
            TransportButton(symbol: player.state.isPlaying ? "pause.fill" : "play.fill",
                            label: player.state.isPlaying ? "Pause" : "Play",
                            glyph: Theme.Size.playGlyph) { player.togglePlayPause() }
            TransportButton(symbol: "forward.fill", label: "Next") { player.next() }
                .disabled(!player.state.hasNext)
        }
        .padding(.horizontal, Theme.Space.xs)
        .padding(.vertical, Theme.Space.xxs)
        .glass(in: Capsule())
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) { volumeButton }
    }

    /// The speaker opens a small vertical slider above it, as in YouTube Music.
    private var volumeButton: some View {
        TransportButton(symbol: volumeSymbol, label: "Volume") {
            // Not a toggle: a click while the popover is open already closes
            // it, and toggling would open it again.
            showsVolume = true
        }
        .padding(Theme.Space.xxs)
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
    /// it is taller than wide.
    private struct VerticalSlider: NSViewRepresentable {
        @Binding var value: Double
        let range: ClosedRange<Double>

        func makeNSView(context: Context) -> NSSlider {
            let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                                  target: context.coordinator, action: #selector(Coordinator.changed(_:)))
            slider.isVertical = true
            slider.isContinuous = true
            slider.controlSize = .small
            return slider
        }

        func updateNSView(_ slider: NSSlider, context: Context) {
            context.coordinator.parent = self
            if slider.doubleValue != value { slider.doubleValue = value }
        }

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        final class Coordinator: NSObject {
            var parent: VerticalSlider
            init(_ parent: VerticalSlider) { self.parent = parent }
            @objc func changed(_ slider: NSSlider) { parent.value = slider.doubleValue }
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
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Theme.Colors.text)
                .frame(width: Theme.Size.transportTarget, height: Theme.Size.transportTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Feedback for icon buttons: a short dip in opacity while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? Theme.Opacity.pressed : 1)
            .animation(.easeOut(duration: Theme.Motion.feedback), value: configuration.isPressed)
    }
}

/// Large artwork as the sleeve, with the record out of it on the right while
/// music plays and inside it while paused. Both move, so the pair stays
/// centred. All of it is Core Animation (see SleeveAndRecord).
struct ArtworkWithRecord: View {
    let url: URL?
    let spinning: Bool

    var body: some View {
        SleeveAndRecord(url: url, spinning: spinning)
            .frame(width: Theme.Size.artworkLarge + Theme.Size.recordPeek, height: Theme.Size.artworkLarge)
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
