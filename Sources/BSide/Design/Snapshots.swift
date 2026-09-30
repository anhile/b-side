import AppKit
import SwiftUI

/// Renders every page in its main states to PNG files, light and dark, for
/// design review without a screen recording. Run with
/// `open B-Side.app --args -snapshot /path/to/folder`; the files land there
/// and the app quits. The window is the real one: same size, hidden title
/// bar, same views, only the player is a fixture.
@MainActor
enum Snapshots {
    private static let artwork = URL(string: "https://i.ytimg.com/vi/UzIm_ZSmGYQ/hqdefault.jpg")
    private static let track = PlayerState(
        title: "Plug Walk", artist: "Rich The Kid", artworkURL: artwork, videoID: "x",
        position: 4, duration: 175, isPlaying: true, isAd: false, queueIndex: 3, queueCount: 50, queueHasMore: true)

    private static let moods = [
        Mood.liked,
        Mood(id: "focus", name: "Focus", source: .playlist(id: "1", shuffled: false)),
        Mood(id: "night", name: "Night drive with a long name", source: .playlist(id: "2", shuffled: true)),
        Mood(id: "radio", name: "Like Plug Walk", source: .radio(videoID: "x")),
    ]

    /// Name, page, and the situation to show.
    private static var cases: [(String, Page, PlayerController)] {
        var paused = track; paused.isPlaying = false
        var long = track
        long.title = "Everything In Its Right Place (Live at Glastonbury 2003, Remastered)"
        long.artist = "Radiohead feat. Someone With A Very Long Name Indeed"
        var noArt = track; noArt.artworkURL = nil
        var ad = track; ad.isAd = true; ad.title = ""
        var loading = PlayerState(); loading.videoID = "x"
        let lists = [
            Playlist(id: "1", title: "Focus", subtitle: "12 tracks", artworkURL: artwork),
            Playlist(id: "2", title: "Night drive with an unreasonably long playlist name", subtitle: "Private · 87 tracks", artworkURL: nil),
            Playlist(id: "3", title: "Workout", subtitle: "34 tracks", artworkURL: artwork),
        ]
        return [
            ("nowplaying-playing", .nowPlaying, .fixture(state: track, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-paused", .nowPlaying, .fixture(state: paused, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-long", .nowPlaying, .fixture(state: long, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-noart", .nowPlaying, .fixture(state: noArt, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-ad", .nowPlaying, .fixture(state: ad, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-loading", .nowPlaying, .fixture(state: loading, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-empty", .nowPlaying, .fixture(playlists: lists)),
            ("nowplaying-signedout", .nowPlaying, .fixture(account: .signedOut)),
            ("nowplaying-failed", .nowPlaying, .fixture(phase: .failed("YouTube Music could not be loaded. Check the connection and try again."))),
            ("vibe-playing", .vibe, .fixture(state: track, source: .mood("focus"), playlists: lists, moods: moods)),
            ("vibe-one", .vibe, .fixture(playlists: lists)),
            ("vibe-none", .vibe, .fixture(playlists: lists, moods: [])),
            ("vibe-many", .vibe, .fixture(state: track, source: .mood("m3"), playlists: lists, moods: moods + (1...5).map {
                Mood(id: "m\($0)", name: "Mood \($0)", source: .playlist(id: "1", shuffled: $0 % 2 == 0))
            })),
            ("vibe-problem", .vibe, .fixture(state: paused, source: .mood(Mood.liked.id), playlists: lists,
                                            problem: "This could not be played. It may be empty or unavailable.")),
            ("playlists-playing", .playlists, .fixture(state: track, source: .playlist("1"), playlists: lists)),
            ("playlists-loading", .playlists, .fixture(playlistsState: .loading)),
            ("playlists-failed", .playlists, .fixture(playlistsState: .failed("The list of playlists could not be loaded."))),
            ("playlists-none", .playlists, .fixture(playlists: [])),
            ("playlists-many", .playlists, .fixture(state: track, source: .playlist("7"), playlists: (1...20).map {
                Playlist(id: String($0), title: "Playlist \($0)", subtitle: "\($0 * 3) tracks", artworkURL: $0 % 2 == 0 ? artwork : nil)
            })),
        ]
    }

    static func render(into folder: URL) async {
        EventLog.write("snapshot: rendering \(cases.count) cases into \(folder.path)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSSetUncaughtExceptionHandler { exception in
            EventLog.write("snapshot: exception \(exception.name.rawValue): \(exception.reason ?? "")")
        }
        for (name, page, player) in cases {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let navigation = Navigation()
                let window = NSWindow(
                    contentRect: NSRect(origin: .zero, size: Theme.Size.window),
                    styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                    backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.appearance = NSAppearance(named: appearance)
                window.isReleasedWhenClosed = false
                let hosting = NSHostingView(rootView: PlayerWindow()
                    .environmentObject(player)
                    .environmentObject(navigation))
                hosting.sizingOptions = []
                hosting.frame = NSRect(origin: .zero, size: Theme.Size.window)
                window.contentView = hosting
                window.setFrameOrigin(NSPoint(x: -4000, y: -4000)) // never on screen
                window.orderFrontRegardless()
                // The paging scroll view only follows the page once it is laid
                // out; then artwork download and image decode.
                try? await Task.sleep(for: .seconds(0.3))
                navigation.page = page
                try? await Task.sleep(for: .seconds(1.5))
                if let image = capture(window) {
                    do {
                        try image.write(to: folder.appendingPathComponent("\(name)-\(suffix).png"))
                        EventLog.write("snapshot \(name)-\(suffix): \(image.count) bytes")
                    } catch {
                        EventLog.write("snapshot \(name)-\(suffix): write failed: \(error.localizedDescription)")
                    }
                } else {
                    EventLog.write("snapshot \(name)-\(suffix): capture returned nothing")
                }
                window.close()
            }
        }
    }

    private static func capture(_ window: NSWindow) -> Data? {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
