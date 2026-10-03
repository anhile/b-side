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

    /// A playlist's tracks, the second one being the one that plays.
    private static func tracks(current: String) -> [Track] {
        let names = [("Sicko Mode", "Travis Scott"), ("Plug Walk", "Rich The Kid"),
                     ("A title long enough to be cut at the end of the row", "Someone feat. Someone Else"),
                     ("Goosebumps", "Travis Scott"), ("", ""), ("Money Longer", "Lil Uzi Vert")]
        return names.enumerated().map { index, name in
            Track(index: index, videoID: index == 1 ? current : "t\(index)", title: name.0, artist: name.1,
                  artworkURL: index % 2 == 0 ? artwork : nil, length: "\(2 + index % 3):\(10 + index * 7)")
        }
    }

    /// Made-up timed lyrics; the track in the fixture is 18 s in, on line 4.
    private static let lyrics = Lyrics(
        videoID: "x", text: "", source: "Source: Musixmatch",
        lines: ["Placeholder words for the first line", "A second line that runs long enough to wrap",
                "", "The line being sung right now", "What comes next", "And after that",
                "A line further down", "The last line"]
            .enumerated().map { LyricLine(start: Double($0.offset * 5 + 3), text: $0.element) })

    /// Name, page, and the situation to show.
    private static var cases: [(String, Page, PlayerController)] {
        var paused = track; paused.isPlaying = false; paused.like = "LIKE" // it plays from Liked Music
        var long = track
        long.title = "Everything In Its Right Place (Live at Glastonbury 2003, Remastered)"
        long.artist = "Radiohead feat. Someone With A Very Long Name Indeed"
        var noArt = track; noArt.artworkURL = nil
        var ad = track; ad.isAd = true; ad.title = ""; ad.adLeft = 12; ad.adLeftAt = .distantFuture // stands still
        var adRun = ad; adRun.adIndex = 1; adRun.adCount = 2
        var loading = PlayerState(); loading.videoID = "x"
        let lists = [
            Playlist(id: "1", title: "Focus", subtitle: "Emil • 12 tracks", artworkURL: artwork),
            Playlist(id: "2", title: "Night drive with an unreasonably long playlist name", subtitle: "Someone Else • 87 tracks", artworkURL: nil),
            Playlist(id: "3", title: "Workout", subtitle: "Emil • 34 tracks", artworkURL: artwork),
        ]
        return [
            ("nowplaying-playing", .nowPlaying, .fixture(state: track, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-paused", .nowPlaying, .fixture(state: paused, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-long", .nowPlaying, .fixture(state: long, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-noart", .nowPlaying, .fixture(state: noArt, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-ad", .nowPlaying, .fixture(state: ad, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-ad-run", .nowPlaying, .fixture(state: adRun, source: .mood(Mood.liked.id), playlists: lists)),
            ("vibe-ad", .vibe, .fixture(state: ad, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-loading", .nowPlaying, .fixture(state: loading, source: .mood(Mood.liked.id), playlists: lists)),
            ("nowplaying-empty", .nowPlaying, .fixture(playlists: lists)),
            ("nowplaying-signedout", .nowPlaying, .fixture(account: .signedOut)),
            ("nowplaying-guest", .nowPlaying, .fixture(account: .signedOut, moods: [.liked], isGuest: true)),
            ("vibe-guest", .vibe, .fixture(account: .signedOut, moods: moods, isGuest: true)),
            ("playlists-guest", .playlists, .fixture(account: .signedOut, isGuest: true)),
            ("welcome", .nowPlaying, .fixture(account: .unknown, phase: .asleep)),
            ("welcome-long", .nowPlaying, .fixture(account: .unknown, phase: .starting, startWait: .long)),
            ("welcome-toolong", .nowPlaying, .fixture(account: .unknown, phase: .starting, startWait: .tooLong)),
            ("nowplaying-failed", .nowPlaying, .fixture(phase: .failed("YouTube Music could not be loaded. Check the connection and try again."))),
            ("vibe-playing", .vibe, .fixture(state: track, source: .mood("focus"), playlists: lists, moods: moods)),
            ("vibe-one", .vibe, .fixture(playlists: lists)),
            ("vibe-longstrip", .vibe, .fixture(state: long, source: .mood("focus"), playlists: lists, moods: moods)),
            ("vibe-radio", .vibe, .fixture(state: track, source: .radio("Sicko Mode"), playlists: lists, moods: moods)),
            ("vibe-none", .vibe, .fixture(playlists: lists, moods: [])),
            ("vibe-many", .vibe, .fixture(state: track, source: .mood("m3"), playlists: lists, moods: moods + (1...5).map {
                Mood(id: "m\($0)", name: "Mood \($0)", source: .playlist(id: "1", shuffled: $0 % 2 == 0))
            })),
            ("vibe-problem", .vibe, .fixture(state: paused, source: .mood(Mood.liked.id), playlists: lists,
                                            problem: "This could not be played. It may be empty or unavailable.")),
            ("playlists-playing", .playlists, .fixture(state: track, source: .playlist("1"), playlists: lists)),
            ("playlist-tracks", .playlists, .fixture(state: track, source: .playlist("1"), playlists: lists,
                                                     openPlaylist: lists[0], tracks: tracks(current: track.videoID), tracksState: .loaded)),
            ("playlist-tracks-loading", .playlists, .fixture(playlists: lists, openPlaylist: lists[1], tracksState: .loading)),
            ("playlists-loading", .playlists, .fixture(playlistsState: .loading)),
            ("playlists-failed", .playlists, .fixture(playlistsState: .failed("The list of playlists could not be loaded."))),
            ("playlists-none", .playlists, .fixture(playlists: [])),
            ("playlists-many", .playlists, .fixture(state: track, source: .playlist("7"), playlists: (1...20).map {
                Playlist(id: String($0), title: "Playlist \($0)", subtitle: "\($0 * 3) tracks", artworkURL: $0 % 2 == 0 ? artwork : nil)
            })),
        ]
    }

    /// The Settings window, one file per tab.
    private static func renderSettings(into folder: URL) async {
        let player = PlayerController.fixture(state: track, account: .signedIn(name: "Emil", handle: "@emil", photoURL: artwork),
                                              source: .mood(Mood.liked.id))
        player.processesForSnapshot = [
            ProcessInfoRow(pid: 501, name: "B-Side", footprintBytes: 41 << 20),
            ProcessInfoRow(pid: 502, name: "WebContent", footprintBytes: 88 << 20),
            ProcessInfoRow(pid: 503, name: "GPU", footprintBytes: 16 << 20),
            ProcessInfoRow(pid: 504, name: "Networking", footprintBytes: 12 << 20),
        ]
        for tab in SettingsView.Tab.allCases {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                // The real window, toolbar and all: the whole frame is captured.
                let (window, keep) = SettingsWindow.make(player: player, tab: tab)
                window.appearance = NSAppearance(named: appearance)
                window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
                window.orderFrontRegardless()
                try? await Task.sleep(for: .seconds(0.8))
                if let contentView = window.contentView { window.setContentSize(contentView.fittingSize) }
                try? await Task.sleep(for: .seconds(0.4))
                withExtendedLifetime(keep) {}
                if let image = capture(window, frame: true) {
                    try? image.write(to: folder.appendingPathComponent("settings-\(tab.rawValue)-\(suffix).png"))
                }
                window.close()
            }
        }
    }

    /// The New Vibe sheet in each step, as it shows over the window.
    private static func renderNewVibe(into folder: URL) async {
        let jazz = VibeSpec(
            name: "Rainy Sunday", colour: 2, tags: ["slow jazz", "rainy", "instrumental"],
            artists: ["Bill Evans", "Chet Baker", "Kenny Dorham", "Paul Desmond"], vocals: .without, mix: .both,
            anchors: [Track(index: 0, videoID: "a", title: "Peace Piece", artist: "Bill Evans", artworkURL: artwork),
                      Track(index: 1, videoID: "b", title: "Alone Together", artist: "Chet Baker", artworkURL: nil),
                      Track(index: 2, videoID: "c", title: "Lotus Blossom", artist: "Kenny Dorham", artworkURL: artwork)],
            matchedMoods: nil)
        var plain = jazz
        plain.name = "Rainy Sunday"; plain.colour = 3; plain.tags = []; plain.artists = []
        plain.matchedMoods = ["Chill", "Jazz"]
        let prompt = "Rainy Sunday morning, slow jazz, no vocals"
        let cases: [(String, NewVibeSheet)] = [
            ("describe-empty", NewVibeSheet()),
            ("describe", NewVibeSheet(prompt: prompt)),
            ("describe-quota", NewVibeSheet(prompt: prompt, quota: VibeServer.Health(open: true, perMonth: 10, left: 7))),
            ("nothing", NewVibeSheet(step: .nothing, prompt: "asdfgh qwerty")),
            ("making", NewVibeSheet(step: .making(1), prompt: prompt)),
            ("preview", NewVibeSheet(step: .preview(jazz), prompt: prompt)),
            ("preview-plain", NewVibeSheet(step: .preview(plain), prompt: prompt)),
        ]
        let player = PlayerController.fixture()
        for (name, sheet) in cases {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                // A sheet sits on the window's own background, which a borderless
                // window's content view does not draw.
                let hosting = NSHostingController(rootView: sheet.environmentObject(player)
                    .background(Color(nsColor: .windowBackgroundColor)))
                let window = NSWindow(contentViewController: hosting)
                window.styleMask = [.borderless]
                window.appearance = NSAppearance(named: appearance)
                window.isReleasedWhenClosed = false
                window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
                window.orderFrontRegardless()
                try? await Task.sleep(for: .seconds(0.8))
                window.setContentSize(hosting.view.fittingSize)
                try? await Task.sleep(for: .seconds(0.6))
                if let image = capture(window) {
                    try? image.write(to: folder.appendingPathComponent("newvibe-\(name)-\(suffix).png"))
                }
                window.close()
            }
        }
    }

    static func render(into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await renderNewVibe(into: folder)
        await renderSettings(into: folder)
        await renderPage(.nowPlaying, player: .fixture(state: track, source: .mood(Mood.liked.id)),
                         name: "nowplaying-reduce-transparency", appearance: .aqua, into: folder,
                         reduceTransparency: true)
        await renderPage(.nowPlaying, player: .fixture(state: track, source: .mood(Mood.liked.id)),
                         name: "nowplaying-hover", appearance: .aqua, into: folder,
                         reduceTransparency: true, artworkHover: true)
        var pausedTrack = track; pausedTrack.isPlaying = false
        await renderPage(.nowPlaying, player: .fixture(state: pausedTrack, source: .mood(Mood.liked.id)),
                         name: "nowplaying-hover-paused", appearance: .darkAqua, into: folder,
                         artworkHover: true)
        var singing = track; singing.position = 18
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            await renderPage(.nowPlaying, player: .fixture(state: singing, source: .mood(Mood.liked.id), lyrics: lyrics),
                             name: "nowplaying-lyrics-\(suffix)", appearance: appearance, into: folder, showsLyrics: true)
        }
        let next = tracks(current: "").enumerated().map { offset, item in
            var item = item; item.index = offset + 4; return item
        }
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            await renderPage(.nowPlaying, player: .fixture(state: track, source: .mood(Mood.liked.id), upNext: next),
                             name: "nowplaying-queue-\(suffix)", appearance: appearance, into: folder, showsQueue: true)
        }
        await renderPage(.nowPlaying, player: .fixture(state: track, source: .mood(Mood.liked.id)),
                         name: "nowplaying-queue-empty", appearance: .darkAqua, into: folder, showsQueue: true)
        var plain = lyrics; plain.lines = []; plain.timedTried = true
        plain.text = "Plain lyrics, without timings,\nshown as text you can select.\n\nA second verse\nof made-up words."
        await renderPage(.nowPlaying, player: .fixture(state: singing, source: .mood(Mood.liked.id), lyrics: plain),
                         name: "nowplaying-lyrics-plain", appearance: .aqua, into: folder, showsLyrics: true)
        let found = [("Вокруг шум", "Каста • Быль в глаза", "3:36"), ("Plug Walk", "Rich The Kid • Plug Walk", "2:55"),
                     ("A result with a title long enough to be cut", "Someone feat. Someone Else • An album", "4:07"),
                     ("Ды-ды-дым", "Каста • Быль в глаза", "4:07")]
            .enumerated().map { index, item in
                MusicItem(id: index, videoID: index == 1 ? track.videoID : "s\(index)", title: item.0,
                          subtitle: item.1, detail: item.2, artworkURL: index % 2 == 0 ? artwork : nil)
            }
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            await renderPage(.explore, player: .fixture(state: track, source: .other), name: "explore-empty-\(suffix)",
                             appearance: appearance, into: folder)
            await renderPage(.explore, player: .fixture(state: track, source: .other, search: ("каста", found),
                                                        searchState: .loaded),
                             name: "explore-results-\(suffix)", appearance: appearance, into: folder)
        }
        let albums = (1...4).map {
            MusicItem(id: $0, kind: .album, playlistID: "OLAK\($0)", browseID: "MPREb\($0)",
                      title: $0 == 1 ? "Быль в глаза" : "An album with a longer name \($0)",
                      subtitle: "\(2000 + $0 * 4)", artworkURL: $0 % 2 == 1 ? artwork : nil)
        }
        let related = (1...4).map {
            MusicItem(id: $0, kind: .artist, browseID: "UC\($0)", title: ["25/17", "Баста", "Someone", "Other"][$0 - 1])
        }
        let artistPage = ArtistPage(id: "UCkasta", name: "Каста", artworkURL: artwork, songsPlaylistID: "OLAKall",
                                    songs: Array(found.prefix(3)),
                                    shelves: [.init(id: 0, title: "Albums", items: albums),
                                              .init(id: 1, title: "Fans might also like", items: related)])
        let albumTracks = ["В супермаркете", "Встреча", "Нормально всё", "Вокруг шум", "Ды-ды-дым"].enumerated().map {
            MusicItem(id: $0.offset, videoID: $0.offset == 3 ? track.videoID : "a\($0.offset)", title: $0.element,
                      subtitle: "Каста", detail: "3:\(10 + $0.offset * 7)", artistID: "UCkasta")
        }
        let album = CollectionPage(id: "MPREbalbum", isAlbum: true, title: "Быль в глаза", subtitle: "Album • 2008",
                                   artist: "Каста", artistID: "UCkasta", artworkURL: artwork, playlistID: "OLAKalbum",
                                   tracks: albumTracks)
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            await renderPage(.explore, player: .fixture(state: track, source: .other, artist: artistPage),
                             name: "explore-artist-\(suffix)", appearance: appearance, into: folder,
                             explorePath: [.artist(id: "UCkasta", name: "Каста")])
            await renderPage(.explore, player: .fixture(state: track, source: .other, collection: album),
                             name: "explore-album-\(suffix)", appearance: appearance, into: folder,
                             explorePath: [.collection(id: "MPREbalbum", title: "Быль в глаза")])
        }
        var shelvesOnly = artistPage; shelvesOnly.songs = []
        await renderPage(.explore, player: .fixture(state: track, source: .other, artist: shelvesOnly),
                         name: "explore-artist-rows", appearance: .aqua, into: folder,
                         explorePath: [.artist(id: "UCkasta", name: "Каста")])
        await renderPage(.explore, player: .fixture(search: ("каста", []), searchState: .loading),
                         name: "explore-loading", appearance: .aqua, into: folder)
        await renderPage(.explore, player: .fixture(search: ("zzqx", []), searchState: .loaded),
                         name: "explore-nothing", appearance: .aqua, into: folder)
        await renderPage(.explore, player: .fixture(state: track, source: .other, search: ("каста", found),
                                                    searchState: .loaded),
                         name: "explore-reduce-transparency", appearance: .aqua, into: folder, reduceTransparency: true)
        // The Large size, 30% bigger.
        Theme.scale = UISize.large.scale
        let largeLists = [Playlist(id: "1", title: "Focus", subtitle: "12 tracks", artworkURL: artwork),
                          Playlist(id: "2", title: "Night drive", subtitle: "87 tracks")]
        await renderPage(.nowPlaying, player: .fixture(state: track, source: .mood(Mood.liked.id)),
                         name: "large-nowplaying", appearance: .aqua, into: folder, reduceTransparency: true)
        await renderPage(.nowPlaying, player: .fixture(state: singing, source: .mood(Mood.liked.id), lyrics: lyrics),
                         name: "large-lyrics", appearance: .darkAqua, into: folder, showsLyrics: true)
        await renderPage(.vibe, player: .fixture(state: track, source: .mood("focus"), moods: moods),
                         name: "large-vibe", appearance: .aqua, into: folder, reduceTransparency: true)
        await renderPage(.playlists, player: .fixture(state: track, source: .playlist("1"), playlists: largeLists),
                         name: "large-playlists", appearance: .darkAqua, into: folder, reduceTransparency: true)
        Theme.scale = UISize.compact.scale
        // Glass does not draw offscreen; these show the strip's panel shape.
        let many = (1...20).map { Playlist(id: "\($0)", title: "Playlist \($0)", subtitle: "\($0 * 3) tracks", artworkURL: nil) }
        await renderPage(.playlists, player: .fixture(state: track, source: .playlist("1"), playlists: many),
                         name: "playlists-reduce-transparency", appearance: .aqua, into: folder,
                         reduceTransparency: true)
        await renderPage(.playlists, player: .fixture(state: track, source: .playlist("1"), playlists: many,
                                                      openPlaylist: many[0], tracks: tracks(current: track.videoID),
                                                      tracksState: .loaded),
                         name: "playlist-tracks-reduce-transparency", appearance: .aqua, into: folder,
                         reduceTransparency: true)
        await renderPage(.vibe, player: .fixture(state: track, source: .mood("focus"), moods: moods),
                         name: "vibe-reduce-transparency", appearance: .darkAqua, into: folder,
                         reduceTransparency: true)
        EventLog.write("snapshot: rendering \(cases.count) cases into \(folder.path)")
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

    /// One page in one appearance, with the accessibility settings given.
    private static func renderPage(_ page: Page, player: PlayerController, name: String,
                                   appearance: NSAppearance.Name, into folder: URL,
                                   reduceTransparency: Bool = false, artworkHover: Bool = false,
                                   showsLyrics: Bool = false, showsQueue: Bool = false,
                                   explorePath: [ExploreRoute] = []) async {
        if let only = UserDefaults.standard.string(forKey: Keys.snapshotOnly), !name.contains(only) { return }
        let navigation = Navigation()
        navigation.showsLyrics = showsLyrics
        navigation.showsQueue = showsQueue
        navigation.setExplorePath(explorePath)
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
            .environmentObject(navigation)
            .environment(\.previewReduceTransparency, reduceTransparency)
            .environment(\.previewArtworkHover, artworkHover))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Theme.Size.window)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(0.3))
        navigation.page = page
        try? await Task.sleep(for: .seconds(1.5))
        if let image = capture(window) {
            try? image.write(to: folder.appendingPathComponent("\(name).png"))
        }
        window.close()
    }

    private static func capture(_ window: NSWindow, frame: Bool = false) -> Data? {
        guard let view = frame ? window.contentView?.superview : window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
