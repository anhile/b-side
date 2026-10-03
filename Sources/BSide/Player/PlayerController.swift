import AppKit
import Combine
import Network
import WebKit

/// Owns the hidden WKWebView, its host window, and everything around playback.
@MainActor
final class PlayerController: NSObject, ObservableObject {
    // MARK: - What plays

    @Published private(set) var state = PlayerState() {
        didSet { if state != oldValue { WidgetFeed.note(self) } }
    }
    /// Where playback is between the page's reports; see PlaybackClock.
    @Published private(set) var clock = PlaybackClock()
    @Published private(set) var source: PlaySource? {
        didSet { if source != oldValue { WidgetFeed.note(self) } }
    }
    /// A track or list was asked for and the page has not answered yet.
    @Published private(set) var isLoading = false
    /// The music has waited for data for a while (Tuning.bufferingNoticeSeconds).
    @Published private(set) var showsBuffering = false
    /// What plays after the current track, in order; a track's `index` is
    /// its place in the page's queue.
    @Published private(set) var upNext: [Track] = []
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
    /// Likes set and taken back here, by video ID, since the app started.
    @Published private(set) var likeChanges: [String: Bool] = [:]

    var hasTrack: Bool { !state.videoID.isEmpty }

    // MARK: - The page and the account

    @Published private(set) var phase = PlayerPhase.starting {
        didSet { if phase != .starting { startWaitTask?.cancel() } }
    }
    @Published private(set) var startWait = StartWait.short
    @Published private(set) var account = Account.unknown
    /// Chose to use B-Side without signing in. Cleared by signing in.
    @Published private(set) var isGuest = Settings.bool(Keys.guest) {
        didSet { Settings.defaults.set(isGuest, forKey: Keys.guest) }
    }
    /// The last thing that went wrong while loading or playing, for the user.
    @Published private(set) var problem: String?
    /// A short word that something was done, such as "Added to Road trip";
    /// gone after a moment.
    @Published private(set) var notice: String?

    // MARK: - The library: vibes, playlists, a playlist's tracks

    /// The Vibe tiles, in the user's order. Saved on every change.
    @Published private(set) var moods: [Mood] = Mood.load() {
        didSet { if moods != oldValue { Mood.save(moods) } }
    }
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var playlistsState = Loadable.idle
    /// The user's playlists that hold a track, by video ID: the checkmarks
    /// in Add to Playlist. Asked again each time the menu opens.
    @Published private(set) var playlistsHolding: [String: Set<String>] = [:]
    /// The playlist whose tracks the Playlists page shows, if any.
    @Published private(set) var openPlaylist: Playlist?
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var tracksState = Loadable.idle

    // MARK: - Explore and lyrics

    /// The Explore page's search: what came back, and what was asked.
    @Published private(set) var searchResults: [MusicItem] = []
    @Published private(set) var searchState = Loadable.idle
    /// The last search, so the page shows it again when it is built again.
    var lastSearch: (query: String, kind: SearchKind)? { searchAsked }
    /// The current track's lyrics, fetched when the lyrics are opened. Only
    /// the last track's are kept.
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var lyricsState = Loadable.idle

    // MARK: - Diagnostics

    @Published private(set) var processes: [ProcessInfoRow] = []
    /// Snapshots only: rows to show instead of the live ones.
    var processesForSnapshot: [ProcessInfoRow] = [] {
        didSet { processes = processesForSnapshot }
    }
    var totalMegabytes: Double { processes.reduce(0) { $0 + $1.megabytes } }

    // MARK: - Kept to itself

    private var webView: WKWebView!
    private let contentController = WKUserContentController()
    private var window: NSWindow!
    private let bridge = JSBridge()
    private let nowPlaying = NowPlaying()
    private var started = false
    /// Whether the page has reported its player ready, and what to play once
    /// it has.
    private var pageReady = false
    private var pendingTarget: (target: PlayTarget, position: Double?)?
    private var startWaitTask: Task<Void, Never>?
    private var signingIn = false
    /// Set while the page is unloaded by "free memory when paused".
    private var unloaded: (target: PlayTarget, position: Double)?
    /// Next (1) or Previous (-1) pressed on a track that waits for Play.
    private var skipAfterLoad = 0
    private var bufferingTask: Task<Void, Never>?
    /// Starts the page again when the network comes back after a failed start.
    private let pathMonitor = NWPathMonitor()

    /// What Play or Pause just asked for, and until when the page's reports
    /// may still say otherwise. The button and the record follow the click,
    /// not the round trip.
    private var expected: (isPlaying: Bool, until: Date)?
    private static let expectationWindow: TimeInterval = 1.5
    /// Where the volume was before it was muted with the speaker button.
    private var volumeBeforeMute: Double = 100
    private var lastRemote: (kind: String, at: Date)?
    /// Two copies of one key press arrive well within this; two presses
    /// by hand are further apart.
    private static let remoteEchoWindow: TimeInterval = 0.3
    private var webKitSessionChecked = false

    private var currentListID: String?
    private var currentShuffle = false
    private var savedSession: LastSession?
    /// Names of lists played from Explore, which are not in the library.
    /// What a list ID stands for, for the source line: its title and kind,
    /// and where its page is (an album's browse ID, an artist's channel).
    private var listTitles: [String: (title: String, kind: SourceLabel.Kind, page: String)] = [:]
    private var playlistsAsked = Date.distantPast
    private var askingHolding: Set<String> = []
    private var tracksHaveMore = false
    private var loadingMoreTracks = false
    private var launchTrackPlayed = false
    private var searchAsked: (query: String, kind: SearchKind)?
    private var noticeTask: Task<Void, Never>?

    private var pauseTimer: Timer?
    private var processTimer: Timer?
    private var playbackActivity: NSObjectProtocol?
    private var sampleCount = 0
    private var lastHeartbeatPosition: Double = -1

    // MARK: - Setup

    /// For design snapshots (see Snapshots.swift): a controller that shows a
    /// given situation and never starts the web view.
    static func fixture(state: PlayerState = PlayerState(), account: Account = .signedIn(name: "", handle: "@bside"),
                        phase: PlayerPhase = .ready, startWait: StartWait = .short, source: PlaySource? = nil,
                        playlists: [Playlist] = [], playlistsState: Loadable = .loaded,
                        problem: String? = nil, volume: Double = 70, buffering: Bool = false,
                        moods: [Mood] = [.liked], isGuest: Bool = false, openPlaylist: Playlist? = nil,
                        tracks: [Track] = [], tracksState: Loadable = .idle,
                        lyrics: Lyrics? = nil, upNext: [Track] = [], search: (String, [MusicItem])? = nil,
                        searchState: Loadable = .idle, artist: ArtistPage? = nil,
                        collection: CollectionPage? = nil) -> PlayerController {
        let controller = PlayerController()
        controller.started = true
        controller.moods = moods
        controller.state = state
        controller.clock = PlaybackClock(state, at: Date())
        controller.account = account
        controller.phase = phase
        controller.startWait = startWait
        controller.source = source
        controller.playlists = playlists
        controller.playlistsState = playlistsState
        controller.isGuest = isGuest
        controller.openPlaylist = openPlaylist
        controller.tracks = tracks
        controller.tracksState = tracksState
        controller.lyrics = lyrics
        controller.upNext = upNext
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
        controller.showsBuffering = buffering
        return controller
    }

    func start() {
        guard !started else { return }
        started = true
        EventLog.write("launch")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default() // persistent cookies, so sign-in survives relaunch
        Net.apply(to: configuration.websiteDataStore)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.inactiveSchedulingPolicy = Tuning.inactiveScheduling

        bridge.onState = { [weak self] in self?.handle(state: $0) }
        WidgetFeed.start { [weak self] in self?.perform($0) }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self, case .failed = self.phase else { return }
                EventLog.write("net\tback; starting the page again")
                self.retry()
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))
        bridge.onEvent = { [weak self] in self?.handle(event: $0, detail: $1) }
        bridge.onAccount = { [weak self] in self?.handle(account: $0) }
        bridge.onLyrics = { [weak self] in self?.receive(lyrics: $0) }
        bridge.onUpNext = { [weak self] in self?.upNext = $0 }
        bridge.onArtist = { [weak self] in self?.receive(artist: $0, page: $1) }
        bridge.onCollection = { [weak self] in self?.receive(collection: $0, page: $1) }
        bridge.onSearch = { [weak self] query, kind, items in
            guard let self, let asked = searchAsked, asked.query == query, asked.kind == kind else { return }
            searchResults = items
            searchState = .loaded
        }
        bridge.onTracks = { [weak self] listID, items, append, more in
            if items.contains(where: \.removable) { self?.ownedPlaylistIDs.insert(listID) }
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
        bridge.onPlaylistEdit = { [weak self] in self?.playlistEdited($0, id: $1, title: $2, videoID: $3) }
        bridge.onPlaylists = { [weak self] in self?.receive(playlists: $0) }
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
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSession() }
        }
        MainWindow.onShow = { [weak self] in self?.wake() }
        applyNowPlayingSetting()

        sampleProcesses()
        processTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleProcesses() }
        }

        Task { [self] in
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
                restoreSession()
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
        startWait = .short
        startWaitTask?.cancel()
        startWaitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.startSlowSeconds))
            guard !Task.isCancelled else { return }
            self?.startWait = .long
            try? await Task.sleep(for: .seconds(Tuning.startRetrySeconds - Tuning.startSlowSeconds))
            guard !Task.isCancelled else { return }
            self?.startWait = .tooLong
            EventLog.write("error\tstart: the page is not ready after \(Int(Tuning.startRetrySeconds)) s")
        }
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
        // A track that only waits for Play (restored, or unloaded) stays waiting.
        guard hasTrack, pendingTarget == nil, unloaded == nil else { return }
        pendingTarget = (currentTarget, position)
    }

    /// The track that plays, in the list it plays from.
    private var currentTarget: PlayTarget {
        PlayTarget(videoID: state.videoID, listID: currentListID, shuffle: currentShuffle)
    }

    // MARK: - The last session

    /// Kept on every pause and track change, once a minute while playing,
    /// and at quit: the next launch shows this track, paused where it was.
    private func saveSession() {
        guard hasTrack, !state.isAd, !Settings.isSnapshot else { return }
        var kind = "other", id = ""
        switch source {
        case .mood(let mood): kind = "mood"; id = mood
        case .playlist(let list): kind = "playlist"; id = list
        case .radio(let title): kind = "radio"; id = title
        case .other, nil: break
        }
        let known = currentListID.flatMap { listTitles[$0] }
        let listKind: String? = switch known?.kind {
        case .album: "album"
        case .artist: "artist"
        case .playlist: "playlist"
        default: nil
        }
        let session = LastSession(
            videoID: state.videoID, title: state.title, artist: state.artist,
            artwork: state.artworkURL?.absoluteString, artistID: state.artistID, albumID: state.albumID,
            like: state.like, position: unloaded?.position ?? position(at: Date()), duration: state.duration,
            listID: currentListID, shuffle: currentShuffle, sourceKind: kind, sourceID: id,
            listTitle: known?.title, listKind: listKind)
        guard session != savedSession else { return }
        savedSession = session
        session.save()
    }

    /// Shows the last session's track, paused. The page is not asked for
    /// anything: Play loads the track at its position, as after "unload
    /// when paused".
    private func restoreSession() {
        guard !hasTrack, pendingTarget == nil, let session = LastSession.load() else { return }
        savedSession = session
        var restored = PlayerState()
        restored.videoID = session.videoID
        restored.title = session.title
        restored.artist = session.artist
        restored.artworkURL = session.artwork.flatMap(URL.init(string:))
        restored.artistID = session.artistID
        restored.albumID = session.albumID
        restored.like = session.like
        restored.position = session.position
        restored.duration = session.duration
        // Play, Next and Previous are the page's to answer once it plays;
        // in a list there is a next track to go to.
        restored.queueIndex = 0
        restored.queueCount = 1
        restored.queueHasMore = session.listID != nil
        state = restored
        clock = PlaybackClock(restored, at: Date())
        currentListID = session.listID
        currentShuffle = session.shuffle
        source = switch session.sourceKind {
        case "mood": .mood(session.sourceID)
        case "playlist": .playlist(session.sourceID)
        // Play goes on with this track's radio, not the one it came from.
        case "radio": .radio(session.title)
        default: .other
        }
        if let list = session.listID, let title = session.listTitle {
            let kind: SourceLabel.Kind = switch session.listKind {
            case "album": .album
            case "artist": .artist
            default: .playlist
            }
            listTitles[list] = (title, kind, "")
        }
        unloaded = (currentTarget, session.position)
        nowPlaying.update(restored)
        EventLog.write("restored\t\(session.videoID)\tat \(Int(session.position)) s")
        if Settings.bool(Keys.resume) { play() }
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

    /// Puts a tile where another one is; the tiles between move up by one.
    func move(_ id: Mood.ID, toPlaceOf target: Mood.ID) {
        guard let from = moods.firstIndex(where: { $0.id == id }),
              let to = moods.firstIndex(where: { $0.id == target }), from != to else { return }
        moods.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    /// One place earlier (-1) or later (1), from a tile's menu.
    func move(_ mood: Mood, by step: Int) {
        guard let from = moods.firstIndex(where: { $0.id == mood.id }),
              moods.indices.contains(from + step) else { return }
        moods.swapAt(from, from + step)
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
        setLike(state.videoID, on: !state.isLiked)
    }

    /// Likes any track, or takes the like back: from a row's menu.
    func setLike(_ videoID: String, on: Bool) {
        guard !videoID.isEmpty else { return }
        bridge.call("like", videoID, on)
        likeChanges[videoID] = on
        if hasTrack, videoID == state.videoID { state.like = on ? "LIKE" : "INDIFFERENT" }
    }

    /// A list knows a track's like as of when it was loaded; the playing
    /// track and the likes set here since are newer.
    func isLiked(_ videoID: String, listed: Bool) -> Bool {
        if hasTrack, videoID == state.videoID, !state.like.isEmpty { return state.isLiked }
        return likeChanges[videoID] ?? listed
    }

    /// Jumps to a track of Up Next; the ones before it are skipped.
    func playUpNext(_ track: Track) {
        bridge.call("playQueued", track.index, track.videoID)
    }

    func removeFromQueue(_ track: Track) {
        bridge.call("removeQueued", track.index, track.videoID)
        upNext.removeAll { $0.index == track.index } // shown at once; the page sends the list again
    }

    /// Puts a track right after the one that plays. The title and artist
    /// are what the list showed, for when YouTube Music gives none.
    func playNext(_ videoID: String, title: String, artist: String) {
        guard hasTrack, !videoID.isEmpty else { return }
        bridge.call("playNext", videoID, title, artist)
    }

    /// The track, then its radio, as a click on a search result plays it.
    func playRadio(of videoID: String, title: String) {
        guard !videoID.isEmpty else { return }
        load(PlayTarget(videoID: videoID, listID: nil), from: .radio(title), startAt: nil)
    }

    private func assume(playing: Bool) {
        guard hasTrack else { return }
        expected = (playing, Date().addingTimeInterval(Self.expectationWindow))
        guard state.isPlaying != playing else { return }
        // From where the clock has got to, not the last report's position.
        let now = Date()
        state.position = clock.position(at: now)
        state.isPlaying = playing
        clock = PlaybackClock(state, at: now)
        nowPlaying.update(state)
        playingChanged(playing)
    }
    /// On a track that waits for Play: its list is loaded, skipping to the
    /// track after (or before) it.
    func next() {
        if unloaded != nil { skipAfterLoad = 1; play() } else { bridge.call("next") }
    }

    func previous() {
        if unloaded != nil { skipAfterLoad = -1; play() } else { bridge.call("previous") }
    }

    func seek(to seconds: Double) {
        bridge.call("seek", seconds)
        unloaded?.position = seconds // a track that waits for Play starts from there
        // Shown at once; the page confirms with its next report.
        state.position = seconds
        clock = PlaybackClock(state, at: Date())
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
        clock.position(at: date)
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

    /// What plays, for the strip: the vibe, or the playlist or album, by
    /// name, or the track whose radio was started. Nil for a track played on
    /// its own, an ad, or a list whose name is unknown.
    var sourceLabel: SourceLabel? {
        guard hasTrack, !state.isAd else { return nil }
        switch source {
        case .mood(let id):
            guard let mood = moods.first(where: { $0.id == id }) else { return nil }
            return SourceLabel(kind: .vibe(colour: VibePalette.index(for: mood)), name: mood.name, symbol: mood.symbol,
                               destination: mood.id)
        case .playlist(let id):
            if id == Tuning.likedMusicID {
                return SourceLabel(kind: .playlist, name: "Liked Music", symbol: "heart.fill", destination: id)
            }
            if let playlist = playlists.first(where: { $0.id == id }) {
                return SourceLabel(kind: .playlist, name: playlist.title, symbol: "music.note.list", destination: id)
            }
            guard let known = listTitles[id] else { return nil }
            let symbol = switch known.kind {
            case .album: "square.stack"
            case .artist: "music.mic"
            default: "music.note.list"
            }
            return SourceLabel(kind: known.kind, name: known.title, symbol: symbol, destination: known.page)
        case .radio(let title):
            return SourceLabel(kind: .radio, name: title.isEmpty ? "a track" : title, symbol: "dot.radiowaves.left.and.right")
        case .other, nil:
            return nil
        }
    }

    /// The playlists a track can be added to: the user's own, not Liked
    /// Music (that is a like) and not the ones saved from others.
    var ownPlaylists: [Playlist] {
        playlists.filter { playlist in
            guard playlist.id != Tuning.likedMusicID else { return false }
            if playlist.isOwn || ownedPlaylistIDs.contains(playlist.id) { return true }
            let author = playlist.subtitle.components(separatedBy: Self.subtitleSeparator).first ?? ""
            return isOwnName(author)
        }
    }

    // MARK: - Editing playlists

    /// A new private playlist, with the track in it when one is given.
    func createPlaylist(title: String, adding videoID: String? = nil) {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard pageReady, account.isSignedIn, !title.isEmpty else { return }
        bridge.call("createPlaylist", title, videoID ?? "")
    }

    func renamePlaylist(_ playlist: Playlist, to title: String) {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard pageReady, account.isSignedIn, !title.isEmpty, title != playlist.title else { return }
        bridge.call("renamePlaylist", playlist.id, title)
    }

    func deletePlaylist(_ playlist: Playlist) {
        guard pageReady, account.isSignedIn else { return }
        bridge.call("deletePlaylist", playlist.id)
    }

    // MARK: The user's order of the playlists

    /// YouTube Music lists the library by its own rules; the user's order,
    /// made by dragging, is kept here and laid over every list that comes.
    /// Playlists not in it yet (new ones) go first, as the library has them.
    private var playlistOrder: [String] {
        get { Settings.defaults.stringArray(forKey: Keys.playlistOrder) ?? [] }
        set { Settings.defaults.set(newValue, forKey: Keys.playlistOrder) }
    }

    private func ordered(_ listed: [Playlist]) -> [Playlist] {
        let order = playlistOrder
        guard !order.isEmpty else { return listed }
        let place = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let known = listed.filter { place[$0.id] != nil }.sorted { place[$0.id]! < place[$1.id]! }
        let new = listed.filter { place[$0.id] == nil && $0.id != Tuning.likedMusicID }
        let liked = listed.filter { $0.id == Tuning.likedMusicID }
        return liked + new + known.filter { $0.id != Tuning.likedMusicID }
    }

    /// Puts a playlist where another one is; the ones between move by one.
    func movePlaylist(_ id: String, toPlaceOf target: String) {
        guard let from = playlists.firstIndex(where: { $0.id == id }),
              let to = playlists.firstIndex(where: { $0.id == target }), from != to,
              id != Tuning.likedMusicID, target != Tuning.likedMusicID else { return }
        playlists.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        playlistOrder = playlists.map(\.id).filter { $0 != Tuning.likedMusicID }
    }

    /// One place up (-1) or down (1), from a row's menu.
    func movePlaylist(_ playlist: Playlist, by step: Int) {
        guard let from = playlists.firstIndex(where: { $0.id == playlist.id }),
              playlists.indices.contains(from + step), playlists[from + step].id != Tuning.likedMusicID else { return }
        playlists.swapAt(from, from + step)
        playlistOrder = playlists.map(\.id).filter { $0 != Tuning.likedMusicID }
    }

    func add(_ videoID: String, to playlist: Playlist) {
        guard pageReady, account.isSignedIn, !videoID.isEmpty else { return }
        bridge.call("addToPlaylist", playlist.id, videoID)
    }

    /// Playlists whose tracks YouTube Music offered to remove: the user's,
    /// whatever their subtitles say.
    private var ownedPlaylistIDs: Set<String> = []

    /// Playlists made here that the library has not listed yet. YouTube
    /// Music's library learns of a new playlist a minute or two after it is
    /// made, so the list asked for right away comes back without it.
    private var newPlaylists: [(playlist: Playlist, made: Date)] = []

    private func receive(playlists listed: [Playlist]) {
        let now = Date()
        newPlaylists.removeAll { new in
            listed.contains { $0.id == new.playlist.id }
                || now.timeIntervalSince(new.made) > Tuning.newPlaylistWaitSeconds
        }
        playlists = ordered(withNew(listed))
        playlistsState = .loaded
        guard !newPlaylists.isEmpty else { return }
        // Ask again until the library has them.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.newPlaylistRetrySeconds))
            guard let self, !self.newPlaylists.isEmpty else { return }
            self.loadPlaylists()
        }
    }

    /// The library's list with the playlists it does not know yet, the
    /// newest first, after Liked Music.
    private func withNew(_ listed: [Playlist]) -> [Playlist] {
        let missing = newPlaylists.map(\.playlist).filter { new in !listed.contains { $0.id == new.id } }
        guard !missing.isEmpty else { return listed }
        var all = listed
        all.insert(contentsOf: missing.reversed(), at: all.first?.id == Tuning.likedMusicID ? 1 : 0)
        return all
    }

    /// Whether the open playlist's tracks can be taken out of it.
    var canEditOpenPlaylist: Bool {
        guard let id = openPlaylist?.id else { return false }
        return ownPlaylists.contains { $0.id == id }
    }

    func remove(_ track: Track, from playlist: Playlist) {
        guard pageReady, account.isSignedIn, !track.setVideoID.isEmpty else { return }
        let video = track.heldVideoID.isEmpty ? track.videoID : track.heldVideoID
        bridge.call("removeFromPlaylist", playlist.id, video, track.setVideoID)
    }

    /// Asks YouTube Music which of the user's playlists hold the track.
    func checkPlaylists(holding videoID: String) {
        guard !videoID.isEmpty, pageReady, account.isSignedIn, askingHolding.insert(videoID).inserted else { return }
        Task {
            defer { askingHolding.remove(videoID) }
            guard let ids = try? await bridge.value("playlistsWith", [videoID]) as? [String] else { return }
            if playlistsHolding.count > Tuning.holdingCacheSize { playlistsHolding.removeAll() }
            playlistsHolding[videoID] = Set(ids)
        }
    }

    /// Takes a track out of a playlist by its video ID, for Add to Playlist's
    /// checkmarks, where the entry in the playlist is not known.
    func removeAnywhere(_ videoID: String, from playlist: Playlist) {
        guard pageReady, account.isSignedIn, !videoID.isEmpty else { return }
        bridge.call("removeVideo", playlist.id, videoID)
    }

    private func playlistEdited(_ action: String, id: String, title: String, videoID: String) {
        if action == "created", !playlists.contains(where: { $0.id == id }) {
            newPlaylists.append((Playlist(id: id, title: title, isOwn: true), Date()))
            playlists = ordered(withNew(playlists))
        }
        // Shown at once; the library's next list confirms it.
        if action == "renamed", let index = playlists.firstIndex(where: { $0.id == id }) {
            let old = playlists[index]
            playlists[index] = Playlist(id: old.id, title: title, subtitle: old.subtitle, artworkURL: old.artworkURL, isOwn: old.isOwn)
            if openPlaylist?.id == id { openPlaylist = playlists[index] }
        }
        if action == "deleted" {
            playlists.removeAll { $0.id == id }
            newPlaylists.removeAll { $0.playlist.id == id }
            if openPlaylist?.id == id { closePlaylist() }
            if source == .playlist(id) { source = .other } // the queue plays on
        }
        if !videoID.isEmpty {
            if action == "removed" {
                playlistsHolding[videoID]?.remove(id)
            } else if playlistsHolding[videoID] != nil || action == "created" {
                playlistsHolding[videoID, default: []].insert(id)
            }
        }
        let name = playlists.first { $0.id == id }?.title ?? title
        switch action {
        case "renamed": show(notice: "Renamed to “\(title)”")
        case "deleted": show(notice: "Deleted the playlist")
        case "created": show(notice: videoID.isEmpty ? "Created “\(name)”" : "Added to new “\(name)”")
        case "added": show(notice: "Added to “\(name)”")
        case "removed": show(notice: "Removed from “\(name)”")
        default: show(notice: "Already in “\(name)”")
        }
        // A removal sends the list itself; an addition goes at the end.
        if openPlaylist?.id == id, action != "removed" { bridge.call("tracks", id) }
    }

    func show(notice text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.noticeTime))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

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

    /// Songs for a query, for the vibe maker; wakes the page and waits for
    /// it. Throws when the page does not come up or the search fails.
    func findSongs(_ query: String) async throws -> [MusicItem] {
        if !pageReady {
            wake()
            for _ in 0..<Int(Tuning.pageWaitSeconds * 5) where !pageReady {
                try await Task.sleep(for: .milliseconds(200))
            }
            guard pageReady else { throw URLError(.timedOut) }
        }
        return MusicItem.list(try await bridge.value("findSongs", [query]))
    }

    /// Debug: makes a vibe from words without the sheet and logs it.
    private func logVibe(_ words: String) {
        Task {
            let start = Date()
            let reading = await VibeMaker.read(words, mix: .both)
            EventLog.write("vibe\treading \(String(format: "%.1f", Date().timeIntervalSince(start))) s: \(reading.name) | \(reading.tags) | \(reading.artists) | \(reading.vocals) | \(reading.matchedMoods ?? [])")
            do {
                let found = try await VibeMaker.find(words, reading: reading, vocals: reading.vocals, search: findSongs)
                EventLog.write("vibe\tfound \(String(format: "%.1f", Date().timeIntervalSince(start))) s: \(found.artists) | " + found.anchors.map { "\($0.title) — \($0.artist)" }.joined(separator: "; "))
            } catch {
                EventLog.write("vibe\tfailed: \(error)")
            }
        }
    }

    /// All of an artist's songs, from the first: their page's Play.
    func play(artist page: ArtistPage) {
        play(list: page.songsPlaylistID, from: 0, title: page.name, kind: .artist, page: page.id)
    }

    /// A song plays with its radio after it, as in YouTube Music; an album
    /// or playlist plays from its first track.
    func play(_ item: MusicItem) {
        if !item.videoID.isEmpty {
            load(PlayTarget(videoID: item.videoID, listID: nil), from: .other, startAt: nil)
        } else if !item.playlistID.isEmpty {
            listTitles[item.playlistID] = (item.title, item.kind == .album ? .album : .playlist, item.browseID)
            load(PlayTarget(videoID: nil, listID: item.playlistID), from: .playlist(item.playlistID), startAt: nil)
        }
    }

    /// An album or playlist from one of its tracks on.
    func play(_ collection: CollectionPage, from index: Int = 0) {
        play(list: collection.playlistID, from: index, title: collection.title,
             kind: collection.isAlbum ? .album : .playlist)
    }

    /// A playlist from one of its tracks on: an album, or all of an artist's
    /// songs, which their top songs are the start of.
    func play(list id: String, from index: Int, title: String = "", kind: SourceLabel.Kind = .playlist, page: String = "") {
        guard !id.isEmpty else { return }
        if !title.isEmpty { listTitles[id] = (title, kind, page) }
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
        if let page { artistPages[id] = page; keep(id) } else { exploreFailures.insert(id) }
    }

    private func receive(collection id: String, page: CollectionPage?) {
        exploreAsked.remove(id)
        if let page { collectionPages[id] = page; keep(id) } else { exploreFailures.insert(id) }
    }

    /// The pages in the order they came; past Tuning.explorePagesKept the
    /// oldest go. One shown again loads again.
    private var explorePageOrder: [String] = []

    private func keep(_ id: String) {
        explorePageOrder.removeAll { $0 == id }
        explorePageOrder.append(id)
        while explorePageOrder.count > Tuning.explorePagesKept {
            let old = explorePageOrder.removeFirst()
            artistPages[old] = nil
            collectionPages[old] = nil
        }
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
            var track = track
            track.index = start + offset
            return track
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
        playlistsAsked = Date()
        bridge.call("playlists")
    }

    /// For the Playlists page coming into view: the list again, unless it
    /// was asked for a moment ago.
    func refreshPlaylists() {
        guard account.isSignedIn, Date().timeIntervalSince(playlistsAsked) > Tuning.playlistsFreshSeconds else { return }
        loadPlaylists()
    }

    private func load(_ target: PlayTarget, from newSource: PlaySource, startAt position: Double?) {
        unloaded = nil
        problem = nil
        source = newSource
        currentListID = target.listID
        currentShuffle = target.shuffle
        EventLog.write("load\t\(target.videoID ?? "-")\t\(target.listID ?? "-")\(target.shuffle ? "\tshuffle" : "")")
        if pageReady {
            sendToPage(target, startAt: position)
        } else {
            pendingTarget = (target, position)
            if webView.url?.host != Tuning.musicHome.host { loadHome() }
        }
    }

    private func sendToPage(_ target: PlayTarget, startAt position: Double?) {
        defer { skipAfterLoad = 0 }
        isLoading = true
        if let video = target.videoID, let list = target.listID, let position {
            // Resuming: the same track at its position, and the list goes
            // on after it.
            bridge.call("load", "playlist", list, position, [
                "shuffle": target.shuffle, "videoId": video, "skip": skipAfterLoad,
                // What is known of the track, for when the list's first
                // page does not have it.
                "track": ["title": state.title, "artist": state.artist, "like": state.like,
                          "artwork": state.artworkURL?.absoluteString ?? "",
                          "artistId": state.artistID, "albumId": state.albumID],
            ])
        } else if let video = target.videoID, target.listID == nil || position != nil {
            bridge.call("load", "video", video, position ?? 0)
        } else if let list = target.listID {
            bridge.call("load", "playlist", list, 0, ["shuffle": target.shuffle, "startIndex": target.startIndex])
        }
    }

    /// From the widget, or a `bside://` URL.
    func perform(_ command: WidgetCommand) {
        EventLog.write("widget\t\(command.rawValue)")
        switch command {
        case .toggle: togglePlayPause()
        case .next: next()
        case .previous: previous()
        case .vibe: playVibe()
        case .show:
            MainWindow.show()
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
        savedSession = nil
        LastSession.clear() // it may be from the account's own playlists
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
        if !new.videoID.isEmpty { isLoading = false }
        clock = clock.following(new, at: Date(), sameTrack: new.videoID == old.videoID)
        nowPlaying.update(new)
        noteBuffering(new.isPlaying && new.isBuffering)

        // The title arrives a moment after the video ID, so wait for it.
        if !new.title.isEmpty, new.videoID != old.videoID || new.title != old.title {
            EventLog.write("track\t\(new.videoID)\t\(new.artist) - \(new.title)")
            TrackNotifier.shared.trackStarted(new)
            if !new.isAd {
                loadLyrics() // so Lyrics shows only for a track that has them
                checkPlaylists(holding: new.videoID) // ready before its menu opens
            }
        }
        if new.isAd, !old.isAd {
            EventLog.write("ad")
        }
        if new.isPlaying != old.isPlaying {
            playingChanged(new.isPlaying)
        }
        if new.isPlaying != old.isPlaying || new.videoID != old.videoID || new.title != old.title {
            saveSession()
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
            if let words = Settings.defaults.string(forKey: Keys.makeVibe) { logVibe(words) }
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
                forgetWhatWasAsked()
            } else if detail.hasPrefix("player error") {
                isLoading = false
                problem = "This track could not be played."
            } else if detail.hasPrefix("playlist edit") {
                show(notice: "The playlist could not be changed. Try again.")
            } else if detail.hasPrefix("like") {
                problem = "The like could not be saved."
            }
        default:
            EventLog.write("\(kind)\t\(detail)")
        }
    }

    /// What was asked for does not exist any more (a playlist deleted on
    /// the web, say): back to nothing playing, and it is not asked for
    /// again at the next launch.
    private func forgetWhatWasAsked() {
        isLoading = false
        unloaded = nil
        source = nil
        currentListID = nil
        state = PlayerState()
        clock = PlaybackClock()
        nowPlaying.update(state)
        savedSession = nil
        LastSession.clear()
    }

    /// "Buffering…" is shown once a wait has lasted a while, so the usual
    /// moment at the start of a track does not flash it.
    private func noteBuffering(_ buffering: Bool) {
        if buffering {
            guard bufferingTask == nil else { return }
            bufferingTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Tuning.bufferingNoticeSeconds))
                guard !Task.isCancelled, let self, self.state.isPlaying, self.state.isBuffering else { return }
                self.showsBuffering = true
                EventLog.write("buffering\t\(self.state.videoID) at \(Int(self.state.position)) s")
            }
        } else {
            bufferingTask?.cancel()
            bufferingTask = nil
            if showsBuffering { showsBuffering = false }
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
        unloaded = (currentTarget, state.position)
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
            saveSession() // where a track is, should the app be killed
            let stalled = state.isPlaying && state.position == lastHeartbeatPosition
            EventLog.write("\(stalled ? "STALLED" : "heartbeat")\t\(state.isPlaying ? "playing" : "paused")\t"
                + "\(Int(state.position))s\t\(state.videoID)\t\(Int(totalMegabytes)) MB"
                + "\t" + processes.map { "\($0.name) \(Int($0.megabytes))" }.joined(separator: ", "))
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
