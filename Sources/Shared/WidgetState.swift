import Foundation

/// What the app tells its widget, and how the widget talks back. This file
/// is compiled into the app and into the widget extension.
///
/// The widget asks the running app over a message port (WidgetPort) for
/// what plays, artwork included, and sends its buttons' commands back the
/// same way; when the app is not running, a button opens it by URL. No
/// shared files: a group container needs a Team ID on recent macOS, and
/// B-Side is signed without one.
struct WidgetState: Codable, Equatable {
    var hasTrack = false
    var isPlaying = false
    var title = ""
    var artist = ""
    /// What it plays from: a vibe or playlist name, "Radio: …".
    var source = ""
    var sourceSymbol = ""
    /// The artwork as JPEG, small.
    var artwork: Data?
    /// False when the app did not answer: it is not running.
    var appRunning = true

    static let widgetKind = "NowPlaying"
    static let appBundleID = "com.anhile.bside"
    /// `bside://<command>` opens the app and runs the command.
    static let urlScheme = "bside"
}

/// What a widget button asks the app to do.
enum WidgetCommand: String, CaseIterable {
    case toggle, next, previous, vibe
    /// Only shows the app, on Now Playing.
    case show

    var url: URL { URL(string: "\(WidgetState.urlScheme)://\(rawValue)")! }
}

/// The message port between the two: the app answers on it while it runs.
/// The widget extension is sandboxed and may look the name up only through
/// its mach-lookup exception entitlement (Support/BSideWidget.entitlements).
enum WidgetPort {
    static let name = "com.anhile.bside.widget"

    enum Message: Int32 {
        case state = 1
        case command = 2
    }

    /// What plays now, from the app; nil when it is not running or did not
    /// answer in time.
    static func askState() -> WidgetState? {
        guard let reply = send(.state, nil) else { return nil }
        return try? JSONDecoder().decode(WidgetState.self, from: reply)
    }

    /// True when the app took the command; false when it is not running.
    @discardableResult
    static func send(_ command: WidgetCommand) -> Bool {
        send(.command, Data(command.rawValue.utf8)) != nil
    }

    private static func send(_ message: Message, _ data: Data?) -> Data? {
        guard let port = CFMessagePortCreateRemote(nil, name as CFString) else { return nil }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, message.rawValue, data as CFData?, 3, 3,
                                              CFRunLoopMode.defaultMode.rawValue, &reply)
        CFMessagePortInvalidate(port)
        guard status == kCFMessagePortSuccess else { return nil }
        return reply?.takeRetainedValue() as Data? ?? Data()
    }
}
