import SwiftUI

/// The preview step: the tile as it will look, what was understood, and the
/// first songs. Changing a part finds the first songs again.
struct VibePreview: View {
    let prompt: String
    let spec: VibeSpec
    let refinding: Bool
    let change: (VibeSpec) -> Void
    let tryIt: () -> Void

    private var edited: Binding<VibeSpec> {
        Binding(get: { spec }, set: change)
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    let mood = Mood(id: "preview", name: spec.name.isEmpty ? "Untitled" : spec.name,
                                    source: .described(prompt: prompt, anchors: []), colour: spec.colour,
                                    heardAs: Mood.heardAs(tags: spec.matchedMoods ?? spec.tags, artists: spec.artists))
                    MoodTile(mood: mood, subtitle: mood.subtitle(playlists: []), isCurrent: false, isPlaying: false)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Button(action: tryIt) {
                            Label("Try It", systemImage: "play.fill")
                        }
                        .buttonStyle(OutlineButtonStyle())
                        .disabled(refinding)
                        Text("Plays the first songs.")
                            .font(Theme.Text.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                }
                // A row of its own, like the two under it: plainly a field.
                TextField("Name", text: edited.name, prompt: Text("Untitled"))
                Picker("Vocals", selection: edited.vocals) {
                    ForEach(VibeSpec.Vocals.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Artists", selection: edited.mix) {
                    ForEach(VibeSpec.Mix.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(spec.matchedMoods != nil) // without a model there are no artists to mix
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    if let note = spec.note {
                        Label(note, systemImage: "info.circle")
                    }
                    if spec.matchedMoods != nil {
                        Label("Apple Intelligence is off, so the words were matched to YouTube Music\u{2019}s own moods.",
                              systemImage: "info.circle")
                    }
                }
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
            }
            if !spec.tags.isEmpty || !spec.artists.isEmpty || !(spec.matchedMoods ?? []).isEmpty {
                Section {
                    FlowLayout(spacing: Theme.Space.xxs) {
                        ForEach(spec.matchedMoods ?? [], id: \.self) { mood in
                            Chip(title: mood, symbol: "sparkles.rectangle.stack") { remove(mood: mood) }
                        }
                        ForEach(spec.tags, id: \.self) { tag in
                            Chip(title: tag, symbol: "number") { remove(tag: tag) }
                        }
                        ForEach(spec.artists, id: \.self) { artist in
                            Chip(title: artist, symbol: "music.mic") { remove(artist: artist) }
                        }
                    }
                    .disabled(refinding)
                } header: {
                    Text("Heard as")
                } footer: {
                    firstUp
                }
            } else {
                Section { EmptyView() } footer: { firstUp }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The first songs, in one line: enough to tell whether it fits.
    private var firstUp: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xxs) {
            if refinding {
                ProgressView().controlSize(.mini)
                Text("Finding songs again…")
            } else {
                Text("Starts with " + spec.anchors.prefix(3).map(\.title).joined(separator: ", ") + ", then more like them.")
            }
        }
        .font(Theme.Text.caption)
        .foregroundStyle(Theme.Colors.textMuted)
        .lineLimit(2)
    }

    private func remove(mood: String) {
        var next = spec; next.matchedMoods?.removeAll { $0 == mood }; change(next)
    }

    private func remove(tag: String) {
        var next = spec; next.tags.removeAll { $0 == tag }; change(next)
    }

    private func remove(artist: String) {
        var next = spec; next.artists.removeAll { $0 == artist }; change(next)
    }
}
