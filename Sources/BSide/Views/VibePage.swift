import SwiftUI

/// One job: start music for how I feel right now, in one click.
struct VibePage: View {
    @EnvironmentObject private var player: PlayerController

    /// The tile being edited, or a new one.
    @State private var editing: Mood?

    private let columns = [
        GridItem(.fixed(Theme.Size.tileWidth), spacing: Theme.Space.s),
        GridItem(.fixed(Theme.Size.tileWidth), spacing: Theme.Space.s),
    ]

    var body: some View {
        if let blocked = blockingState(for: player) {
            blocked
        } else if player.account == .unknown {
            SkeletonList()
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(player.moods) { mood in
                    Button {
                        player.play(mood)
                    } label: {
                        MoodTile(mood: mood, subtitle: mood.subtitle(playlists: player.playlists),
                                 isCurrent: player.source == .mood(mood.id), isPlaying: player.state.isPlaying)
                    }
                    .buttonStyle(TileButtonStyle())
                    .help(mood.name)
                    .contextMenu {
                        Button("Edit…") { editing = mood }
                        Button("Remove", role: .destructive) { player.remove(mood) }
                    }
                }
                Button {
                    editing = Mood(name: "", source: .likedShuffled)
                } label: {
                    AddTile(isFirst: player.moods.isEmpty)
                }
                .buttonStyle(TileButtonStyle())
                .help("Add a mood")
                .accessibilityLabel("Add a mood")
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.xxs)
            .padding(.bottom, Theme.Space.xs)
        }
        .scrollIndicators(.automatic)
        .sheet(item: $editing) { mood in
            MoodEditor(mood: mood, playlists: player.playlists) { saved in
                player.save(saved)
            }
        }
    }
}

/// A mood: the name, what it plays, and the kind of source in the corner.
/// The playing tile carries the accent; nothing else does.
struct MoodTile: View {
    let mood: Mood
    let subtitle: String
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack {
                Spacer()
                if isCurrent {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.accentText)
                        .accessibilityLabel(isPlaying ? "Playing" : "Paused")
                } else {
                    Image(systemName: mood.symbol)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
            Text(mood.name)
                .font(Theme.Text.title)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .lineLimit(1)
        }
        .padding(Theme.Space.s)
        .frame(width: Theme.Size.tileWidth, height: Theme.Size.tileHeight, alignment: .bottomLeading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
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
                Text("Add a mood")
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

/// Tiles under the pointer get a `control-border` outline; pressed, they dip.
struct TileButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .strokeBorder(Theme.Colors.controlBorder)
                    .opacity(hovering ? 1 : 0)
            )
            .opacity(configuration.isPressed ? Theme.Opacity.pressed : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
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
        }
    }

    private var isNew: Bool { mood.name.isEmpty && mood.id != Mood.liked.id }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $mood.name, prompt: Text("Late night"))
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
