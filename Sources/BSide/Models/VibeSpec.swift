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
