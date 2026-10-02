import SwiftUI

/// What B-Side understood from the user's words, and the songs found for
/// them. Every part can be taken back by the user; nothing in it is played
/// unless YouTube Music search found it.
struct VibeSpec: Equatable {
    enum Vocals: String, CaseIterable, Identifiable {
        case any = "Vocals or not"
        case with = "With vocals"
        case without = "No vocals"
        var id: String { rawValue }
    }

    enum Mix: String, CaseIterable, Identifiable {
        case familiar = "Artists I know"
        case both = "Known and new"
        case new = "Only new artists"
        var id: String { rawValue }
    }

    var name: String
    var colour: Int
    var tags: [String]
    var artists: [String]
    var vocals: Vocals
    var mix: Mix
    /// The songs the stream starts from, found on YouTube Music; the first
    /// three are shown.
    var anchors: [Track]
    /// Set when no language model was used: the YouTube Music moods the
    /// words were matched to.
    var matchedMoods: [String]?
    /// Why the words were not read where the user asked, if so.
    var note: String?
    var byServer = false

    var reading: VibeMaker.Reading {
        VibeMaker.Reading(name: name, tags: tags, artists: artists, vocals: vocals, matchedMoods: matchedMoods, byServer: byServer)
    }
}

/// The sheet behind the "+" tile: a vibe from the user's own words. Three
/// steps in one sheet: describe, making, preview. A playlist, Liked Music or
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
    /// Opens the old editor: a playlist, Liked Music or a track's radio.
    let pickSource: () -> Void

    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @State private var work: Task<Void, Never>?
    /// The songs are being found again after a change in the preview.
    @State private var refinding = false
    /// With the server on: how many vibes this Mac has left this month.
    @State private var quota: VibeServer.Health?

    static let examples = ["Rainy Sunday morning", "Night drive", "Deep focus, no lyrics", "Dinner with friends"]

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
                Preview(prompt: prompt, spec: spec, refinding: refinding, change: change,
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
                             ? "In any language. The B-Side server reads the words; they are not stored. B-Side finds songs that fit and keeps playing more like them."
                             : VibeMaker.hasModel
                             ? "In any language. B-Side finds songs that fit and keeps playing more like them."
                             : "B-Side matches the words to YouTube Music\u{2019}s moods and searches for them. Turn on Apple Intelligence for a closer match.")
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
                            Label("A playlist, Liked Music or a track\u{2019}s radio", systemImage: "music.note.list")
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

/// The preview step: the tile as it will look, what was understood, and the
/// first songs. Changing a part finds the first songs again.
private struct Preview: View {
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
                    MoodTile(mood: Mood(id: "preview", name: spec.name.isEmpty ? "Untitled" : spec.name,
                                        source: .described(prompt: prompt, anchors: []), colour: spec.colour),
                             subtitle: "\u{201C}\(prompt)\u{201D}", isCurrent: false, isPlaying: false)
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

/// CUSTOM: a word in a small capsule. With a symbol it is a part of what
/// was understood and has an x that takes it out; without one, a click
/// uses it.
struct Chip: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xxs) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .imageScale(.small)
                }
                Text(title)
                    .lineLimit(1)
                if symbol != nil {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .foregroundStyle(hovering ? Theme.Colors.text : Theme.Colors.textMuted)
                }
            }
            .font(Theme.Text.caption)
            .foregroundStyle(Theme.Colors.text)
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.xxs)
            .background(Theme.Colors.text.opacity(hovering ? Theme.Opacity.hover : 0), in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.Colors.controlBorder) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHand()
        .help(symbol == nil ? "Use these words" : "Leave out \(title)")
        .accessibilityLabel(symbol == nil ? title : "Leave out \(title)")
    }
}

/// Lays its children out in rows, wrapping to the next row when one is
/// full, as words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
