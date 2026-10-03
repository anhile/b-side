import SwiftUI

/// The sheet behind the "+" tile: a vibe from the user's own words. Three
/// steps in one sheet: describe, making, preview. A playlist or
/// a track's radio are one click away, in the editor it replaced.
struct NewVibeSheet: View {
    enum Step: Equatable {
        case describe
        /// How far it got: 0 reading the words, 1 finding the artists,
        /// 2 picking the first songs.
        case making(Int)
        case preview(VibeSpec)
        /// Nothing on YouTube Music fit the words.
        case nothing
        /// Search failed: the reason.
        case failed(String)
    }

    @State var prompt: String
    @State var step: Step
    /// The tile being made again, whose id and colour stay.
    let replacing: Mood?
    /// Opens the old editor: a playlist or a track's radio.
    let pickSource: () -> Void

    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @State private var work: Task<Void, Never>?
    /// The songs are being found again after a change in the preview.
    @State private var refinding = false
    /// With the server on: how many vibes this Mac has left this month.
    @State private var quota: VibeServer.Health?

    /// Three, so they stay on one line.
    static let examples = ["Rainy day", "Night drive", "Focus"]

    init(replacing: Mood? = nil, step: Step = .describe, prompt: String? = nil, quota: VibeServer.Health? = nil,
         pickSource: @escaping () -> Void = {}) {
        _quota = State(initialValue: quota)
        var words = prompt ?? ""
        if prompt == nil, case .described(let saved, _) = replacing?.source { words = saved }
        _prompt = State(initialValue: words)
        _step = State(initialValue: step)
        self.replacing = replacing
        self.pickSource = pickSource
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .describe, .nothing, .failed:
                describe
            case .making(let done):
                making(done)
            case .preview(let spec):
                VibePreview(prompt: prompt, spec: spec, refinding: refinding, change: change,
                        tryIt: { tryIt(spec) })
            }
            footer
        }
        .frame(width: Theme.Size.editorWidth)
        .animation(.easeInOut(duration: Theme.Motion.feedback * 2), value: step)
        .onDisappear { work?.cancel() }
        // Asked when the sheet opens and after each vibe made.
        .task(id: isDescribing) {
            guard isDescribing, VibeServer.isOn, let url = VibeServer.address else { return }
            if let health = await VibeServer.health(at: url) { quota = health }
        }
    }

    private var isDescribing: Bool {
        switch step {
        case .describe, .nothing, .failed: true
        case .making, .preview: false
        }
    }

    /// Under the words, with the server on: what is left of the month.
    private var quotaText: String? {
        guard let quota, quota.open, let left = quota.left else { return nil }
        return left > 0 ? quota.leftText.map { $0 + "." }
            : "This month\u{2019}s \(quota.perMonth) vibes are used; this Mac reads the words until next month."
    }

    // MARK: - Making

    private var words: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func make(mix: VibeSpec.Mix = .both) {
        work?.cancel()
        let prompt = words
        let colour = replacing.map(VibePalette.index(for:)) ?? Int.random(in: VibePalette.swatches.indices)
        step = .making(0)
        work = Task {
            let reading = await VibeMaker.read(prompt, mix: mix)
            guard !Task.isCancelled else { return }
            step = .making(1)
            do {
                let found = try await VibeMaker.find(prompt, reading: reading, vocals: reading.vocals,
                                                     search: player.findSongs, artistsDone: { step = .making(2) })
                guard !Task.isCancelled else { return }
                if found.anchors.isEmpty {
                    step = .nothing
                } else {
                    step = .preview(VibeSpec(name: reading.name, colour: colour, tags: reading.tags, artists: found.artists,
                                             vocals: reading.vocals, mix: mix, anchors: found.anchors,
                                             matchedMoods: reading.matchedMoods, note: reading.note, byServer: reading.byServer))
                }
            } catch is CancellationError {
            } catch {
                step = .failed("YouTube Music could not be searched. Check the connection and try again.")
            }
        }
    }

    /// A change in the preview: the name only renames; the artists' mix
    /// reads the words again; anything else finds the songs again.
    private func change(_ spec: VibeSpec) {
        guard case .preview(let old) = step else { return }
        step = .preview(spec)
        if spec.mix != old.mix { return make(mix: spec.mix) }
        guard spec.tags != old.tags || spec.artists != old.artists || spec.vocals != old.vocals
                || spec.matchedMoods != old.matchedMoods else { return }
        work?.cancel()
        refinding = true
        let prompt = words
        work = Task {
            defer { if !Task.isCancelled { refinding = false } }
            guard let found = try? await VibeMaker.find(prompt, reading: spec.reading, vocals: spec.vocals,
                                                        search: player.findSongs),
                  !Task.isCancelled, !found.anchors.isEmpty,
                  case .preview(var current) = step else { return }
            current.anchors = found.anchors
            step = .preview(current)
        }
    }

    private func tryIt(_ spec: VibeSpec) {
        guard let first = spec.anchors.first else { return }
        player.play(MusicItem(id: 0, videoID: first.videoID, title: first.title, subtitle: first.artist,
                              artworkURL: first.artworkURL))
    }

    private func add(_ spec: VibeSpec) {
        var mood = replacing ?? Mood(name: "", source: .likedShuffled)
        mood.name = spec.name.trimmingCharacters(in: .whitespaces)
        mood.colour = spec.colour
        mood.source = .described(prompt: words, anchors: spec.anchors.map(\.videoID))
        mood.heardAs = Mood.heardAs(tags: spec.matchedMoods ?? spec.tags, artists: spec.artists)
        player.save(mood)
        dismiss()
    }

    // MARK: - Describe

    private var describe: some View {
        Form {
            Section {
                TextField("Describe a vibe", text: $prompt,
                          prompt: Text("Rainy Sunday, slow jazz, no vocals"), axis: .vertical)
                    .lineLimit(3...5)
                    .labelsHidden()
            } header: {
                Text("Describe a vibe")
            } footer: {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .nothing:
                        Label("Nothing on YouTube Music fit these words. Try a genre, an artist or a place.",
                              systemImage: "exclamationmark.circle")
                    case .failed(let reason):
                        Label(reason, systemImage: "exclamationmark.triangle")
                    default:
                        Text(VibeServer.isOn
                             ? "Any language works. B-Side finds songs that fit and keeps more coming. The words go to the B-Side server and are not kept."
                             : VibeMaker.hasModel
                             ? "Any language works. B-Side finds songs that fit and keeps more coming."
                             : "B-Side matches the words to YouTube Music\u{2019}s moods. Turn on Apple Intelligence for a closer match.")
                        if let quotaText {
                            Text(quotaText)
                                .padding(.top, Theme.Space.xxs)
                        }
                    }
                }
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
            }
            Section("Or try") {
                FlowLayout(spacing: Theme.Space.xxs) {
                    ForEach(Self.examples, id: \.self) { example in
                        Chip(title: example) { prompt = example }
                    }
                }
            }
            // The other way to a tile, as a row of its own: it leads to
            // the editor with its three kinds.
            if replacing == nil {
                Section("Or play what you have") {
                    Button {
                        dismiss()
                        pickSource()
                    } label: {
                        HStack(spacing: Theme.Space.xs) {
                            Label("A playlist or a track\u{2019}s radio", systemImage: "music.note.list")
                                .foregroundStyle(Theme.Colors.text)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .imageScale(.small)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let stages = ["Reading the words", "Finding artists on YouTube Music", "Picking the first songs"]

    private func making(_ done: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("\u{201C}\(words)\u{201D}")
                .font(Theme.Text.title)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(Self.stages.indices, id: \.self) { index in
                    HStack(spacing: Theme.Space.xs) {
                        Group {
                            if index < done {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Colors.accentText)
                            } else if index == done {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .imageScale(.small)
                            }
                        }
                        .frame(width: Theme.Space.m)
                        Text(Self.stages[index])
                            .font(Theme.Text.body)
                            .foregroundStyle(index <= done ? Theme.Colors.text : Theme.Colors.textMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .padding(.top, Theme.Space.xs)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if case .preview = step {
                Button("Back") {
                    work?.cancel()
                    refinding = false
                    step = .describe
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            switch step {
            case .describe, .nothing, .failed:
                Button("Make") { make() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(words.isEmpty)
            case .making:
                EmptyView()
            case .preview(let spec):
                Button(replacing == nil ? "Add Vibe" : "Save") { add(spec) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(spec.name.trimmingCharacters(in: .whitespaces).isEmpty || spec.anchors.isEmpty || refinding)
            }
        }
        .padding(Theme.Space.m)
    }
}
