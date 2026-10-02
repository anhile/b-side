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
    @Environment(\.previewArtworkHover) private var previewArtworkHover
    @Environment(\.pageShown) private var pageShown

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
            // Like stands at the end of the title, always in view; as much
            // room is kept free at the start, so the title stays centred.
            HStack(spacing: Theme.Space.xxs) {
                Spacer(minLength: 0).frame(width: Theme.Size.transportTarget)
                VStack(spacing: Theme.Space.xxs) {
                    Text(title)
                        .font(Theme.Text.title)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                        .help(title)
                    if player.state.artistID.isEmpty || player.state.isAd {
                        Text(subtitle)
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .lineLimit(1)
                            .help(subtitle)
                    } else {
                        // The artist's page on Explore; Back there returns here.
                        Button { navigation.open(.artist(id: player.state.artistID, name: subtitle)) } label: {
                            LinkText(text: subtitle)
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help("Show \(subtitle)")
                    }
                }
                .frame(maxWidth: .infinity)
                likeButton
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

    /// Orange and filled once liked. An ad cannot be liked: the button
    /// keeps its place and goes away.
    private var likeButton: some View {
        TransportButton(symbol: player.state.isLiked ? "heart.fill" : "heart",
                        label: player.state.isLiked ? "Remove Like" : "Like",
                        color: player.state.isLiked ? Theme.Colors.accentText : Theme.Colors.textMuted) {
            player.toggleLike()
        }
        .opacity(player.state.isAd ? 0 : 1)
        .disabled(player.state.isAd)
    }

    /// The zone the artwork's colour fills: from the top of the page to half
    /// way to the title. While the pointer is over it, a dark veil covers all
    /// of it, with Lyrics and Repeat in the middle. Lyrics take the artwork's
    /// place, in the same frame, so nothing else moves.
    private var artworkZone: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.m)
            ArtworkWithRecord(url: player.state.artworkURL, spinning: player.state.isPlaying && pageShown)
                .opacity(showsLyrics ? 0 : 1)
            Spacer(minLength: Theme.Space.s)
        }
        // The whole zone, so the lines scroll out under the title bar's edge
        // rather than being cut in the middle of the colour.
        .overlay {
            if showsLyrics {
                LyricsView()
                    .padding(.horizontal, Theme.Space.m)
                    .clipped() // at the title bar's edge
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsLyrics {
                TransportButton(symbol: "quote.bubble.fill", label: "Hide Lyrics") {
                    navigation.showsLyrics = false
                }
                .glass(in: Circle())
                .padding(.top, Theme.Space.xs)
                .padding(.trailing, Theme.Space.m)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Theme.Motion.page), value: showsLyrics)
        // The next track has none: back to the record.
        .onChange(of: player.lyricsAvailable) {
            if showsLyrics, player.lyricsAvailable == false { navigation.showsLyrics = false }
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
        !showsLyrics && (hoveringArtwork || previewArtworkHover)
    }

    private var showsLyrics: Bool { navigation.showsLyrics }

    private var artworkActions: some View {
        HStack(spacing: Theme.Space.s) {
            if player.lyricsAvailable == true {
                TransportButton(symbol: "quote.bubble", label: "Lyrics",
                                glyph: Theme.Size.playGlyph, target: Theme.Size.artworkAction) {
                    navigation.showsLyrics = true
                }
                .glass(in: Circle())
            }
            // Off, All, One in turn; orange while on.
            TransportButton(symbol: player.repeatMode.symbol, label: "Repeat: \(player.repeatMode.title)",
                            glyph: Theme.Size.playGlyph, target: Theme.Size.artworkAction,
                            color: player.repeatMode == .off ? Theme.Colors.text : Theme.Colors.accent) {
                player.repeatMode = player.repeatMode.next
            }
            .glass(in: Circle())
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
        TimelineView(PlaybackSeconds(clock: player.clock)) { context in
            let duration = player.state.duration
            let position = scrub ?? min(player.position(at: context.date), max(duration, 0))
            ProgressBar(position: position, duration: duration, time: time,
                        onScrub: { scrub = $0 },
                        onCommit: { target in
                            player.seek(to: target)
                            scrub = nil
                        })
                .disabled(duration <= 0 || player.state.isAd)
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

    /// What can be done with the track itself: Like with its shortcut, then
    /// the menu every track has, with Lyrics and Repeat in it.
    private var trackMenu: some View {
        Menu {
            Button { player.toggleLike() } label: {
                Label(player.state.isLiked ? "Remove Like" : "Like",
                      systemImage: player.state.isLiked ? "heart.slash" : "heart")
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(player.state.isAd)
            TrackMenu(videoID: player.state.isAd ? "" : player.state.videoID, artist: player.state.artist,
                      artistID: player.state.artistID, albumID: player.state.albumID, showsLike: false) {
                Button { navigation.showsLyrics.toggle() } label: {
                    Label(showsLyrics ? "Hide Lyrics" : "Show Lyrics", systemImage: "quote.bubble")
                }
                .disabled(!showsLyrics && player.lyricsAvailable != true)
                Picker(selection: $player.repeatMode) {
                    ForEach(RepeatMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Repeat", systemImage: player.repeatMode.symbol)
                }
                .pickerStyle(.menu)
            }
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
        .pointingHand()
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

    /// CUSTOM: the track's progress, in place of the system slider, which can
    /// neither change colour smoothly nor say where the pointer is. The
    /// filled part is a light orange; under the pointer it turns full orange,
    /// a thin tick marks where a click would go, and that time shows above
    /// it, clear of the pointer. Dragging scrubs; the seek happens on release.
    private struct ProgressBar: View {
        let position: Double
        let duration: Double
        let time: (Double) -> String
        let onScrub: (Double) -> Void
        let onCommit: (Double) -> Void

        @State private var pointer: CGFloat?
        @State private var dragging = false
        @Environment(\.isEnabled) private var isEnabled

        private var active: Bool { isEnabled && (pointer != nil || dragging) }

        var body: some View {
            let length = max(duration, 1)
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let knob = Theme.Size.progressKnob
                    let filled = width * CGFloat(min(max(position / length, 0), 1))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Colors.text.opacity(Theme.Opacity.progressTrack))
                        Capsule()
                            .fill(Theme.Colors.accent.opacity(active ? 1 : Theme.Opacity.progressRest))
                            .frame(width: max(filled, Theme.Size.progressLine))
                    }
                    .frame(height: Theme.Size.progressLine)
                    .overlay(alignment: .leading) {
                        // Where a click would go.
                        if isEnabled, !dragging, let pointer {
                            Capsule()
                                .fill(Theme.Colors.text)
                                .frame(width: Theme.Size.progressTick, height: Theme.Size.progressKnob.height)
                                .offset(x: min(max(pointer, 0), width) - Theme.Size.progressTick / 2)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Colors.knob)
                            .shadow(color: Theme.Colors.shadow.opacity(Theme.Opacity.groove), radius: 1, y: 0.5)
                            .frame(width: knob.width, height: knob.height)
                            .offset(x: min(max(filled - knob.width / 2, 0), width - knob.width))
                            .opacity(isEnabled ? 1 : 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .pointingHand(isEnabled)
                    .onContinuousHover { phase in
                        if case .active(let point) = phase { pointer = point.x } else { pointer = nil }
                    }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            dragging = true
                            pointer = drag.location.x
                            onScrub(seconds(at: drag.location.x, width: width))
                        }
                        .onEnded { drag in
                            dragging = false
                            onCommit(seconds(at: drag.location.x, width: width))
                        })
                }
                .frame(height: Theme.Size.progressTarget)
                .overlay { pointerTime }
                labels
            }
            .animation(.easeOut(duration: Theme.Motion.page), value: active)
            .accessibilityElement()
            .accessibilityLabel("Position")
            .accessibilityValue("\(time(position)) of \(time(duration))")
            .accessibilityAdjustableAction { direction in
                let step = Tuning.seekStep
                let target = direction == .increment ? position + step : position - step
                onCommit(min(max(target, 0), length))
            }
        }

        /// Elapsed on the left, the length on the right, and while the
        /// pointer is over the bar, the time under it.
        /// Elapsed on the left, the length on the right.
        private var labels: some View {
            HStack {
                Text(time(position))
                Spacer()
                Text(time(duration))
            }
            .font(Theme.Text.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.textMuted)
        }

        /// While the pointer is over the bar, the time under it, just above
        /// the line, where the pointer does not cover it.
        private var pointerTime: some View {
            GeometryReader { proxy in
                let width = proxy.size.width
                let half = Theme.Size.timeLabel / 2
                if active, let pointer {
                    Text(time(seconds(at: pointer, width: width)))
                        .font(Theme.Text.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.accentText)
                        .fixedSize()
                        .position(x: min(max(pointer, half), width - half), y: -Theme.Space.xxs)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }

        private func seconds(at x: CGFloat, width: CGFloat) -> Double {
            guard width > 0 else { return 0 }
            return Double(min(max(x / width, 0), 1)) * max(duration, 0)
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
                .pointingHand(isEnabled)
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
/// The lyrics in the artwork's place. Timed lines follow the playback: the
/// current one in `text`, the others muted, the view keeping it in the
/// middle; a click on a line plays from there. Plain text otherwise.
///
/// Nothing runs between lines: one wait until the next line starts, begun
/// again whenever the player reports (play, pause, seek, every 5 s).
struct LyricsView: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current: Int?
    @State private var height: CGFloat = 0

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The text first (usually here already), then the timings once
            // the text is in.
            .task(id: "\(player.state.videoID) \(player.lyrics?.videoID ?? "")") {
                player.loadLyrics()
                player.loadTimedLyrics()
            }
    }

    @ViewBuilder
    private var content: some View {
        if player.state.isAd {
            note("No lyrics during an ad.")
        } else if let lyrics = player.lyrics, lyrics.videoID == player.state.videoID, player.lyricsState == .loaded,
                  lyrics.isTimed || lyrics.timedTried {
            if lyrics.isTimed {
                timed(lyrics)
            } else if !lyrics.text.isEmpty {
                plain(lyrics)
            } else {
                note("No lyrics for this track.")
            }
        } else if case .failed(let reason) = player.lyricsState {
            note(reason)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func timed(_ lyrics: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(lyrics.lines.indices, id: \.self) { index in
                        Button { player.seek(to: lyrics.lines[index].start) } label: {
                            Text(lyrics.lines[index].text.isEmpty ? "♪" : lyrics.lines[index].text)
                                .font(Theme.Text.title)
                                .foregroundStyle(index == current ? Theme.Colors.text : Theme.Colors.textMuted)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .id(index)
                    }
                    source(lyrics)
                }
                // Half the height above and below, so the first and the last
                // line can come to the middle too.
                .padding(.top, max(Self.topRoom, height / 2))
                .padding(.bottom, height / 2)
            }
            .scrollIndicators(.never)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onChange(of: current) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: Theme.Motion.page)) {
                    proxy.scrollTo(current ?? 0, anchor: Self.readingLine)
                }
            }
            .onAppear {
                current = lyrics.lines.index(at: player.position(at: Date()))
                proxy.scrollTo(current ?? 0, anchor: Self.readingLine)
            }
        }
        .task(id: Follow(state: player.state, lines: lyrics.lines.count)) { await follow(lyrics.lines) }
    }

    /// The current line sits in the middle.
    private static let readingLine = UnitPoint(x: 0, y: 0.5)

    private struct Follow: Equatable {
        let state: PlayerState
        let lines: Int
    }

    private func follow(_ lines: [LyricLine]) async {
        while !Task.isCancelled {
            let position = player.position(at: Date())
            let index = lines.index(at: position)
            if index != current { current = index }
            guard player.state.isPlaying else { return }
            let next = (index ?? -1) + 1
            guard next < lines.count else { return }
            try? await Task.sleep(for: .seconds(max(lines[next].start - position, Theme.Motion.feedback)))
        }
    }

    private func plain(_ lyrics: Lyrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(lyrics.text)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.text)
                    .lineSpacing(Theme.Space.xxs)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                source(lyrics)
            }
            .padding(.top, Self.topRoom)
            .padding(.bottom, Theme.Space.m)
        }
        .scrollIndicators(.never)
    }

    /// Clear of the Hide Lyrics button at the top, while scrolled to the start.
    private static var topRoom: CGFloat { Theme.Space.xs + Theme.Size.transportTarget + Theme.Space.xs }

    @ViewBuilder
    private func source(_ lyrics: Lyrics) -> some View {
        if !lyrics.source.isEmpty {
            Text(lyrics.source)
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Space.s)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Text.caption)
            .foregroundStyle(Theme.Colors.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Text that opens a page: muted like the text around it, underlined and in
/// `text` under the pointer, with the pointing hand.
struct LinkText: View {
    let text: String
    var font = Theme.Text.body
    @State private var hovering = false

    var body: some View {
        Text(text)
            .font(font)
            .underline(hovering)
            .foregroundStyle(hovering ? Theme.Colors.text : Theme.Colors.textMuted)
            .lineLimit(1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .pointingHand()
    }
}
