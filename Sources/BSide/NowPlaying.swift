import AppKit
import MediaPlayer

/// System Now Playing widget and media keys.
///
/// UNCERTAIN: WebKit also publishes Now Playing on its own, from the page's
/// `navigator.mediaSession`. The two may compete. The "Native Now Playing"
/// toggle in the UI turns this class off so the two can be compared.
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
    }

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
            EventLog.write("remote\t\(mapped)") // media keys and the Now Playing widget land here
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
