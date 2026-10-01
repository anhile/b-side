import Foundation
import WebKit

struct PlayerState: Equatable {
    var title = ""
    var artist = ""
    var artworkURL: URL?
    var videoID = ""
    var position: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var isAd = false
    var queueIndex = -1
    var queueCount = 0
    /// The queue has more pages that are not loaded yet.
    var queueHasMore = false
    /// "LIKE", "INDIFFERENT", or "" when unknown.
    var like = ""

    var isLiked: Bool { like == "LIKE" }

    var hasPrevious: Bool { queueIndex > 0 }
    var hasNext: Bool { queueIndex >= 0 && (queueIndex < queueCount - 1 || queueHasMore) }
}

struct Playlist: Identifiable, Equatable {
    let id: String
    let title: String
    var subtitle = ""
    var artworkURL: URL?
}

/// A track's lyrics: plain text, and where they come from ("Source: Musixmatch").
/// Empty text means the track has none. `lines` holds the timed lines when a
/// source has them (see TimedLyrics); the text is shown otherwise.
struct Lyrics: Equatable {
    let videoID: String
    var text: String
    var source: String
    /// YouTube Music's lyrics page for the track (`MPLYt…`), empty without one.
    var page = ""
    var lines: [LyricLine] = []

    var isTimed: Bool { !lines.isEmpty }
}

/// One timed line: when it starts, in seconds, and its words ("" for a break).
struct LyricLine: Equatable {
    let start: Double
    let text: String
}

extension [LyricLine] {
    /// The line being sung at `position`, or nil before the first one.
    func index(at position: Double) -> Int? {
        var low = 0, high = count
        while low < high {
            let middle = (low + high) / 2
            if self[middle].start <= position { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }
}

/// One track in a playlist's list. A playlist can hold a track twice, so the
/// identity is the position.
struct Track: Identifiable, Equatable {
    let index: Int
    let videoID: String
    let title: String
    let artist: String
    var artworkURL: URL?
    var id: Int { index }
}

/// Talks to `window.__bside`, which Resources/player.js defines in the page.
@MainActor
final class JSBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "bside"

    weak var webView: WKWebView?
    var onState: ((PlayerState) -> Void)?
    /// kind is "ready", "error", or a label for the event log such as "queue".
    var onEvent: ((_ kind: String, _ detail: String) -> Void)?
    /// The signed-in user's playlists.
    var onPlaylists: (([Playlist]) -> Void)?
    var onAccount: ((Account) -> Void)?
    /// A media key or Control Center command that WebKit gave to the page:
    /// the Media Session action ("play", "nexttrack", ...) and, for "seekto",
    /// the position.
    var onRemote: ((_ action: String, _ seconds: Double?) -> Void)?
    /// A page of a playlist's tracks: new items, whether they follow the
    /// ones before, and whether there are more.
    var onTracks: ((_ listID: String, _ items: [Track], _ append: Bool, _ more: Bool) -> Void)?
    var onLyrics: ((Lyrics) -> Void)?

    static let script = "player"

    /// Replaces all user scripts. `pageConfig` becomes `window.__bsideConfig`.
    /// player.js stays silent outside music.youtube.com, e.g. during sign-in.
    func install(in controller: WKUserContentController, pageConfig: [String: Any]) {
        controller.removeAllUserScripts()
        controller.removeScriptMessageHandler(forName: Self.handlerName)
        controller.add(self, name: Self.handlerName)

        let config = "window.__bsideConfig = \(Self.json(pageConfig));" + Self.mediaSessionHandlers
        controller.addUserScript(WKUserScript(source: config, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        guard let url = Bundle.main.url(forResource: Self.script, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            onEvent?("error", "\(Self.script).js is missing from the app bundle")
            return
        }
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    /// WebKit registers the playing element with the system on its own, as
    /// Safari does, so some media key presses reach WebKit instead of the
    /// app's MPRemoteCommandCenter. Without Media Session handlers WebKit
    /// then pauses or plays the element itself, behind the app's back. With
    /// handlers it calls them instead (WebKit's
    /// `MediaElementSession::didReceiveRemoteControlCommand`), so these
    /// hand every action to the app, which treats it like its own command.
    /// The page's player may not replace them.
    private static let mediaSessionHandlers = """
    (function () {
      var session = navigator.mediaSession;
      if (!session) return;
      var set = session.setActionHandler.bind(session);
      ['play', 'pause', 'stop', 'nexttrack', 'previoustrack', 'seekto'].forEach(function (action) {
        try {
          set(action, function (details) {
            window.webkit.messageHandlers.bside.postMessage({ type: 'remote', action: action,
              seconds: details && typeof details.seekTime === 'number' ? details.seekTime : null });
          });
        } catch (e) {}
      });
      session.setActionHandler = function () {};
    })();
    """

    /// Calls `window.__bside.<method>(args...)`. Arguments are JSON-encoded.
    func call(_ method: String, _ args: Any...) {
        let encoded = Self.json(args)
        let script = "window.__bside && window.__bside.\(method).apply(null, \(encoded)); undefined"
        webView?.evaluateJavaScript(script) { [weak self] _, error in
            if let error { self?.onEvent?("error", "\(method): \(error.localizedDescription)") }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "state":
            var state = PlayerState()
            state.title = body["title"] as? String ?? ""
            state.artist = body["artist"] as? String ?? ""
            state.artworkURL = (body["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            state.videoID = body["videoId"] as? String ?? ""
            state.position = (body["position"] as? NSNumber)?.doubleValue ?? 0
            state.duration = (body["duration"] as? NSNumber)?.doubleValue ?? 0
            state.isPlaying = body["playing"] as? Bool ?? false
            state.isAd = body["ad"] as? Bool ?? false
            state.queueIndex = (body["queueIndex"] as? NSNumber)?.intValue ?? -1
            state.queueCount = (body["queueCount"] as? NSNumber)?.intValue ?? 0
            state.queueHasMore = body["queueHasMore"] as? Bool ?? false
            state.like = body["like"] as? String ?? ""
            onState?(state)
        case "account":
            let signedIn = body["signedIn"] as? Bool ?? false
            onAccount?(signedIn
                ? .signedIn(name: body["name"] as? String ?? "", handle: body["handle"] as? String ?? "",
                            photoURL: (body["photo"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) })
                : .signedOut)
        case "lyrics":
            onLyrics?(Lyrics(videoID: body["videoId"] as? String ?? "",
                             text: body["text"] as? String ?? "",
                             source: body["source"] as? String ?? "",
                             page: body["page"] as? String ?? ""))
        case "tracks":
            let items = body["items"] as? [[String: Any]] ?? []
            // Positions are filled in by the receiver, which knows the count so far.
            onTracks?(body["listId"] as? String ?? "", items.compactMap { item in
                guard let video = item["videoId"] as? String else { return nil }
                return Track(index: 0, videoID: video,
                             title: item["title"] as? String ?? "",
                             artist: item["artist"] as? String ?? "",
                             artworkURL: (item["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) })
            }, body["append"] as? Bool ?? false, body["more"] as? Bool ?? false)
        case "remote":
            onRemote?(body["action"] as? String ?? "", (body["seconds"] as? NSNumber)?.doubleValue)
        case "event":
            onEvent?(body["kind"] as? String ?? "", body["detail"] as? String ?? "")
        case "playlists":
            let items = body["items"] as? [[String: Any]] ?? []
            onPlaylists?(items.compactMap { item in
                guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
                return Playlist(id: id, title: title,
                                subtitle: item["subtitle"] as? String ?? "",
                                artworkURL: (item["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) })
            })
        default:
            break
        }
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}
