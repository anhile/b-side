import Foundation

enum Keys {
    static let nativeNowPlaying = "nativeNowPlaying"
    static let reloadWhenPaused = "reloadWhenPaused"
    static let reloadAfterMinutes = "reloadAfterMinutes"
    static let forceAudioOnly = "forceAudioOnly"
    static let volume = "volume"                 // 0 to 100
    static let moods = "moods"                   // the Vibe tiles, JSON
    static let wasSignedIn = "wasSignedIn"       // greet with "Welcome back" while the player loads
    static let guest = "guest"                   // chose to use B-Side without signing in
    static let notifyTrack = "notifyTrack"       // a notification when the next track starts
    // Launch arguments only, e.g. `open B-Side.app --args -play <id> -muted YES`
    static let play = "play"
    static let vibe = "vibe"                     // start Vibe (Liked Music, shuffled) at launch
    static let startHidden = "startHidden"       // start in the menu bar without the window, as at login
    static let muted = "muted"
    static let startIndex = "startIndex"         // start a playlist at this track (0-based)
    static let listTracks = "listTracks"         // debug: open this playlist's track list at launch
    static let playTrack = "playTrack"           // debug: with listTracks, play from this track (0-based)
    static let lyrics = "lyrics"                 // debug: fetch the first track's lyrics, as opening them does
    static let url = "url"                       // debug: load this URL instead of the player page
    static let snapshot = "snapshot"             // render the screens with sample data into this folder and quit
}

enum Settings {
    static let defaults = UserDefaults.standard

    static func register() {
        defaults.register(defaults: [
            Keys.nativeNowPlaying: true,
            Keys.reloadWhenPaused: false,
            Keys.reloadAfterMinutes: 5,
            Keys.forceAudioOnly: true,
            Keys.volume: 100.0,
            Keys.notifyTrack: false,
        ])
    }

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
}
