import Foundation

/// A tile on the Vibe page: a name and what to play for it.
struct Mood: Identifiable, Equatable, Codable {
    enum Source: Equatable, Codable {
        case likedShuffled
        case playlist(id: String, shuffled: Bool)
        case radio(videoID: String)
        /// Made from the user's words: the songs found for them, whose
        /// radios play one after another.
        case described(prompt: String, anchors: [String])
    }

    var id: String
    var name: String
    var source: Source
    /// One of VibePalette's colours, when the user picked one.
    var colour: Int?

    init(id: String = UUID().uuidString, name: String, source: Source, colour: Int? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.colour = colour
    }

    /// The tile every account starts with.
    static let liked = Mood(id: "liked", name: "Liked Music", source: .likedShuffled)

    /// Liked Music belongs to an account; a track's radio and a public
    /// playlist play without one.
    var needsAccount: Bool {
        if case .likedShuffled = source { return true }
        return false
    }

    var target: PlayTarget {
        switch source {
        case .likedShuffled: return PlayTarget(videoID: nil, listID: Tuning.likedMusicID, shuffle: true)
        case .playlist(let id, let shuffled): return PlayTarget(videoID: nil, listID: id, shuffle: shuffled)
        case .radio(let videoID): return PlayTarget(videoID: videoID, listID: nil)
        case .described(_, let anchors): return PlayTarget(videoID: anchors.randomElement(), listID: nil) // a different start each time
        }
    }

    /// The SF Symbol for the kind of source.
    var symbol: String {
        switch source {
        case .likedShuffled: return "heart.fill"
        case .playlist: return "music.note.list"
        case .radio: return "dot.radiowaves.left.and.right"
        case .described: return "text.bubble"
        }
    }

    /// What the tile says under its name. Playlist names come from the
    /// library, which may not be loaded yet.
    func subtitle(playlists: [Playlist]) -> String {
        switch source {
        case .likedShuffled:
            return "Shuffled"
        case .playlist(let id, let shuffled):
            var title = playlists.first { $0.id == id }?.title ?? (id == Tuning.likedMusicID ? "Liked Music" : "Playlist")
            if title == name { title = "Playlist" } // "Focus / Focus" says nothing
            return shuffled ? "\(title), shuffled" : title
        case .radio:
            return "Radio"
        case .described(let prompt, _):
            return "“\(prompt)”"
        }
    }

    // MARK: - Saved in UserDefaults as JSON

    static func load() -> [Mood] {
        guard let data = Settings.defaults.data(forKey: Keys.moods),
              let moods = try? JSONDecoder().decode([Mood].self, from: data) else { return [.liked] }
        return moods
    }

    static func save(_ moods: [Mood]) {
        guard let data = try? JSONEncoder().encode(moods) else { return }
        Settings.defaults.set(data, forKey: Keys.moods)
    }
}
