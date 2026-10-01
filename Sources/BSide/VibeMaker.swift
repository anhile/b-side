import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns the user's words into a vibe: what they mean (tags and artists,
/// from Apple's on-device model, or YouTube Music's moods without it), then
/// songs YouTube Music really has. The model only suggests; nothing plays
/// unless search found it. See docs/research/vibe-from-prompt.md.
@MainActor
enum VibeMaker {
    /// What the words mean, before search.
    struct Reading: Equatable {
        var name: String
        var tags: [String]
        var artists: [String]
        var vocals: VibeSpec.Vocals
        /// Set when no model read the words: the moods they matched.
        var matchedMoods: [String]?
    }

    /// The songs the stream starts from, and the artists search confirmed.
    struct Found: Equatable {
        var anchors: [Track]
        var artists: [String]
    }

    /// The most songs kept as seeds; each play starts from one of them.
    private static let anchorLimit = 8
    private static let songsPerArtist = 2
    private static let songsPerQuery = 3

    // MARK: - Reading the words

    static var hasModel: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static func read(_ prompt: String, mix: VibeSpec.Mix) async -> Reading {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), hasModel {
            do {
                return try await readWithModel(prompt, mix: mix)
            } catch {
                EventLog.write("vibe\tmodel failed: \(error.localizedDescription)")
            }
        }
        #endif
        return readByMoods(prompt)
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    @Generable
    struct ModelReading {
        // Written first, so the model works out the moment before it picks
        // music: without it, "Dota playing" got quiet folk.
        @Guide(description: "What the listener is doing or feeling, and the energy and tempo the music needs for it, in one short English sentence")
        var moment: String
        @Guide(description: "Energy the music needs, from 1 (still) to 5 (intense)", .range(1...5))
        var energy: Int
        @Guide(description: "A short, warm name for this vibe, two or three words, in the language of the request")
        var name: String
        @Guide(description: "Two to four music genres or styles a music search understands, in English, such as 'cool jazz', 'synthwave', 'lo-fi hip hop'", .count(2...4))
        var tags: [String]
        @Guide(description: "Four to eight real artists whose music fits the moment and its energy; only artists you are sure exist", .count(4...8))
        var artists: [String]
        @Guide(description: "Whether the songs should have singing", .anyOf(["any", "with", "without"]))
        var vocals: String
    }

    @available(macOS 26, *)
    private static func readWithModel(_ prompt: String, mix: VibeSpec.Mix) async throws -> Reading {
        let artists = switch mix {
        case .familiar: "Prefer well-known artists."
        case .both: "Mix well-known artists with lesser-known ones."
        case .new: "Prefer lesser-known artists; avoid the most famous names."
        }
        // No example artists: the small model copies them into any answer.
        let session = LanguageModelSession(instructions: """
            You choose music for a listener who describes a mood, an activity, a moment or a place, in any language. \
            First work out what they are doing and how much energy the music needs: an activity such as sport, \
            gaming or cleaning needs driving, energetic music; rest and sleep need calm music. \
            \(artists) Name only artists you are sure exist. Never name songs. \
            If the listener asks for no vocals or no lyrics, choose artists who make instrumental music.
            """)
        let reading = try await session.respond(to: prompt, generating: ModelReading.self).content
        EventLog.write("vibe\tmodel: \(reading.moment) | energy \(reading.energy) | \(reading.tags) \(reading.artists) \(reading.vocals)")
        return Reading(name: reading.name, tags: reading.tags, artists: unique(reading.artists),
                       vocals: VibeSpec.Vocals(model: reading.vocals), matchedMoods: nil)
    }
    #endif

    /// YouTube Music's own moods and genres, and words that lead to them.
    private static let moods: [(String, [String])] = [
        ("Chill", ["chill", "calm", "relax", "lazy", "rain", "sunday", "cozy", "спокой", "расслаб", "дожд", "уют"]),
        ("Focus", ["focus", "study", "work", "coding", "concentrat", "фокус", "учёб", "учеб", "работ"]),
        ("Sleep", ["sleep", "night", "bed", "сон", "спать", "ноч"]),
        ("Gaming", ["game", "gaming", "dota", "играю", "игра", "игру", "доту"]),
        ("Workout", ["workout", "gym", "run", "sport", "трениров", "спорт", "бег"]),
        ("Party", ["party", "dance", "friends", "вечерин", "танц", "друз"]),
        ("Feel good", ["happy", "sunny", "good", "весел", "радост", "солн"]),
        ("Romance", ["love", "romance", "date", "любов", "романт", "свидан"]),
        ("Sad", ["sad", "cry", "heartbreak", "груст", "печал"]),
        ("Commute", ["drive", "road", "commute", "car", "дорог", "машин", "поездк"]),
        ("Energize", ["energy", "pump", "morning", "бодр", "энерг", "утр"]),
        ("Jazz", ["jazz", "джаз"]),
        ("Classical", ["classical", "piano", "orchestra", "классик", "пианино", "оркестр"]),
        ("Hip-hop", ["hip-hop", "hip hop", "rap", "рэп", "хип-хоп"]),
        ("Rock", ["rock", "рок"]),
        ("Metal", ["metal", "метал"]),
        ("Dance & electronic", ["electronic", "techno", "house", "edm", "synth", "электрон", "техно"]),
        ("Indie & alternative", ["indie", "alternative", "инди"]),
        ("R&B & soul", ["r&b", "soul", "соул"]),
        ("Folk & acoustic", ["folk", "acoustic", "фолк", "акуст"]),
        ("Pop", ["pop", "поп"]),
    ]

    private static func readByMoods(_ prompt: String) -> Reading {
        let words = fold(prompt)
        let matched = moods.filter { _, cues in cues.contains { words.contains(fold($0)) } }.map(\.0)
        let without = ["no vocal", "no lyrics", "instrumental", "без слов", "без вокал", "инструмент"].contains { words.contains($0) }
        return Reading(name: name(from: prompt), tags: [], artists: [], vocals: without ? .without : .any,
                       matchedMoods: Array(matched.prefix(3)))
    }

    /// The first words of the prompt, as a name: "Rainy Sunday morning,
    /// slow jazz" gives "Rainy Sunday morning".
    private static func name(from prompt: String) -> String {
        let first = prompt.split(whereSeparator: { ",.;:!?\n".contains($0) }).first.map(String.init) ?? prompt
        let words = first.split(separator: " ").prefix(4).joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    // MARK: - Finding songs

    /// Searches YouTube Music for the artists and the tags, keeps artists
    /// that search confirms, and picks seeds from different artists.
    static func find(_ prompt: String, reading: Reading, vocals: VibeSpec.Vocals,
                     search: (String) async throws -> [MusicItem],
                     artistsDone: () -> Void = {}) async throws -> Found {
        var anchors: [Track] = []
        var confirmed: [String] = []
        var seen = Set<String>()

        func keep(_ item: MusicItem) {
            guard anchors.count < anchorLimit, seen.insert(item.videoID).inserted else { return }
            if vocals == .without, fold(item.title).contains("feat") { return }
            anchors.append(Track(index: anchors.count, videoID: item.videoID, title: item.title,
                                 artist: artistName(item), artworkURL: item.artworkURL))
        }

        let instrumental = vocals == .without ? " instrumental" : ""
        for artist in reading.artists {
            try Task.checkCancellation()
            var items = try await search(artist)
            if items.isEmpty {
                // Search now and then answers empty, most often right
                // after the page loads; once more settles it.
                try await Task.sleep(for: .milliseconds(500))
                items = try await search(artist)
            }
            var theirs = items.filter { artists(of: $0).contains(fold(artist)) }
            guard !theirs.isEmpty else {
                EventLog.write("vibe\tnot on YouTube Music: \(artist) (search gave \(items.prefix(3).map(\.subtitle)))")
                continue
            }
            confirmed.append(artist)
            if vocals == .without {
                // Their instrumental versions first, where search has them.
                theirs = theirs.filter { fold($0.title).contains("instrumental") } + theirs.filter { !fold($0.title).contains("instrumental") }
            }
            theirs.prefix(songsPerArtist).forEach(keep)
        }
        artistsDone()
        // The user's own words go to search too when the model knew little
        // (few artists confirmed) or the words are not in Latin letters,
        // where it knows the music least; YouTube Music reads any language.
        // Their songs go first then.
        let nonLatin = prompt.unicodeScalars.contains { $0.properties.isAlphabetic && !$0.isASCII && !("\u{00C0}"..."\u{024F}").contains($0) }
        let ownWords = !reading.artists.isEmpty && (confirmed.count < 2 || nonLatin)
        if ownWords && nonLatin {
            let fromArtists = anchors
            anchors = []
            seen.subtract(fromArtists.map(\.videoID))
            try await search(prompt + instrumental).prefix(songsPerQuery).forEach(keep)
            for track in fromArtists {
                keep(MusicItem(id: 0, videoID: track.videoID, title: track.title, subtitle: track.artist, artworkURL: track.artworkURL))
            }
        }
        for query in (ownWords && !nonLatin ? [prompt + instrumental] : []) + queries(prompt, reading: reading, instrumental: instrumental) {
            try Task.checkCancellation()
            try await search(query).prefix(songsPerQuery).forEach(keep)
        }
        EventLog.write("vibe\t\(anchors.count) songs, \(confirmed.count) of \(reading.artists.count) artists")
        return Found(anchors: spread(anchors), artists: confirmed)
    }

    /// The tags together, then the moods; the user's own words when there is
    /// nothing else, since YouTube Music search reads any language.
    private static func queries(_ prompt: String, reading: Reading, instrumental: String) -> [String] {
        var queries: [String] = []
        if !reading.tags.isEmpty { queries.append(reading.tags.joined(separator: " ") + instrumental) }
        if reading.tags.count > 2 { queries.append(reading.tags.prefix(2).joined(separator: " ") + instrumental) }
        queries += (reading.matchedMoods ?? []).map { $0 + " music" + instrumental }
        if reading.artists.isEmpty { queries.insert(prompt + instrumental, at: 0) }
        return queries
    }

    /// Different artists first, so the first songs say more about the vibe.
    private static func spread(_ tracks: [Track]) -> [Track] {
        var firsts: [Track] = [], rest: [Track] = [], artists = Set<String>()
        for track in tracks {
            if artists.insert(fold(track.artist)).inserted { firsts.append(track) } else { rest.append(track) }
        }
        return firsts + rest
    }

    /// "Duke Ellington & John Coltrane • …" → ["duke ellington", "john coltrane"].
    /// The whole credit stays too: "Simon & Garfunkel" is one artist.
    private static func artists(of item: MusicItem) -> [String] {
        [fold(artistName(item))] + artistName(item).components(separatedBy: CharacterSet(charactersIn: "&,"))
            .flatMap { $0.components(separatedBy: " x ") }
            .map { fold($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// "Bill Evans • Peace Piece • 6:42" → "Bill Evans".
    private static func artistName(_ item: MusicItem) -> String {
        item.subtitle.components(separatedBy: " • ").first ?? item.subtitle
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert(fold($0)).inserted }
    }
}

extension VibeSpec.Vocals {
    init(model: String) {
        switch model {
        case "with": self = .with
        case "without": self = .without
        default: self = .any
        }
    }
}
