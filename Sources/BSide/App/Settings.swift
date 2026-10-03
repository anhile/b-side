import AppKit

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
    static let menuBarTrack = "menuBarTrack"     // the track's name next to the record in the menu bar
    static let bluetoothOutputs = "bluetoothOutputs" // asked to see paired Bluetooth devices in Sound Output
    static let theme = "theme"                   // ThemeMode: system, light or dark
    static let uiSize = "uiSize"                 // UISize: compact or large
    static let repeatMode = "repeatMode"         // RepeatMode: off, all or one
    static let vibeServer = "vibeServer"         // read vibe words on the B-Side server (off by default)
    static let vibeServerAddress = "vibeServerAddress" // that server's address
    static let vibeInstallID = "vibeInstallID"   // a random ID the server counts this Mac's vibes by
    // Launch arguments only, e.g. `open B-Side.app --args -play <id> -muted YES`
    static let play = "play"
    static let vibe = "vibe"                     // start Vibe (Liked Music, shuffled) at launch
    static let startHidden = "startHidden"       // start in the menu bar without the window, as at login
    static let muted = "muted"
    static let startIndex = "startIndex"         // start a playlist at this track (0-based)
    static let listTracks = "listTracks"         // debug: open this playlist's track list at launch
    static let playTrack = "playTrack"           // debug: with listTracks, play from this track (0-based)
    static let url = "url"                       // debug: load this URL instead of the player page
    static let page = "page"                     // debug: open the window on this page (nowPlaying, vibe, playlists, explore)
    static let makeVibe = "makeVibe"             // debug: make a vibe from these words once the page is ready, and log it
    static let vibeServerDebug = "vibeServerURL" // debug: -vibeServerURL <url> turns the server on with that address
    static let lastSession = "lastSession"       // the track that played last, shown paused at the next launch
    static let resume = "resume"                 // debug: press Play on the restored track once the app has started
    static let snapshotOnly = "snapshotOnly"     // with snapshot: only the pages whose name has this in it
    static let snapshot = "snapshot"             // render the screens with sample data into this folder and quit
    static let proxy = "proxy"                   // debug: host:port of an HTTP CONNECT proxy for all traffic
    static let captureTo = "captureTo"           // debug: write pictures of the real window into this folder…
    static let captureAt = "captureAt"           // …at these seconds after launch, "5,20,60"
    static let scratch = "scratch"               // debug: settings and the last session in a throwaway domain
}

enum Settings {
    /// Rendering design snapshots: a second copy of B-Side, next to the
    /// user's own, that must not touch the player, the menu bar or the
    /// user's settings.
    static let isSnapshot = UserDefaults.standard.string(forKey: Keys.snapshot) != nil
    /// A test run: it must not touch the user's settings or their last session.
    private static let isScratch = isSnapshot || UserDefaults.standard.bool(forKey: Keys.scratch)
    /// The sample data a snapshot sets (volume, Vibe tiles) goes to a scratch
    /// domain, emptied before and after, instead of the user's settings.
    static let defaults: UserDefaults = isScratch ? scratch : .standard

    private static let scratchName = "\(Bundle.main.bundleIdentifier ?? "B-Side").snapshot"
    private static let scratch: UserDefaults = {
        let scratch = UserDefaults(suiteName: scratchName) ?? .standard
        scratch.removePersistentDomain(forName: scratchName)
        return scratch
    }()

    static func clearScratch() {
        guard isSnapshot else { return }
        defaults.removePersistentDomain(forName: scratchName)
    }

    static func register() {
        defaults.register(defaults: [
            Keys.nativeNowPlaying: true,
            Keys.reloadWhenPaused: false,
            Keys.reloadAfterMinutes: 5,
            Keys.forceAudioOnly: true,
            Keys.volume: 100.0,
            Keys.notifyTrack: false,
            Keys.menuBarTrack: false,
            Keys.bluetoothOutputs: false,
        ])
    }

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
}

/// Settings, Appearance: light, dark, or as the system is.
enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    static var current: ThemeMode {
        ThemeMode(rawValue: Settings.defaults.string(forKey: Keys.theme) ?? "") ?? .system
    }

    /// For the whole app: the windows, the menu and Settings. The colours
    /// in the asset catalog follow it.
    static func apply(_ mode: ThemeMode = current) {
        NSApp.appearance = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Settings, Appearance: the size of everything in the window and the menu.
/// Large is for reading at a distance or with low vision.
enum UISize: String, CaseIterable, Identifiable {
    case compact, large

    var id: String { rawValue }
    var title: String { self == .compact ? "Compact" : "Large" }
    /// What Theme multiplies type, spacing and sizes by.
    var scale: CGFloat { self == .compact ? 1 : 1.3 }

    static var current: UISize {
        UISize(rawValue: Settings.defaults.string(forKey: Keys.uiSize) ?? "") ?? .compact
    }
}

/// Repeat, as in YouTube Music: off, the whole queue, or the current track.
enum RepeatMode: String, CaseIterable, Identifiable {
    case off, all, one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }

    var symbol: String { self == .one ? "repeat.1" : "repeat" }

    /// The order a click on the Repeat button goes through.
    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}
