import Foundation
import WebKit

/// A track's lyrics: plain text, and where they come from ("Source: Musixmatch").
/// Empty text means the track has none. `lines` holds the timed lines when a
/// source has them (see TimedLyrics); the text is shown otherwise.
struct Lyrics: Equatable {
    let videoID: String
    var text: String
    var source: String
    /// YouTube Music's lyrics page for the track (`MPLYt…`), empty without one.
    var page = ""
    var lines: [LyricLine] = []
    /// The timings were looked for (they are only when the lyrics are shown).
    var timedTried = false

    var isTimed: Bool { !lines.isEmpty }
    var isEmpty: Bool { text.isEmpty && lines.isEmpty }
}

/// One timed line: when it starts, in seconds, and its words ("" for a break).
struct LyricLine: Equatable {
    let start: Double
    let text: String
}

extension [LyricLine] {
    /// The line being sung at `position`, or nil before the first one.
    func index(at position: Double) -> Int? {
        var low = 0, high = count
        while low < high {
            let middle = (low + high) / 2
            if self[middle].start <= position { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }
}
