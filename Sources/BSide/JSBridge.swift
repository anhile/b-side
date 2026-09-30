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

    var hasPrevious: Bool { queueIndex > 0 }
    var hasNext: Bool { queueIndex >= 0 && (queueIndex < queueCount - 1 || queueHasMore) }
}

struct Playlist: Identifiable, Equatable {
    let id: String
    let title: String
    var subtitle = ""
    var artworkURL: URL?
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

    static let script = "player"

    /// Replaces all user scripts. `pageConfig` becomes `window.__bsideConfig`.
    /// player.js stays silent outside music.youtube.com, e.g. during sign-in.
    func install(in controller: WKUserContentController, pageConfig: [String: Any]) {
        controller.removeAllUserScripts()
        controller.removeScriptMessageHandler(forName: Self.handlerName)
        controller.add(self, name: Self.handlerName)

        let config = "window.__bsideConfig = \(Self.json(pageConfig));"
        controller.addUserScript(WKUserScript(source: config, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        guard let url = Bundle.main.url(forResource: Self.script, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            onEvent?("error", "\(Self.script).js is missing from the app bundle")
            return
        }
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

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
            onState?(state)
        case "account":
            let signedIn = body["signedIn"] as? Bool ?? false
            onAccount?(signedIn ? .signedIn(name: body["name"] as? String ?? "") : .signedOut)
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
