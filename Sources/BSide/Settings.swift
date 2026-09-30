import Foundation

enum Keys {
    static let nativeNowPlaying = "nativeNowPlaying"
    static let reloadWhenPaused = "reloadWhenPaused"
    static let reloadAfterMinutes = "reloadAfterMinutes"
    static let forceAudioOnly = "forceAudioOnly"
    // Launch arguments only, e.g. `open B-Side.app --args -play <id> -muted YES`
    static let play = "play"
    static let vibe = "vibe"                     // start Vibe (Liked Music, shuffled) at launch
    static let muted = "muted"
    static let startIndex = "startIndex"         // start a playlist at this track (0-based)
    static let url = "url"                       // debug: load this URL instead of the player page
}

enum Settings {
    static let defaults = UserDefaults.standard

    static func register() {
        defaults.register(defaults: [
            Keys.nativeNowPlaying: true,
            Keys.reloadWhenPaused: false,
            Keys.reloadAfterMinutes: 5,
            Keys.forceAudioOnly: true,
        ])
    }

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
}
