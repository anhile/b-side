import AppKit
import MediaPlayer
import WebKit

/// System Now Playing widget and media keys.
///
/// WebKit also publishes Now Playing for the playing element, so some key
/// presses reach the page instead of here; `JSBridge` hands those back to the
/// app through Media Session handlers. The "Media keys and Now Playing"
/// toggle in Settings turns this class off.
@MainActor
final class NowPlaying {
    enum Command {
        case play, pause, toggle, next, previous
        case seek(Double)
    }

    var onCommand: ((Command) -> Void)?

    private var registered = false
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?
    private var lastState = PlayerState()

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    func update(_ state: PlayerState) {
        lastState = state
        guard registered else { return }
        loadArtworkIfNeeded(state.artworkURL)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.title,
            MPMediaItemPropertyArtist: state.artist,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.position,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        // macOS has no audio session, so the state must be set explicitly.
        center.playbackState = state.isPlaying ? .playing : .paused
    }

    private func register() {
        guard !registered else { return }
        registered = true
        EventLog.write("remote\tregistered for media keys")
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand) { _ in .play }
        add(center.pauseCommand) { _ in .pause }
        add(center.togglePlayPauseCommand) { _ in .toggle }
        add(center.nextTrackCommand) { _ in .next }
        add(center.previousTrackCommand) { _ in .previous }
        add(center.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { .seek($0.positionTime) }
        }
        update(lastState)
        claimPlayKey()
    }

    /// The system sends Play only to an app that has reported `.playing` at
    /// least once; `.paused` and track info alone leave Play to Apple Music
    /// (experiment 1 in docs/research/default-player.md, macOS 27). So right
    /// after launch, before anything has played, B-Side reports a moment of
    /// playing, then its real state: the same sequence the experiment tested.
    private func claimPlayKey() {
        guard !lastState.isPlaying else { return }
        MPNowPlayingInfoCenter.default().playbackState = .playing
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.claimDuration) { [weak self] in
            guard let self, self.registered else { return }
            self.update(self.lastState)
            EventLog.write("remote\tclaimed the Play key")
        }
    }

    private static let claimDuration: TimeInterval = 0.5

    private func unregister() {
        guard registered else { return }
        registered = false
        let center = MPRemoteCommandCenter.shared()
        [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
         center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand]
            .forEach { $0.removeTarget(nil) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .unknown
    }

    private func add(_ command: MPRemoteCommand, _ map: @escaping (MPRemoteCommandEvent) -> Command?) {
        command.isEnabled = true
        command.addTarget { [weak self] event in
            guard let mapped = map(event) else { return .commandFailed }
            DispatchQueue.main.async { self?.onCommand?(mapped) }
            return .success
        }
    }

    private func loadArtworkIfNeeded(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        guard let url else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            guard let self, self.artworkURL == url else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.update(self.lastState)
        }
    }
}

/// Whether WebKit holds a Now Playing session of its own for the page.
/// Written to the event log once per launch, as a check on the key routing.
///
/// UNCERTAIN: private WebKit API, found by listing the selectors of
/// `WKWebView`; guarded with `responds(to:)`.
enum WebKitNowPlaying {
    private static let hasSession = Selector(("_hasActiveNowPlayingSession"))

    static func hasSession(_ webView: WKWebView) -> Bool? {
        guard webView.responds(to: hasSession), let method = webView.method(for: hasSession) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method, to: Getter.self)(webView, hasSession)
    }
}
