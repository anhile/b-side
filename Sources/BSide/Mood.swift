import Foundation

/// A tile on the Vibe page: a name and what to play for it.
struct Mood: Identifiable, Equatable {
    enum Source: Equatable {
        case likedShuffled
        case playlist(id: String, shuffled: Bool)
        case radio(videoID: String)
    }

    let id: String
    var name: String
    var source: Source

    /// The tile every account starts with.
    static let liked = Mood(id: "liked", name: "Liked Music, shuffled", source: .likedShuffled)

    var target: PlayTarget {
        switch source {
        case .likedShuffled: return PlayTarget(videoID: nil, listID: Tuning.likedMusicID, shuffle: true)
        case .playlist(let id, let shuffled): return PlayTarget(videoID: nil, listID: id, shuffle: shuffled)
        case .radio(let videoID): return PlayTarget(videoID: videoID, listID: nil)
        }
    }
}
