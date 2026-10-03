import SwiftUI

/// The sheet that names a tile and picks what it plays. System controls, as
/// in Settings.
struct MoodEditor: View {
    @Environment(\.dismiss) private var dismiss

    /// Liked Music is one of the playlists (since 2026-10-03; before, a
    /// kind of its own, which said the same thing twice).
    private enum Kind: String, CaseIterable, Identifiable {
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
            _kind = State(initialValue: .playlist)
            _playlistID = State(initialValue: Tuning.likedMusicID)
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
        // Liked Music shuffled keeps its own source: the default tile's.
        case .playlist where playlistID == Tuning.likedMusicID && shuffled: return .likedShuffled
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
