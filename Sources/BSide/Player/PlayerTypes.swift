import AppKit
import Combine
import WebKit

enum Account: Equatable {
    case unknown
    case signedOut
    /// YouTube Music tells the account's name and channel handle, not its
    /// email address.
    case signedIn(name: String, handle: String, photoURL: URL? = nil)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

enum PlayerPhase: Equatable {
    /// Started in the menu bar: registered for the media keys, but the page
    /// is not loaded until the first Play or until the window is shown.
    case asleep
    case starting
    case ready
    case failed(String)
}

/// How long the page has been starting, for the Welcome screen.
enum StartWait: Equatable {
    case short
    /// Longer than usual: said so.
    case long
    /// Long enough to offer starting again.
    case tooLong
}

enum Loadable: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// What started the current queue.
enum PlaySource: Equatable {
    case mood(String)
    case playlist(String)
    /// A track's radio, started as one: the track's title.
    case radio(String)
    case other
}

/// What the strip says plays under the track: a vibe in its colour, or a
/// playlist, an album or a track's radio in the accent.
struct SourceLabel: Hashable {
    enum Kind: Hashable {
        case vibe(colour: Int)
        case playlist
        case album
        case artist
        case radio
    }

    let kind: Kind
    let name: String
    let symbol: String
}
