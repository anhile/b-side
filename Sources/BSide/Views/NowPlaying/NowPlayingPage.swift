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
    @ObservedObject private var outputs = AudioOutputs.shared

    var body: some View {
        if let blocked = blockingState(for: player) {
            blocked
        } else if player.hasTrack || player.isLoading {
            content
        } else {
            nothingPlaying
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            artworkZone
                .layoutPriority(1) // the record takes the free height, not the gaps
            // The title as far below the colour's edge as the artist is
            // above the progress line (the bar's frame reaches 8 past it).
            Spacer(minLength: Theme.Space.l)
            // The track's name from the left edge, and what can be done
            // with the track after it: Like and the menu, always in view.
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    MarqueeText(text: title, font: Theme.Text.title, color: Theme.Colors.text)
                        .help(title)
                    if player.state.isAd, player.state.adLeft >= 0 {
                        AdCountdown(font: Theme.Text.body)
                    } else if player.showsBuffering {
                        Text("Buffering…")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.textMuted)
                    } else if player.state.artistID.isEmpty || player.state.isAd {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                likeButton
                trackMenu
            }
            .padding(.leading, Theme.Space.m)
            // The menu's dots sit over the middle of the Up Next circle.
            .padding(.trailing, Theme.Space.m + (Theme.Size.transportBar - Theme.Size.transportTarget) / 2)
            // s to the bar's frame, which reaches 8 past the line: as far
            // from the artist to the line as from the colour to the title.
            Spacer(minLength: Theme.Space.s)
            progress
                .padding(.horizontal, Theme.Space.m)
            Spacer(minLength: Theme.Space.m)
            transport
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.m) // as far from the bottom as from the sides
        }
    }

    /// Opens the list of what plays next in the artwork's place, and closes
    /// it; orange while it shows. Its circle mirrors the speaker's.
    private var queueButton: some View {
        TransportButton(symbol: "list.bullet", label: showsQueue ? "Hide Up Next" : "Up Next",
                        target: Theme.Size.transportBar,
                        color: showsQueue ? Theme.Colors.accentText : Theme.Colors.text) {
            navigation.showsQueue.toggle()
        }
        .disabled(player.state.isAd)
        .glass(in: Circle())
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

    /// The zone the artwork's colour fills: from the top of the page to just
    /// under the artwork. While the pointer is over it, a dark veil covers
    /// all of it, with Lyrics and Repeat in the middle. Lyrics take the
    /// artwork's place, in the same frame, so nothing else moves.
    private var artworkZone: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.m)
            ArtworkWithRecord(url: player.state.artworkURL, spinning: player.state.isPlaying && pageShown)
                .opacity(showsLyrics || showsQueue ? 0 : 1)
        }
        .overlay {
            if showsQueue {
                UpNextList()
                    .clipped() // at the title bar's edge
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Theme.Motion.page), value: showsQueue)
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
        !showsLyrics && !showsQueue && (hoveringArtwork || previewArtworkHover)
    }

    private var showsLyrics: Bool { navigation.showsLyrics }
    private var showsQueue: Bool { navigation.showsQueue && !player.state.isAd }

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
    /// has its own circle on the left and Up Next one on the right.
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
        .overlay(alignment: .trailing) { queueButton }
    }

    /// The menu every track has, with Lyrics, Up Next and Repeat in it. No
    /// Like: the heart is next to it, and Command-L is in the Playback menu.
    private var trackMenu: some View {
        Menu {
            TrackMenu(videoID: player.state.isAd ? "" : player.state.videoID, title: player.state.title,
                      artist: player.state.artist,
                      artistID: player.state.artistID, albumID: player.state.albumID, showsLike: false) {
                // A track without lyrics has no Lyrics item at all.
                if showsLyrics || player.lyricsAvailable == true {
                    Button { navigation.showsLyrics.toggle() } label: {
                        Label(showsLyrics ? "Hide Lyrics" : "Show Lyrics", systemImage: "quote.bubble")
                    }
                }
                Button { navigation.showsQueue.toggle() } label: {
                    Label(showsQueue ? "Hide Up Next" : "Show Up Next", systemImage: "list.bullet")
                }
                Picker(selection: $player.repeatMode) {
                    ForEach(RepeatMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Repeat", systemImage: player.repeatMode.symbol)
                }
                .pickerStyle(.menu)
                soundOutput
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: Theme.Size.transportGlyph, weight: .semibold))
                .foregroundStyle(Theme.Colors.textMuted)
                .frame(width: Theme.Size.transportTarget, height: Theme.Size.transportTarget)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(PressableStyle())
        .menuIndicator(.hidden)
        .pointingHand()
        .help("More")
        .accessibilityLabel("More")
    }

    /// Where the Mac's sound goes: the outputs it has, the one in use
    /// checked, then the paired Bluetooth devices that are not connected.
    private var soundOutput: some View {
        Menu {
            ForEach(outputs.devices) { device in
                Toggle(isOn: Binding(get: { device.id == outputs.current }, set: { _ in outputs.select(device) })) {
                    Label(device.name, systemImage: device.symbol)
                }
            }
            .onAppear { outputs.refreshPaired() }
            Divider()
            if outputs.showsBluetooth {
                ForEach(outputs.paired) { device in
                    Button { outputs.connect(device) } label: {
                        Label("Connect \(device.name)", systemImage: "headphones")
                    }
                }
            } else {
                Button { outputs.showBluetooth() } label: {
                    Label("Show Bluetooth Devices", systemImage: "dot.radiowaves.left.and.right")
                }
            }
        } label: {
            Label("Sound Output", systemImage: "hifispeaker.2")
        }
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
