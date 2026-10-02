import Foundation
import WebKit

/// Native-side knobs that depend on how Google / YouTube behave today.
/// Page-side knobs (config keys, endpoints, player API names) live in
/// Resources/player.js.
enum Tuning {
    /// Tracks whose playlists are remembered for Add to Playlist's checkmarks.
    static let holdingCacheSize = 200
    /// The player page usually starts in one to three seconds. After the
    /// first of these the Welcome screen says it is taking long; after the
    /// second it offers to start again.
    static let startSlowSeconds: Double = 6
    static let startRetrySeconds: Double = 15
    /// The track's name in the menu bar is cut after this many characters:
    /// the menu bar is short of room, more so beside a notch.
    /// How long a Bluetooth device asked for in Sound Output may take to
    /// connect and still get the sound.
    static let bluetoothConnectSeconds: Double = 20
    static let menuBarTrackLength = 32
    /// The list of playlists is not asked for again sooner than this when
    /// the Playlists page comes into view.
    static let playlistsFreshSeconds: Double = 30
    /// A playlist made here is shown at once and the library is asked again
    /// this often until it lists it, for this long at most.
    static let newPlaylistRetrySeconds: Double = 15
    static let newPlaylistWaitSeconds: Double = 300
    /// How long the vibe maker waits for a sleeping player page to load.
    static let pageWaitSeconds: Double = 20
    /// Google sign-in tends to reject embedded web views ("This browser or app
    /// may not be secure"). Presenting as Safari avoids that. Set to nil to use
    /// WKWebView's default user agent.
    static let userAgent: String? =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    static let musicHome = URL(string: "https://music.youtube.com/")!
    /// A track's link, before its video ID: what Copy Link copies.
    static let trackLink = "https://music.youtube.com/watch?v="

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

    /// How long a timed-lyrics source may take before the next one is tried.
    static let lyricsWait: TimeInterval = 5
    /// LRCLIB's lyrics count only for a recording this close in length, in
    /// seconds; a longer video or another edit would drift out of time.
    static let lyricsLengthTolerance: Double = 2

    /// A failed artwork download is tried once more after this many seconds.
    static let artworkRetryDelay: TimeInterval = 1
    /// How far VoiceOver's adjust gestures move the progress bar, in seconds.
    static let seekStep: TimeInterval = 10
    /// The playback clock (PlaybackClock): a report off by less than the
    /// tolerance is eased in over `clockEase` seconds; the shown time is
    /// redrawn just after each new second.
    static let clockTolerance: TimeInterval = 1.5
    static let clockEase: TimeInterval = 3
    static let clockMinimumTick: TimeInterval = 0.05
    static let clockMargin: TimeInterval = 0.02
    /// Artist and album pages kept for going back to them.
    static let explorePagesKept = 30
    /// How long a notice such as "Added to …" stays.
    static let noticeTime: TimeInterval = 2.5
}

/// A video, a playlist, or a video within a playlist.
struct PlayTarget: Equatable {
    var videoID: String?
    var listID: String?
    /// Ask the server for the playlist in random order.
    var shuffle = false
    /// Start the playlist at this track (0-based).
    var startIndex = 0

    init(videoID: String?, listID: String?, shuffle: Bool = false, startIndex: Int = 0) {
        self.videoID = videoID
        self.listID = listID
        self.shuffle = shuffle
        self.startIndex = startIndex
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
