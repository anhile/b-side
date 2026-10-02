import SwiftUI

/// One job: start music for how I feel right now, in one click.
struct VibePage: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.footerRoom) private var footerRoom

    /// The tile being edited, or a new one.
    @State private var editing: Mood?
    /// The New Vibe sheet: a new tile from words, or one made from words
    /// made again.
    @State private var describing: Describing?
    /// The tile being dragged to another place.
    @State private var dragged: Mood.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Describing: Identifiable {
        let id = UUID()
        var replacing: Mood?
    }

    private let columns = [
        GridItem(.fixed(Theme.Size.tileWidth), spacing: Theme.Space.s),
        GridItem(.fixed(Theme.Size.tileWidth), spacing: Theme.Space.s),
    ]

    private func move(_ mood: Mood, by step: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: Theme.Motion.page)) { player.move(mood, by: step) }
    }

    var body: some View {
        if let blocked = blockingState(for: player) {
            blocked
                .padding(.bottom, footerRoom)
        } else if player.account == .unknown {
            SkeletonList()
                .padding(.top, Theme.Space.s)
                .padding(.bottom, footerRoom)
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(player.moods) { mood in
                    let locked = mood.needsAccount && player.account == .signedOut
                    let play = { locked ? player.showSignIn() : player.play(mood) }
                    // A click plays, a drag moves the tile: not a Button,
                    // which would keep the mouse and never let a drag start.
                    MoodTile(mood: mood, subtitle: locked ? "Sign in to play" : mood.subtitle(playlists: player.playlists),
                             isCurrent: player.source == .mood(mood.id), isPlaying: player.state.isPlaying)
                        .modifier(TileLift())
                        .onTapGesture(perform: play)
                        .onDrag {
                            dragged = mood.id
                            return NSItemProvider(object: mood.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: TileDrop(target: mood.id, dragged: $dragged) { id in
                            withAnimation(reduceMotion ? nil : .snappy(duration: Theme.Motion.page)) {
                                player.move(id, toPlaceOf: mood.id)
                            }
                        })
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, play)
                        .help(mood.name)
                        .contextMenu {
                            Button("Edit…") {
                                if case .described = mood.source { describing = Describing(replacing: mood) } else { editing = mood }
                            }
                            Divider()
                            Button("Move Earlier") { move(mood, by: -1) }
                                .disabled(mood.id == player.moods.first?.id)
                            Button("Move Later") { move(mood, by: 1) }
                                .disabled(mood.id == player.moods.last?.id)
                            Divider()
                            Button("Remove", role: .destructive) { player.remove(mood) }
                        }
                }
                Button {
                    describing = Describing()
                } label: {
                    AddTile(isFirst: player.moods.isEmpty)
                }
                .buttonStyle(TileButtonStyle())
                .help("Add a vibe")
                .accessibilityLabel("Add a vibe")
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m) // air under the title bar
            .padding(.bottom, Theme.Space.xs)
            .background(OverlayScrollers())
        }
        .contentMargins(.bottom, footerRoom, for: .scrollContent)
        .contentMargins(.bottom, footerRoom, for: .scrollIndicators)
        // A drop between the tiles ends the drag too.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            defer { dragged = nil }
            return dragged != nil
        }
        .sheet(item: $describing) { describing in
            NewVibeSheet(replacing: describing.replacing) {
                // After this sheet is gone: one sheet at a time.
                DispatchQueue.main.async { editing = Mood(name: "", source: .likedShuffled) }
            }
        }
        .sheet(item: $editing) { mood in
            MoodEditor(mood: mood, playlists: player.playlists) { saved in
                player.save(saved)
            }
        }
    }
}

/// Moves the dragged tile to the place of the tile it is over, as it gets
/// there, so the others make room before the drop.
private struct TileDrop: DropDelegate {
    let target: Mood.ID
    @Binding var dragged: Mood.ID?
    let move: (Mood.ID) -> Void

    func dropEntered(info: DropInfo) {
        if let dragged, dragged != target { move(dragged) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: dragged == nil ? .cancel : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragged = nil }
        return dragged != nil
    }
}

/// A mood: a gradient of its own colour (VibePalette), the name and what it
/// plays in white in the deep corner, the kind of source in the other, and
/// the same symbol large and faded, half off the edge. A glass edge on top.
/// The playing tile has a white ring and a pulsing speaker.
struct MoodTile: View {
    let mood: Mood
    let subtitle: String
    let isCurrent: Bool
    let isPlaying: Bool
    @Environment(\.pageShown) private var pageShown
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.m) }

    var body: some View {
        let swatch = VibePalette.swatch(for: mood)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack {
                Spacer()
                Group {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .symbolEffect(.variableColor.iterative, isActive: isPlaying && pageShown) // tokens-ok: an effect, not a colour
                            .accessibilityLabel(isPlaying ? "Playing" : "Paused")
                    } else {
                        Image(systemName: mood.symbol)
                            .accessibilityHidden(true)
                    }
                }
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.onVibe)
            }
            Spacer(minLength: 0)
            Text(mood.name)
                .font(Theme.Text.title)
                .foregroundStyle(Theme.Colors.onVibe)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.onVibe.opacity(Theme.Opacity.vibeSubtitle))
                .lineLimit(1)
        }
        .padding(Theme.Space.s)
        .frame(width: Theme.Size.tileWidth, height: Theme.Size.tileHeight, alignment: .bottomLeading)
        .background { background(swatch) }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [Theme.Colors.onVibe.opacity(Theme.Opacity.vibeEdgeTop),
                                                       Theme.Colors.onVibe.opacity(Theme.Opacity.vibeEdgeBottom)],
                                              startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            // The playing tile's ring, in its own colour, a little outside
            // it: the deep shade on the light page, the light one on the dark.
            RoundedRectangle(cornerRadius: Theme.Radius.m + Theme.Size.currentRing * 1.5)
                .strokeBorder(colorScheme == .dark ? swatch.light : swatch.deep, lineWidth: Theme.Size.currentRing)
                .padding(-Theme.Size.currentRing * 1.5)
                .opacity(isCurrent ? 1 : 0)
        }
        .shadow(color: swatch.deep.opacity(Theme.Opacity.vibeShadow), radius: Theme.Size.vibeShadow,
                y: Theme.Size.vibeShadow / 2)
        .contentShape(shape)
    }

    /// Light corner top right, deep corner bottom left under the name, a
    /// glow in the light corner, the faded symbol, and a shade under the text.
    private func background(_ swatch: VibePalette.Swatch) -> some View {
        ZStack {
            LinearGradient(colors: [swatch.light, swatch.deep], startPoint: .topTrailing, endPoint: .bottomLeading)
            Circle()
                .fill(swatch.light)
                .frame(width: Theme.Size.vibeGlow, height: Theme.Size.vibeGlow)
                .blur(radius: Theme.Size.vibeGlow / 3)
                .opacity(Theme.Opacity.vibeGlow)
                .offset(x: Theme.Size.vibeGlow / 2, y: -Theme.Size.vibeGlow / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            Image(systemName: mood.symbol)
                .font(.system(size: Theme.Size.vibeMark))
                .foregroundStyle(Theme.Colors.onVibe.opacity(Theme.Opacity.vibeMark))
                .rotationEffect(.degrees(-14))
                .offset(x: Theme.Size.vibeMark / 4, y: Theme.Size.vibeMark / 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            LinearGradient(colors: [.clear, Theme.Colors.shadow.opacity(Theme.Opacity.vibeShade)],
                           startPoint: .center, endPoint: .bottom)
        }
    }
}

/// The last tile: a plus in a dashed outline. When it is the only tile it
/// says what to do.
struct AddTile: View {
    let isFirst: Bool

    var body: some View {
        VStack(spacing: Theme.Space.xxs) {
            Image(systemName: "plus")
                .font(Theme.Text.title)
                .foregroundStyle(Theme.Colors.textMuted)
            if isFirst {
                Text("Add a vibe")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .frame(width: Theme.Size.tileWidth, height: Theme.Size.tileHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .strokeBorder(Theme.Colors.border, style: StrokeStyle(lineWidth: 1, dash: [Theme.Space.xxs]))
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
    }
}

/// A tile that is not a button rises under the pointer the same way.
struct TileLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(!reduceMotion && hovering ? Theme.Motion.tileHover : 1)
            .onHover { hovering = $0 }
            .pointingHand()
            .animation(.snappy(duration: Theme.Motion.feedback * 2), value: hovering)
    }
}

/// Tiles rise a little under the pointer and dip when pressed, on a spring.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Lifted(configuration: configuration)
    }

    private struct Lifted: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? Theme.Motion.tilePress
                             : hovering ? Theme.Motion.tileHover : 1)
                .opacity(reduceMotion && configuration.isPressed ? Theme.Opacity.pressed : 1)
                .onHover { hovering = $0 }
                .pointingHand(isEnabled)
                .animation(.snappy(duration: Theme.Motion.feedback * 2), value: hovering)
                .animation(.snappy(duration: Theme.Motion.feedback), value: configuration.isPressed)
        }
    }
}

/// The sheet that names a tile and picks what it plays. System controls, as
/// in Settings.
struct MoodEditor: View {
    @Environment(\.dismiss) private var dismiss

    private enum Kind: String, CaseIterable, Identifiable {
        case liked = "Liked Music, shuffled"
        case playlist = "A playlist"
        case radio = "Radio from a track"
        var id: String { rawValue }
    }

    let playlists: [Playlist]
    let save: (Mood) -> Void

    @State private var mood: Mood
    @State private var kind: Kind
    @State private var playlistID: String
    @State private var shuffled: Bool
    @State private var track: String

    init(mood: Mood, playlists: [Playlist], save: @escaping (Mood) -> Void) {
        self.playlists = playlists
        self.save = save
        _mood = State(initialValue: mood)
        switch mood.source {
        case .likedShuffled:
            _kind = State(initialValue: .liked)
            _playlistID = State(initialValue: playlists.first?.id ?? Tuning.likedMusicID)
            _shuffled = State(initialValue: true)
            _track = State(initialValue: "")
        case .playlist(let id, let isShuffled):
            _kind = State(initialValue: .playlist)
            _playlistID = State(initialValue: id)
            _shuffled = State(initialValue: isShuffled)
            _track = State(initialValue: "")
        case .radio(let videoID):
            _kind = State(initialValue: .radio)
            _playlistID = State(initialValue: playlists.first?.id ?? Tuning.likedMusicID)
            _shuffled = State(initialValue: false)
            _track = State(initialValue: videoID)
        case .described(_, let anchors):
            // Edited in NewVibeSheet; here only as a track's radio.
            _kind = State(initialValue: .radio)
            _playlistID = State(initialValue: playlists.first?.id ?? Tuning.likedMusicID)
            _shuffled = State(initialValue: false)
            _track = State(initialValue: anchors.first ?? "")
        }
    }

    private var isNew: Bool { mood.name.isEmpty && mood.id != Mood.liked.id }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $mood.name, prompt: Text("Late night"))
                LabeledContent("Colour") {
                    HStack(spacing: Theme.Space.xs) {
                        ForEach(VibePalette.swatches.indices, id: \.self) { index in
                            swatchButton(index)
                        }
                    }
                }
                Picker("Plays", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                switch kind {
                case .liked:
                    EmptyView()
                case .playlist:
                    Picker("Playlist", selection: $playlistID) {
                        Text("Liked Music").tag(Tuning.likedMusicID)
                        ForEach(playlists.filter { $0.id != Tuning.likedMusicID }) { Text($0.title).tag($0.id) }
                    }
                    Toggle("Shuffle", isOn: $shuffled)
                case .radio:
                    TextField("Track", text: $track, prompt: Text("Video ID or YouTube Music link"))
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    save(result)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(Theme.Space.m)
        }
        .frame(width: Theme.Size.editorWidth)
    }

    private func swatchButton(_ index: Int) -> some View {
        let swatch = VibePalette.swatches[index]
        let isChosen = VibePalette.index(for: mood) == index
        return Button { mood.colour = index } label: {
            Circle()
                .fill(LinearGradient(colors: [swatch.light, swatch.deep], startPoint: .topTrailing, endPoint: .bottomLeading))
                .frame(width: Theme.Size.swatch, height: Theme.Size.swatch)
                .padding(Theme.Size.currentRing * 1.5)
                .overlay { Circle().strokeBorder(Theme.Colors.text, lineWidth: Theme.Size.currentRing).opacity(isChosen ? 1 : 0) }
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(swatch.name)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var source: Mood.Source? {
        switch kind {
        case .liked: return .likedShuffled
        case .playlist: return .playlist(id: playlistID, shuffled: shuffled)
        case .radio: return PlayTarget(track)?.videoID.map { .radio(videoID: $0) }
        }
    }

    private var isValid: Bool {
        !mood.name.trimmingCharacters(in: .whitespaces).isEmpty && source != nil
    }

    private var result: Mood {
        var saved = mood
        saved.name = mood.name.trimmingCharacters(in: .whitespaces)
        saved.source = source ?? .likedShuffled
        return saved
    }
}
