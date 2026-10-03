import Foundation
import WebKit

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
    /// Results for one search: the query and kind they answer, so a late
    /// answer to an older query can be dropped.
    var onSearch: ((_ query: String, _ kind: SearchKind, _ items: [MusicItem]) -> Void)?
    /// An artist's or a collection's page, or nil with its ID when it failed.
    var onArtist: ((_ id: String, _ page: ArtistPage?) -> Void)?
    var onCollection: ((_ id: String, _ page: CollectionPage?) -> Void)?
    var onLyrics: ((Lyrics) -> Void)?
    /// What plays after the current track; `index` is the place in the queue.
    var onUpNext: (([Track]) -> Void)?
    /// A playlist was created ("created"), or a track added to one ("added",
    /// or "already" when it was there).
    var onPlaylistEdit: ((_ action: String, _ playlistID: String, _ title: String, _ videoID: String) -> Void)?

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

    /// Calls `window.__bside.<method>(args...)` and waits for what it
    /// returns (a promise is awaited).
    func value(_ method: String, _ args: [Any]) async throws -> Any? {
        guard let webView else { throw CancellationError() }
        return try await webView.callAsyncJavaScript(
            "return await window.__bside[method].apply(null, args)",
            arguments: ["method": method, "args": args], in: nil, contentWorld: .page)
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
            state.isBuffering = body["buffering"] as? Bool ?? false
            state.isAd = body["ad"] as? Bool ?? false
            if state.isAd {
                state.adLeft = (body["adLeft"] as? NSNumber)?.doubleValue ?? -1
                state.adLeftAt = Date()
                state.adIndex = (body["adIndex"] as? NSNumber)?.intValue ?? 0
                state.adCount = (body["adCount"] as? NSNumber)?.intValue ?? 0
            }
            state.queueIndex = (body["queueIndex"] as? NSNumber)?.intValue ?? -1
            state.queueCount = (body["queueCount"] as? NSNumber)?.intValue ?? 0
            state.queueHasMore = body["queueHasMore"] as? Bool ?? false
            state.like = body["like"] as? String ?? ""
            state.artistID = body["artistId"] as? String ?? ""
            state.albumID = body["albumId"] as? String ?? ""
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
                             artworkURL: (item["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                             setVideoID: item["setVideoId"] as? String ?? "",
                             heldVideoID: item["heldVideoId"] as? String ?? "",
                             removable: item["removable"] as? Bool ?? false,
                             artistID: item["artistId"] as? String ?? "",
                             albumID: item["albumId"] as? String ?? "",
                             liked: item["like"] as? String == "LIKE",
                             length: item["length"] as? String ?? "")
            }, body["append"] as? Bool ?? false, body["more"] as? Bool ?? false)
        case "upNext":
            let items = body["items"] as? [[String: Any]] ?? []
            onUpNext?(items.compactMap { item in
                guard let video = item["videoId"] as? String, let index = (item["index"] as? NSNumber)?.intValue else { return nil }
                return Track(index: index, videoID: video,
                             title: item["title"] as? String ?? "",
                             artist: item["artist"] as? String ?? "",
                             artworkURL: (item["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                             artistID: item["artistId"] as? String ?? "",
                             albumID: item["albumId"] as? String ?? "",
                             liked: item["like"] as? String == "LIKE",
                             length: item["length"] as? String ?? "")
            })
        case "search":
            onSearch?(body["query"] as? String ?? "", SearchKind(rawValue: body["kind"] as? String ?? "") ?? .songs,
                      MusicItem.list(body["items"]))
        case "artist":
            let id = body["id"] as? String ?? ""
            guard body["failed"] as? Bool != true else { return onArtist?(id, nil) ?? () }
            let shelves = ((body["shelves"] as? [[String: Any]]) ?? []).enumerated().map { index, shelf in
                ArtistPage.Shelf(id: index, title: shelf["title"] as? String ?? "", items: MusicItem.list(shelf["items"]))
            }
            onArtist?(id, ArtistPage(id: id, name: body["name"] as? String ?? "",
                                     artworkURL: (body["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                                     songsPlaylistID: body["songsPlaylistId"] as? String ?? "",
                                     songs: MusicItem.list(body["songs"]), shelves: shelves))
        case "collection":
            let id = body["id"] as? String ?? ""
            guard body["failed"] as? Bool != true else { return onCollection?(id, nil) ?? () }
            onCollection?(id, CollectionPage(id: id, isAlbum: body["album"] as? Bool ?? false,
                                             title: body["title"] as? String ?? "",
                                             subtitle: body["subtitle"] as? String ?? "",
                                             artist: body["artist"] as? String ?? "",
                                             artistID: body["artistId"] as? String ?? "",
                                             artworkURL: (body["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                                             playlistID: body["playlistId"] as? String ?? "",
                                             tracks: MusicItem.list(body["tracks"])))
        case "remote":
            onRemote?(body["action"] as? String ?? "", (body["seconds"] as? NSNumber)?.doubleValue)
        case "event":
            onEvent?(body["kind"] as? String ?? "", body["detail"] as? String ?? "")
        case "playlistEdit":
            onPlaylistEdit?(body["action"] as? String ?? "", body["playlistId"] as? String ?? "",
                            body["title"] as? String ?? "", body["videoId"] as? String ?? "")
        case "playlists":
            let items = body["items"] as? [[String: Any]] ?? []
            onPlaylists?(items.compactMap { item in
                guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
                return Playlist(id: id, title: title,
                                subtitle: item["subtitle"] as? String ?? "",
                                artworkURL: (item["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                                isOwn: item["own"] as? Bool ?? false)
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
