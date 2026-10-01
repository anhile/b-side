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
    case other
}

/// Owns the hidden WKWebView, its host window, and everything around playback.
@MainActor
final class PlayerController: NSObject, ObservableObject {
    @Published private(set) var state = PlayerState()
    @Published private(set) var phase = PlayerPhase.starting
    /// Chose to use B-Side without signing in. Cleared by signing in.
    @Published private(set) var isGuest = Settings.bool(Keys.guest) {
        didSet { Settings.defaults.set(isGuest, forKey: Keys.guest) }
    }
    /// The playlist whose tracks the Playlists page shows, if any.
    @Published private(set) var openPlaylist: Playlist?
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var tracksState = Loadable.idle
    /// The current track's lyrics, fetched when the lyrics are opened. Only
    /// the last track's are kept.
    /// The Explore page's search: what was asked, and what came back.
    @Published private(set) var searchResults: [MusicItem] = []
    @Published private(set) var searchState = Loadable.idle
    private var searchAsked: (query: String, kind: SearchKind)?
    /// The last search, so the page shows it again when it is built again.
    var lastSearch: (query: String, kind: SearchKind)? { searchAsked }
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var lyricsState = Loadable.idle
    private var tracksHaveMore = false
    private var loadingMoreTracks = false
    private var launchTrackPlayed = false
    @Published private(set) var account = Account.unknown
    @Published private(set) var source: PlaySource?
    /// The Vibe tiles, in the user's order. Saved on every change.
    @Published private(set) var moods: [Mood] = Mood.load() {
        didSet { if moods != oldValue { Mood.save(moods) } }
    }
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var playlistsState = Loadable.idle
    /// The last thing that went wrong while loading or playing, for the user.
    @Published private(set) var problem: String?
    @Published private(set) var processes: [ProcessInfoRow] = []
    /// Snapshots only: rows to show instead of the live ones.
    var processesForSnapshot: [ProcessInfoRow] = [] {
        didSet { processes = processesForSnapshot }
    }
    /// 0 to 100. Kept between launches.
    @Published var volume: Double = Settings.defaults.double(forKey: Keys.volume) {
        didSet {
            guard volume != oldValue else { return }
            Settings.defaults.set(volume, forKey: Keys.volume)
            bridge.call("volume", volume)
        }
    }
    /// Kept across launches, as YouTube Music keeps it.
    @Published var repeatMode = RepeatMode(rawValue: Settings.defaults.string(forKey: Keys.repeatMode) ?? "") ?? .off {
        didSet {
            guard repeatMode != oldValue else { return }
            Settings.defaults.set(repeatMode.rawValue, forKey: Keys.repeatMode)
            bridge.call("repeat", repeatMode.rawValue)
            EventLog.write("repeat\t\(repeatMode.rawValue)")
        }
    }

    /// Where the volume was before it was muted with the speaker button.
    private var volumeBeforeMute: Double = 100

    var totalMegabytes: Double { processes.reduce(0) { $0 + $1.megabytes } }
    var hasTrack: Bool { !state.videoID.isEmpty }

    private var webView: WKWebView!
    private let contentController = WKUserContentController()
    private var window: NSWindow!
    private let bridge = JSBridge()
    private let nowPlaying = NowPlaying()
    private var started = false
    private var webKitSessionChecked = false
    private var lastRemote: (kind: String, at: Date)?
    /// Two copies of one key press arrive well within this; two presses
    /// by hand are further apart.
    private static let remoteEchoWindow: TimeInterval = 0.3

    private var currentListID: String?
    /// When `state` arrived, to run the position forward between reports.
    private var stateDate = Date()
    /// What Play or Pause just asked for, and until when the page's reports
    /// may still say otherwise. The button and the record follow the click,
    /// not the round trip.
    private var expected: (isPlaying: Bool, until: Date)?
    private static let expectationWindow: TimeInterval = 1.5
    /// Set while the page is unloaded by "free memory when paused".
    private var unloaded: (target: PlayTarget, position: Double)?
    /// Whether the page has reported its player ready, and what to play once
    /// it has.
    private var pageReady = false
    private var pendingTarget: (target: PlayTarget, position: Double?)?
    private var signingIn = false
    private var pauseTimer: Timer?
    private var processTimer: Timer?
    private var playbackActivity: NSObjectProtocol?
    private var sampleCount = 0
    private var lastHeartbeatPosition: Double = -1

    // MARK: - Setup

    /// For design snapshots (see Snapshots.swift): a controller that shows a
    /// given situation and never starts the web view.
    static func fixture(state: PlayerState = PlayerState(), account: Account = .signedIn(name: "", handle: "@bside"),
                        phase: PlayerPhase = .ready, source: PlaySource? = nil,
                        playlists: [Playlist] = [], playlistsState: Loadable = .loaded,
                        problem: String? = nil, volume: Double = 70,
                        moods: [Mood] = [.liked], isGuest: Bool = false, openPlaylist: Playlist? = nil,
                        tracks: [Track] = [], tracksState: Loadable = .idle,
                        lyrics: Lyrics? = nil, search: (String, [MusicItem])? = nil,
                        searchState: Loadable = .idle, artist: ArtistPage? = nil,
                        collection: CollectionPage? = nil) -> PlayerController {
        let controller = PlayerController()
        controller.started = true
        controller.moods = moods
        controller.state = state
        controller.stateDate = Date()
        controller.account = account
        controller.phase = phase
        controller.source = source
        controller.playlists = playlists
        controller.playlistsState = playlistsState
        controller.isGuest = isGuest
        controller.openPlaylist = openPlaylist
        controller.tracks = tracks
        controller.tracksState = tracksState
        controller.lyrics = lyrics
        if let search {
            controller.searchAsked = (search.0, .songs)
            controller.searchResults = search.1
        }
        controller.searchState = searchState
        if let artist { controller.artistPages[artist.id] = artist }
        if let collection { controller.collectionPages[collection.id] = collection }
        controller.lyricsState = lyrics == nil ? .idle : .loaded
        if let lyrics { controller.lyricsCache[lyrics.videoID] = lyrics }
        controller.problem = problem
        controller.volume = volume
        return controller
    }

    func start() {
        guard !started else { return }
        started = true
        EventLog.write("launch")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default() // persistent cookies, so sign-in survives relaunch
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.inactiveSchedulingPolicy = Tuning.inactiveScheduling

        bridge.onState = { [weak self] in self?.handle(state: $0) }
        bridge.onEvent = { [weak self] in self?.handle(event: $0, detail: $1) }
        bridge.onAccount = { [weak self] in self?.handle(account: $0) }
        bridge.onLyrics = { [weak self] in self?.receive(lyrics: $0) }
        bridge.onArtist = { [weak self] in self?.receive(artist: $0, page: $1) }
        bridge.onCollection = { [weak self] in self?.receive(collection: $0, page: $1) }
        bridge.onSearch = { [weak self] query, kind, items in
            guard let self, let asked = searchAsked, asked.query == query, asked.kind == kind else { return }
            searchResults = items
            searchState = .loaded
        }
        bridge.onTracks = { [weak self] listID, items, append, more in
            self?.receive(tracks: items, of: listID, append: append, more: more)
        }
        bridge.onRemote = { [weak self] action, seconds in
            let command: NowPlaying.Command? = switch action {
            case "play": .play
            case "pause", "stop": .pause
            case "nexttrack": .next
            case "previoustrack": .previous
            case "seekto": seconds.map { .seek($0) }
            default: nil
            }
            if let command { self?.receive(command, via: "page") }
        }
        bridge.onPlaylists = { [weak self] in
            self?.playlists = $0
            self?.playlistsState = .loaded
        }
        installScripts()

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720), configuration: configuration)
        webView.customUserAgent = Tuning.userAgent
        webView.isInspectable = Tuning.inspectable
        webView.navigationDelegate = self
        webView.uiDelegate = self
        bridge.webView = webView

        // The web view lives in a real window that is simply never ordered
        // front. Sign-in and debugging show this same window.
        window = NSWindow(contentRect: webView.frame,
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "B-Side Player Page"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        window.center()

        nowPlaying.onCommand = { [weak self] in self?.receive($0, via: "system") }
        MainWindow.onShow = { [weak self] in self?.wake() }
        applyNowPlayingSetting()

        sampleProcesses()
        processTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleProcesses() }
        }

        Task {
            // The rules must be in place before the first request goes out.
            await installContentRules()
            if let text = Settings.defaults.string(forKey: Keys.url), let url = URL(string: text) {
                EventLog.write("debug url\t\(text)")
                webView.load(URLRequest(url: url))
            } else if Settings.bool(Keys.vibe) {
                // `-vibe YES` and `-play <id>` on the command line start
                // playback right away, for scripted test runs.
                playVibe()
            } else if let input = Settings.defaults.string(forKey: Keys.play), let target = PlayTarget(input) {
                load(target, from: .other, startAt: nil)
            } else {
                // Wait for the launch to be classified: AppDelegate knows
                // whether this is a start in the menu bar.
                MainWindow.whenLaunched { [weak self] inMenuBar in
                    guard let self, self.phase == .starting, self.pendingTarget == nil else { return }
                    if inMenuBar {
                        self.phase = .asleep
                        EventLog.write("page deferred until Play or the window")
                    } else {
                        self.loadHome()
                    }
                }
            }
        }
    }

    /// Loads the page after a start in the menu bar. The first Play does it
    /// through `load`; showing the window or the menu does it here, since
    /// the user is about to look at the account, playlists or Vibe tiles.
    func wake() {
        guard phase == .asleep else { return }
        EventLog.write("wake")
        loadHome()
    }

    /// The page is loading and there is nothing else to show yet: the window
    /// shows the welcome screen instead of empty pages.
    var showsWelcome: Bool {
        !hasTrack && (phase == .asleep || phase == .starting)
    }

    private func installScripts() {
        bridge.install(in: contentController, pageConfig: [
            "muted": Settings.bool(Keys.muted),
            "startIndex": Settings.defaults.integer(forKey: Keys.startIndex),
            "audioOnly": Settings.bool(Keys.forceAudioOnly),
        ])
    }

    private func installContentRules() async {
        contentController.removeAllContentRuleLists()
        do {
            contentController.add(try await ContentRules.compile())
        } catch {
            EventLog.write("error\trules: \(error.localizedDescription)")
        }
    }

    /// Applies a changed page setting (audio only) without relaunching. The
    /// current track resumes where it was.
    func applyPageSettings() {
        installScripts()
        rememberTrack(at: position(at: Date()))
        loadHome()
    }

    /// An empty document with YouTube Music's origin: cookies and same-origin
    /// requests work, and none of the site's own scripts or markup are ever
    /// loaded. player.js does the rest. Never call `webView.reload()`: that
    /// would fetch the base URL, the real home page.
    private func loadHome() {
        phase = .starting
        webView.loadHTMLString(Tuning.emptyPage, baseURL: Tuning.musicHome)
    }

    /// Starts the player page again after it failed to start.
    func retry() {
        problem = nil
        loadHome()
    }

    func applyNowPlayingSetting() {
        nowPlaying.setEnabled(Settings.bool(Keys.nativeNowPlaying))
    }

    /// The page is about to be replaced: play the same track again once the
    /// new one is ready.
    private func rememberTrack(at position: Double) {
        guard hasTrack, pendingTarget == nil else { return }
        pendingTarget = (PlayTarget(videoID: state.videoID, listID: currentListID), position)
    }

    // MARK: - Commands

    /// Liked Music in random order: the first tile, and what Play does when
    /// nothing is loaded. A guest gets the first tile that needs no account.
    func playVibe() {
        if let mood = vibeMood {
            play(mood)
        } else {
            problem = "Sign in to play Liked Music, or add a vibe from a track."
        }
    }

    /// What Play Vibe starts. While the account is not known yet (right
    /// after launch) it is Liked Music, unless the user chose to be a guest.
    var vibeMood: Mood? {
        if account.isSignedIn || (account == .unknown && !isGuest) { return .liked }
        return moods.first { !$0.needsAccount }
    }

    func continueAsGuest() {
        isGuest = true
        EventLog.write("account\tguest")
    }

    func play(_ mood: Mood) {
        load(mood.target, from: .mood(mood.id), startAt: nil)
    }

    /// Adds a tile, or replaces the one with the same id.
    func save(_ mood: Mood) {
        if let index = moods.firstIndex(where: { $0.id == mood.id }) {
            moods[index] = mood
        } else {
            moods.append(mood)
        }
    }

    func remove(_ mood: Mood) {
        moods.removeAll { $0.id == mood.id }
    }

    func play(_ playlist: Playlist) {
        load(PlayTarget(videoID: nil, listID: playlist.id), from: .playlist(playlist.id), startAt: nil)
    }

    func play() {
        if let unloaded {
            load(unloaded.target, from: source ?? .other, startAt: unloaded.position)
        } else {
            bridge.call("play")
            assume(playing: true)
        }
    }

    func pause() {
        bridge.call("pause")
        assume(playing: false)
    }

    /// Likes the current track, or takes the like back. Shown at once; the
    /// page confirms.
    func toggleLike() {
        guard hasTrack else { return }
        let on = !state.isLiked
        bridge.call("like", state.videoID, on)
        state.like = on ? "LIKE" : "INDIFFERENT"
    }

    private func assume(playing: Bool) {
        guard hasTrack else { return }
        expected = (playing, Date().addingTimeInterval(Self.expectationWindow))
        guard state.isPlaying != playing else { return }
        state.isPlaying = playing
        stateDate = Date()
        nowPlaying.update(state)
        playingChanged(playing)
    }
    func next() { bridge.call("next") }
    func previous() { bridge.call("previous") }

    func seek(to seconds: Double) {
        bridge.call("seek", seconds)
        // Shown at once; the page confirms with its next report.
        state.position = seconds
        stateDate = Date()
        nowPlaying.update(state)
    }

    /// With nothing loaded, Play starts Vibe, so the media keys work right
    /// after launch.
    func togglePlayPause() {
        if !hasTrack, unloaded == nil {
            playVibe()
        } else {
            state.isPlaying ? pause() : play()
        }
    }

    func toggleMute() {
        if volume > 0 {
            volumeBeforeMute = volume
            volume = 0
        } else {
            volume = volumeBeforeMute > 0 ? volumeBeforeMute : 100
        }
    }

    /// One menu command's worth, in percent.
    static let volumeStep: Double = 10

    func adjustVolume(by step: Double) {
        volume = min(100, max(0, volume + step))
    }

    /// The page reports its position every few seconds; in between, time runs.
    func position(at date: Date) -> Double {
        guard state.isPlaying else { return state.position }
        let running = state.position + date.timeIntervalSince(stateDate)
        return state.duration > 0 ? min(running, state.duration) : running
    }

    /// Asks the page for the signed-in user's playlists.
    // MARK: - Playlists

    /// A library subtitle reads "Author • 19 tracks". The author is left out
    /// when it is the user: the account's name, or whoever made most of the
    /// library. Playlists saved from someone else keep theirs.
    func subtitle(of playlist: Playlist) -> String {
        let parts = playlist.subtitle.components(separatedBy: Self.subtitleSeparator)
        guard parts.count > 1, let author = parts.first, isOwnName(author) else { return playlist.subtitle }
        return parts.dropFirst().joined(separator: Self.subtitleSeparator)
    }

    private static let subtitleSeparator = " • "

    private func isOwnName(_ author: String) -> Bool {
        if case .signedIn(let name, _, _) = account, !name.isEmpty, name == author { return true }
        return author == libraryAuthor
    }

    /// The author of most playlists in the library, if there is one that
    /// made at least two of them.
    private var libraryAuthor: String? {
        let authors = playlists.compactMap { playlist -> String? in
            let parts = playlist.subtitle.components(separatedBy: Self.subtitleSeparator)
            return parts.count > 1 ? parts.first : nil
        }
        let counts = Dictionary(authors.map { ($0, 1) }, uniquingKeysWith: +)
        guard let top = counts.max(by: { $0.value < $1.value }), top.value >= 2 else { return nil }
        return top.key
    }

    // MARK: - Lyrics

    /// Whether the current track has lyrics: nil until known. Known soon
    /// after each track starts, since the text is asked for then (about 30 KB,
    /// against 3 to 4 MB of audio); the timings only when the lyrics are shown.
    var lyricsAvailable: Bool? {
        if case .failed = lyricsState { return false }
        guard let lyrics, lyrics.videoID == state.videoID, lyricsState == .loaded else { return nil }
        return !lyrics.isEmpty
    }

    /// Asks for the current track's lyrics text, unless it is here already.
    /// The page finds the text and the lyrics page; a track YouTube Music
    /// has no text for is looked up on LRCLIB. Kept for the session.
    func loadLyrics() {
        let video = state.videoID
        guard !video.isEmpty, !state.isAd, pageReady else { return }
        if lyrics?.videoID == video, lyricsState == .loaded { return }
        if lyricsState == .loading, lyricsRequested == video { return }
        if let known = lyricsCache[video] {
            lyrics = known
            lyricsState = .loaded
            return
        }
        lyrics = nil
        lyricsState = .loading
        lyricsRequested = video
        bridge.call("lyrics", video)
    }

    /// The timings for the lyrics on screen. YouTube Music times only what it
    /// has text for, so without text it is not asked.
    func loadTimedLyrics() {
        guard var current = lyrics, current.videoID == state.videoID, lyricsState == .loaded,
              !current.timedTried, !current.text.isEmpty, timedRequested != current.videoID else { return }
        timedRequested = current.videoID
        let title = state.title, artist = state.artist, duration = state.duration
        Task {
            if let timed = await TimedLyrics.find(page: current.page, title: title, artist: artist, duration: duration) {
                current.lines = timed.lines
                if !timed.source.isEmpty { current.source = timed.source }
            }
            current.timedTried = true
            timedRequested = ""
            keep(current)
        }
    }

    private var lyricsRequested = ""
    private var timedRequested = ""

    private func receive(lyrics found: Lyrics) {
        guard found.videoID == state.videoID else { return } // the track moved on
        guard found.text.isEmpty else { return keep(found) }
        let title = state.title, artist = state.artist, duration = state.duration
        Task {
            var found = found
            if let timed = await TimedLyrics.lrclib(title: title, artist: artist, duration: duration) {
                found.lines = timed.lines
                found.source = timed.source
                found.text = timed.lines.map(\.text).joined(separator: "\n")
            }
            found.timedTried = true
            keep(found)
        }
    }

    /// Into the session's cache, and on screen if the track still plays.
    private func keep(_ found: Lyrics) {
        if lyricsCache[found.videoID] == nil {
            lyricsOrder.append(found.videoID)
            if lyricsOrder.count > Self.lyricsCacheSize {
                lyricsCache[lyricsOrder.removeFirst()] = nil
            }
        }
        lyricsCache[found.videoID] = found
        guard found.videoID == state.videoID else { return }
        lyrics = found
        lyricsState = .loaded
    }

    private var lyricsCache: [String: Lyrics] = [:]
    private var lyricsOrder: [String] = []
    /// A few hours of listening; a track's lyrics are a few KB.
    private static let lyricsCacheSize = 100

    // MARK: - Search

    /// Searches YouTube Music; an empty query clears the results. Wakes the
    /// player page if it sleeps, and asks once it is ready.
    func search(_ query: String, kind: SearchKind) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchAsked = nil
            searchResults = []
            searchState = .idle
            return
        }
        if let asked = searchAsked, asked.query == query, asked.kind == kind,
           searchState == .loading || searchState == .loaded { return }
        searchAsked = (query, kind)
        searchState = .loading
        if pageReady { bridge.call("search", query, kind.rawValue) } else { wake() } // "ready" asks
    }

    func retrySearch() {
        guard let asked = searchAsked else { return }
        searchAsked = nil
        search(asked.query, kind: asked.kind)
    }

    /// A song plays with its radio after it, as in YouTube Music; an album
    /// or playlist plays from its first track.
    func play(_ item: MusicItem) {
        if !item.videoID.isEmpty {
            load(PlayTarget(videoID: item.videoID, listID: nil), from: .other, startAt: nil)
        } else if !item.playlistID.isEmpty {
            load(PlayTarget(videoID: nil, listID: item.playlistID), from: .playlist(item.playlistID), startAt: nil)
        }
    }

    /// An album or playlist from one of its tracks on.
    func play(_ collection: CollectionPage, from index: Int = 0) {
        play(list: collection.playlistID, from: index)
    }

    /// A playlist from one of its tracks on: an album, or all of an artist's
    /// songs, which their top songs are the start of.
    func play(list id: String, from index: Int) {
        guard !id.isEmpty else { return }
        load(PlayTarget(videoID: nil, listID: id, startIndex: index), from: .playlist(id), startAt: nil)
    }

    // MARK: - Artist and album pages

    /// Loaded pages stay for the session, so going back shows them at once.
    @Published private(set) var artistPages: [String: ArtistPage] = [:]
    @Published private(set) var collectionPages: [String: CollectionPage] = [:]
    @Published private(set) var exploreFailures: Set<String> = []
    private var exploreAsked: Set<String> = []

    func loadArtist(_ id: String) {
        guard artistPages[id] == nil, !exploreAsked.contains(id) else { return }
        exploreAsked.insert(id)
        exploreFailures.remove(id)
        if pageReady { bridge.call("artist", id) } else { wake() } // "ready" asks
    }

    func loadCollection(_ id: String) {
        guard collectionPages[id] == nil, !exploreAsked.contains(id) else { return }
        exploreAsked.insert(id)
        exploreFailures.remove(id)
        if pageReady { bridge.call("collection", id) } else { wake() }
    }

    func retryExplorePage(_ id: String) {
        exploreAsked.remove(id)
        id.hasPrefix("UC") ? loadArtist(id) : loadCollection(id)
    }

    private func receive(artist id: String, page: ArtistPage?) {
        exploreAsked.remove(id)
        if let page { artistPages[id] = page } else { exploreFailures.insert(id) }
    }

    private func receive(collection id: String, page: CollectionPage?) {
        exploreAsked.remove(id)
        if let page { collectionPages[id] = page } else { exploreFailures.insert(id) }
    }

    // MARK: - A playlist's tracks

    func open(_ playlist: Playlist) {
        openPlaylist = playlist
        tracks = []
        tracksHaveMore = false
        loadingMoreTracks = false
        tracksState = .loading
        if pageReady { bridge.call("tracks", playlist.id) } // otherwise "ready" asks
    }

    func closePlaylist() {
        openPlaylist = nil
        tracks = []
        tracksState = .idle
    }

    func retryTracks() {
        if let openPlaylist { open(openPlaylist) }
    }

    /// Called as the list nears its end.
    func loadMoreTracks() {
        guard tracksHaveMore, !loadingMoreTracks, pageReady else { return }
        loadingMoreTracks = true
        bridge.call("moreTracks")
    }

    private func receive(tracks items: [Track], of listID: String, append: Bool, more: Bool) {
        guard listID == openPlaylist?.id else { return } // an answer for a list closed meanwhile
        defer { playTrackFromLaunchArgument() }
        let start = append ? tracks.count : 0
        let numbered = items.enumerated().map { offset, track in
            Track(index: start + offset, videoID: track.videoID, title: track.title,
                  artist: track.artist, artworkURL: track.artworkURL)
        }
        tracks = append ? tracks + numbered : numbered
        tracksHaveMore = more
        loadingMoreTracks = false
        tracksState = .loaded
    }

    /// `-listTracks <id> -playTrack <n>`, for scripted test runs.
    private func playTrackFromLaunchArgument() {
        guard Settings.defaults.object(forKey: Keys.playTrack) != nil, !launchTrackPlayed else { return }
        launchTrackPlayed = true
        let index = Settings.defaults.integer(forKey: Keys.playTrack)
        if tracks.indices.contains(index) { playOpenPlaylist(from: tracks[index]) }
    }

    /// Plays the open playlist from one of its tracks, in the list's order.
    func playOpenPlaylist(from track: Track) {
        guard let playlist = openPlaylist else { return }
        guard pageReady else { return play(playlist) } // the list lives in the page
        unloaded = nil
        problem = nil
        source = .playlist(playlist.id)
        currentListID = playlist.id
        EventLog.write("load\t\(track.videoID)\t\(playlist.id)\tfrom track \(track.index + 1)")
        bridge.call("playListing", playlist.id, track.index)
    }

    func loadPlaylists() {
        guard pageReady else { return }
        if playlists.isEmpty { playlistsState = .loading }
        bridge.call("playlists")
    }

    private func load(_ target: PlayTarget, from newSource: PlaySource, startAt position: Double?) {
        unloaded = nil
        problem = nil
        source = newSource
        currentListID = target.listID
        EventLog.write("load\t\(target.videoID ?? "-")\t\(target.listID ?? "-")\(target.shuffle ? "\tshuffle" : "")")
        if pageReady {
            sendToPage(target, startAt: position)
        } else {
            pendingTarget = (target, position)
            if webView.url?.host != Tuning.musicHome.host { loadHome() }
        }
    }

    private func sendToPage(_ target: PlayTarget, startAt position: Double?) {
        // Resuming a track wins over restarting its playlist from the top.
        if let video = target.videoID, position != nil || target.listID == nil {
            bridge.call("load", "video", video, position ?? 0)
        } else if let list = target.listID {
            bridge.call("load", "playlist", list, 0, ["shuffle": target.shuffle, "startIndex": target.startIndex])
        }
    }

    /// A command from a media key, AirPods or Control Center. It comes
    /// either straight from the system or through WebKit and the page; one
    /// press may arrive both ways, so the second copy is dropped.
    private func receive(_ command: NowPlaying.Command, via path: String) {
        let kind = switch command {
        case .play, .pause, .toggle: "play/pause"
        default: "\(command)"
        }
        let now = Date()
        if let last = lastRemote, last.kind == kind, now.timeIntervalSince(last.at) < Self.remoteEchoWindow {
            EventLog.write("remote\t\(path) \(command), same press, ignored")
            return
        }
        lastRemote = (kind, now)
        EventLog.write("remote\t\(path) \(command)")
        handle(command: command)
    }

    private func handle(command: NowPlaying.Command) {
        switch command {
        case .play: if !state.isPlaying { togglePlayPause() }
        case .pause: pause()
        case .toggle: togglePlayPause()
        case .next: next()
        case .previous: previous()
        case .seek(let seconds): seek(to: seconds)
        }
    }

    // MARK: - Account

    func showSignIn() {
        signingIn = true
        window.title = "Sign in to YouTube Music"
        webView.load(URLRequest(url: Tuning.signIn))
        showWebView()
    }

    /// Removes every cookie and cache of the web view, which signs out.
    func signOut() {
        EventLog.write("sign out")
        pause()
        pendingTarget = nil
        unloaded = nil
        source = nil
        currentListID = nil
        state = PlayerState()
        nowPlaying.update(state)
        playlists = []
        playlistsState = .idle
        account = .signedOut
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
        ) { [weak self] in
            Task { @MainActor in self?.loadHome() }
        }
    }

    /// The player's window, shown for Google's sign-in page.
    func showWebView() {
        window.makeKeyAndOrderFront(nil)
    }

    func hideWebView() {
        window.orderOut(nil)
        window.title = "B-Side Player Page"
        // Coming back from the sign-in flow: return to the player page.
        if signingIn || (webView.url?.host != Tuning.musicHome.host && unloaded == nil) {
            signingIn = false
            loadHome()
        }
    }

    // MARK: - Page messages

    private func handle(state new: PlayerState) {
        guard unloaded == nil else { return }
        var new = new
        if let expected {
            if Date() < expected.until, new.isPlaying != expected.isPlaying {
                new.isPlaying = expected.isPlaying // the page has not caught up yet
            } else {
                self.expected = nil
            }
        }
        let old = state
        state = new
        stateDate = Date()
        nowPlaying.update(new)

        // The title arrives a moment after the video ID, so wait for it.
        if !new.title.isEmpty, new.videoID != old.videoID || new.title != old.title {
            EventLog.write("track\t\(new.videoID)\t\(new.artist) - \(new.title)")
            TrackNotifier.shared.trackStarted(new)
            if !new.isAd { loadLyrics() } // so Lyrics shows only for a track that has them
        }
        if new.isAd, !old.isAd {
            EventLog.write("ad")
        }
        if new.isPlaying != old.isPlaying {
            playingChanged(new.isPlaying)
        }
        if new.isPlaying, !webKitSessionChecked {
            webKitSessionChecked = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let webView = self?.webView else { return }
                let answer = WebKitNowPlaying.hasSession(webView).map { $0 ? "yes" : "no" } ?? "unknown"
                EventLog.write("remote\tWebKit now-playing session: \(answer)")
            }
        }
    }

    private func handle(account new: Account) {
        // The name arrives after the first "signed in"; keep it across page
        // reloads, which report "signed in" without a name again.
        if case .signedIn(let name, let handle, _) = new, name.isEmpty, handle.isEmpty, account.isSignedIn { return }
        if new != account {
            // The name itself stays out of the log.
            switch new {
            case .signedIn(let name, _, _):
                EventLog.write("account\tsigned in, \(name.isEmpty ? "no name yet" : "name received")")
            default: EventLog.write("account\tsigned out")
            }
        }
        account = new
        if new.isSignedIn {
            Settings.defaults.set(true, forKey: Keys.wasSignedIn)
            isGuest = false
        }
        if !new.isSignedIn {
            playlists = []
            playlistsState = .idle
        }
    }

    private func handle(event kind: String, detail: String) {
        switch kind {
        case "ready":
            phase = .ready
            pageReady = true
            bridge.call("volume", volume)
            bridge.call("repeat", repeatMode.rawValue)
            if account.isSignedIn { loadPlaylists() }
            if let openPlaylist, tracksState == .loading { bridge.call("tracks", openPlaylist.id) }
            if let asked = searchAsked, searchState == .loading { bridge.call("search", asked.query, asked.kind.rawValue) }
            for id in exploreAsked { bridge.call(id.hasPrefix("UC") ? "artist" : "collection", id) }
            if openPlaylist == nil, let id = Settings.defaults.string(forKey: Keys.listTracks) {
                open(Playlist(id: id, title: id))
            }
            if let pending = pendingTarget {
                pendingTarget = nil
                sendToPage(pending.target, startAt: pending.position)
            }
        case "error":
            EventLog.write("error\t\(detail)")
            // player.js starts every error with the step that failed.
            if detail.hasPrefix("boot") {
                phase = .failed("YouTube Music could not be loaded. Check the connection and try again.")
            } else if detail.hasPrefix("search") {
                searchState = .failed("The search did not go through. Check the connection and try again.")
            } else if detail.hasPrefix("lyrics") {
                lyricsState = .failed("The lyrics could not be loaded.")
            } else if detail.hasPrefix("tracks") {
                loadingMoreTracks = false
                if tracks.isEmpty { tracksState = .failed("The tracks of this playlist could not be loaded.") }
            } else if detail.hasPrefix("playlists") {
                playlistsState = .failed("The list of playlists could not be loaded.")
            } else if detail.hasPrefix("load") {
                problem = "This could not be played. It may be empty or unavailable."
            } else if detail.hasPrefix("player error") {
                problem = "This track could not be played."
            } else if detail.hasPrefix("like") {
                problem = "The like could not be saved."
            }
        default:
            EventLog.write("\(kind)\t\(detail)")
        }
    }

    private func playingChanged(_ isPlaying: Bool) {
        EventLog.write(isPlaying ? "playing" : "paused\t\(Int(state.position))s")
        if isPlaying { problem = nil }

        // Keep App Nap away from this process while music plays.
        if isPlaying, playbackActivity == nil {
            playbackActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Audio playback")
        } else if !isPlaying, let activity = playbackActivity {
            ProcessInfo.processInfo.endActivity(activity)
            playbackActivity = nil
        }

        pauseTimer?.invalidate()
        pauseTimer = nil
        if !isPlaying, Settings.bool(Keys.reloadWhenPaused) {
            let minutes = max(1, Settings.defaults.integer(forKey: Keys.reloadAfterMinutes))
            pauseTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.unloadAfterPause(minutes: minutes) }
            }
        }
    }

    /// Memory reclaim: drop the page, remember where playback was, and load
    /// it again on the next Play.
    private func unloadAfterPause(minutes: Int) {
        guard !state.isPlaying, hasTrack else { return }
        unloaded = (PlayTarget(videoID: state.videoID, listID: currentListID), state.position)
        EventLog.write("unloaded after \(minutes) min paused")
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    private func sampleProcesses() {
        let rows = ProcessReporter.snapshot()
        ProcessReporter.write(rows)
        processes = rows

        // Once a minute, record where playback is. A position that stops
        // advancing while "playing" is a silent stop.
        sampleCount += 1
        if sampleCount % 12 == 0 {
            let stalled = state.isPlaying && state.position == lastHeartbeatPosition
            EventLog.write("\(stalled ? "STALLED" : "heartbeat")\t\(state.isPlaying ? "playing" : "paused")\t"
                + "\(Int(state.position))s\t\(state.videoID)\t\(Int(totalMegabytes)) MB")
            lastHeartbeatPosition = state.position
        }
    }
}

// MARK: - WebKit delegates

extension PlayerController: WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pageReady = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Google sends the browser back to YouTube Music once sign-in is done.
        if signingIn, webView.url?.host == Tuning.musicHome.host {
            EventLog.write("sign-in flow finished")
            hideWebView()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(navigationError: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(navigationError: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        EventLog.write("crash\tWebContent process terminated")
        rememberTrack(at: state.position)
        state.isPlaying = false
        nowPlaying.update(state)
        loadHome()
    }

    /// Google's sign-in flow sometimes opens a new window; keep it in this one.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWebView()
        return false
    }

    private func report(navigationError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        EventLog.write("error\tnavigation: \(error.localizedDescription)")
    }
}
