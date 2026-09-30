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
    /// The last thing that happened, for Diagnostics.
    @Published private(set) var status = "Starting"
    @Published private(set) var isWebViewVisible = false
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

    private var currentListID: String?
    /// When `state` arrived, to run the position forward between reports.
    private var stateDate = Date()
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
                        moods: [Mood] = [.liked]) -> PlayerController {
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

        nowPlaying.onCommand = { [weak self] in self?.handle(command: $0) }
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
                loadHome()
            }
        }
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
            status = "Content rules failed to compile: \(error.localizedDescription)"
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
    /// nothing is loaded.
    func playVibe() {
        play(Mood.liked)
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

    /// Diagnostics: a video ID, a playlist ID, or a URL.
    func load(_ input: String) {
        guard let target = PlayTarget(input) else {
            problem = "Enter a video ID, a playlist ID, or a YouTube Music URL."
            return
        }
        load(target, from: .other, startAt: nil)
    }

    func play() {
        if let unloaded {
            load(unloaded.target, from: source ?? .other, startAt: unloaded.position)
        } else {
            bridge.call("play")
        }
    }

    func pause() { bridge.call("pause") }
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
        status = "Loading"
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
            bridge.call("load", "playlist", list, 0, ["shuffle": target.shuffle])
        }
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

    /// Diagnostics: look at the player page.
    func showWebView() {
        window.makeKeyAndOrderFront(nil)
        isWebViewVisible = true
    }

    func hideWebView() {
        window.orderOut(nil)
        window.title = "B-Side Player Page"
        isWebViewVisible = false
        // Coming back from the sign-in flow: return to the player page.
        if signingIn || (webView.url?.host != Tuning.musicHome.host && unloaded == nil) {
            signingIn = false
            loadHome()
        }
    }

    // MARK: - Page messages

    private func handle(state new: PlayerState) {
        guard unloaded == nil else { return }
        let old = state
        state = new
        stateDate = Date()
        nowPlaying.update(new)

        // The title arrives a moment after the video ID, so wait for it.
        if !new.title.isEmpty, new.videoID != old.videoID || new.title != old.title {
            EventLog.write("track\t\(new.videoID)\t\(new.artist) - \(new.title)")
        }
        if new.isAd, !old.isAd {
            EventLog.write("ad")
        }
        if new.isPlaying != old.isPlaying {
            playingChanged(new.isPlaying)
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
        if !new.isSignedIn {
            playlists = []
            playlistsState = .idle
        }
    }

    private func handle(event kind: String, detail: String) {
        switch kind {
        case "ready":
            status = "Player ready"
            phase = .ready
            pageReady = true
            bridge.call("volume", volume)
            if account.isSignedIn { loadPlaylists() }
            if let pending = pendingTarget {
                pendingTarget = nil
                sendToPage(pending.target, startAt: pending.position)
            }
        case "error":
            status = "Error: \(detail)"
            EventLog.write("error\t\(detail)")
            // player.js starts every error with the step that failed.
            if detail.hasPrefix("boot") {
                phase = .failed("YouTube Music could not be loaded. Check the connection and try again.")
            } else if detail.hasPrefix("playlists") {
                playlistsState = .failed("The list of playlists could not be loaded.")
            } else if detail.hasPrefix("load") {
                problem = "This could not be played. It may be empty or unavailable."
            } else if detail.hasPrefix("player error") {
                problem = "This track could not be played."
            }
        default:
            status = "\(kind): \(detail)"
            EventLog.write("\(kind)\t\(detail)")
        }
    }

    private func playingChanged(_ isPlaying: Bool) {
        EventLog.write(isPlaying ? "playing" : "paused\t\(Int(state.position))s")
        status = isPlaying ? "Playing" : "Paused"
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
        status = "Page unloaded after \(minutes) min paused. Play reloads it."
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
        status = "WebContent process terminated, reloading"
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
        status = "Load failed: \(error.localizedDescription)"
        EventLog.write("error\tnavigation: \(error.localizedDescription)")
    }
}
