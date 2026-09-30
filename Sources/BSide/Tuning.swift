import Foundation
import WebKit

/// Native-side knobs that depend on how Google / YouTube behave today.
/// Page-side knobs (config keys, endpoints, player API names) live in
/// Resources/player.js.
enum Tuning {
    /// Google sign-in tends to reject embedded web views ("This browser or app
    /// may not be secure"). Presenting as Safari avoids that. Set to nil to use
    /// WKWebView's default user agent.
    static let userAgent: String? =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    static let musicHome = URL(string: "https://music.youtube.com/")!

    static let signIn = URL(string:
        "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F")!

    /// The playlist ID of "Liked Music", the same for every account.
    static let likedMusicID = "LM"

    /// The player page: an empty document that is given YouTube Music's origin.
    static let emptyPage = "<!doctype html><html><head><meta charset=\"utf-8\"><title>B-Side</title></head><body></body></html>"

    /// How WebKit schedules a web view that is not on screen. `.none` keeps it
    /// running at full speed; try `.throttle` to see if playback survives it.
    static let inactiveScheduling: WKPreferences.InactiveSchedulingPolicy = .none

    /// Lets Safari's Web Inspector attach (Develop menu). Do not attach during a
    /// measurement run: the inspector itself costs memory.
    static let inspectable = true

    /// The `variant` column in measurement CSVs and the event log. The spike
    /// compared variants A to D; D is the one that was kept (see RESULTS.md).
    static let measurementLabel = "D"

    /// How long a track notification waits for its artwork before it goes
    /// without one.
    static let notificationArtworkWait: TimeInterval = 3
}

/// A video, a playlist, or a video within a playlist.
struct PlayTarget: Equatable {
    var videoID: String?
    var listID: String?
    /// Ask the server for the playlist in random order.
    var shuffle = false

    init(videoID: String?, listID: String?, shuffle: Bool = false) {
        self.videoID = videoID
        self.listID = listID
        self.shuffle = shuffle
    }

    /// Accepts a bare video ID (11 characters), a bare playlist ID, or a full
    /// YouTube / YouTube Music URL.
    init?(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let components = URLComponents(string: text), components.host != nil {
            videoID = components.queryItems?.first { $0.name == "v" }?.value
            listID = components.queryItems?.first { $0.name == "list" }?.value
            if videoID == nil && listID == nil { return nil }
        } else if text.count == 11 {
            videoID = text
        } else {
            listID = text
        }
    }
}
