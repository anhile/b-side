import AppKit
import WidgetKit

/// Keeps the desktop widget told. The app answers the widget's questions
/// on a message port (what plays, with the artwork) and takes its commands
/// there; whenever what plays changes, it asks WidgetKit to redraw, a
/// moment after the change so a burst of reports becomes one redraw.
@MainActor
enum WidgetFeed {
    private static var pending: Task<Void, Never>?
    private static var told: WidgetState?
    private static var current = WidgetState()
    private static var port: CFMessagePort?
    private static var onCommand: ((WidgetCommand) -> Void)?

    /// Opens the port. `perform` takes the widget's commands.
    static func start(_ perform: @escaping (WidgetCommand) -> Void) {
        guard port == nil, !Settings.isSnapshot else { return }
        onCommand = perform
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        guard let local = CFMessagePortCreateLocal(nil, WidgetPort.name as CFString, { _, message, data, _ in
            MainActor.assumeIsolated { WidgetFeed.answer(message, data.map { $0 as Data }) }
        }, &context, nil) else {
            return EventLog.write("error\twidget: the message port could not be made")
        }
        port = local
        let source = CFMessagePortCreateRunLoopSource(nil, local, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private static func answer(_ message: Int32, _ data: Data?) -> Unmanaged<CFData>? {
        switch WidgetPort.Message(rawValue: message) {
        case .state:
            guard let json = try? JSONEncoder().encode(current) else { return nil }
            return Unmanaged.passRetained(json as CFData)
        case .command:
            if let data, let name = String(data: data, encoding: .utf8), let command = WidgetCommand(rawValue: name) {
                onCommand?(command)
            }
            return Unmanaged.passRetained(Data() as CFData)
        case nil:
            return nil
        }
    }

    /// Called by the player whenever its state or source changes.
    static func note(_ player: PlayerController) {
        guard !Settings.isSnapshot else { return }
        pending?.cancel()
        pending = Task { [weak player] in
            try? await Task.sleep(for: .seconds(Tuning.widgetDelay))
            guard !Task.isCancelled, let player else { return }
            await refresh(for: player)
        }
    }

    private static func refresh(for player: PlayerController) async {
        var state = WidgetState()
        state.hasTrack = player.hasTrack && !player.state.isAd
        state.isPlaying = player.state.isPlaying
        state.title = player.state.title
        state.artist = player.state.artist
        state.source = player.sourceLabel?.text ?? ""
        state.sourceSymbol = player.sourceLabel?.symbol ?? ""
        if state.hasTrack, let url = player.state.artworkURL {
            state.artwork = url == artworkFor ? current.artwork : await png(of: url)
            artworkFor = url
        }
        current = state
        guard told != state else { return }
        told = state
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetState.widgetKind)
    }

    private static var artworkFor: URL?

    /// The artwork, small, as JPEG: a widget is drawn at a few hundred
    /// points, and the picture crosses a message port on every redraw.
    private static func png(of url: URL) async -> Data? {
        guard let image = await ArtworkLoader.image(for: url) else { return nil }
        let side = Tuning.widgetArtworkPixels
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let small = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: Tuning.widgetArtworkQuality])
    }

    /// `bside://toggle` and the like, from the widget when the app was not
    /// running, or from anywhere else.
    static func command(in url: URL) -> WidgetCommand? {
        guard url.scheme == WidgetState.urlScheme, let host = url.host() else { return nil }
        return WidgetCommand(rawValue: host)
    }
}
