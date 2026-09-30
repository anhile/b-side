// Experiment 3: can the timed lyrics be asked for from Swift, and from inside
// a music.youtube.com page, and does it matter?
//
// For each video ID given on the command line:
//   swift  - URLSession, no cookies: the web client's /next for the lyrics
//            page, then /browse as the Android client, with and without the
//            Android User-Agent.
//   page   - a WKWebView on music.youtube.com (a private, signed-out store):
//            the same two requests with fetch(), with the page's cookies and
//            without them.
// Prints one line per attempt: status, whether timed lyrics came, lines, KB, ms.
// No lyrics text is printed.

import AppKit
import WebKit

let ytm = URL(string: "https://music.youtube.com/")!
let androidVersion = "7.21.50"
let webAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

func log(_ parts: String...) {
    print(parts.joined(separator: "\t"))
    fflush(stdout)
}

/// Counts the timed lines in a /browse reply without keeping the text.
func timedLines(_ data: Data) -> Int? {
    guard let tree = try? JSONSerialization.jsonObject(with: data) else { return nil }
    func find(_ node: Any, _ key: String) -> Any? {
        if let dict = node as? [String: Any] {
            if let value = dict[key] { return value }
            for value in dict.values { if let hit = find(value, key) { return hit } }
        } else if let array = node as? [Any] {
            for value in array { if let hit = find(value, key) { return hit } }
        }
        return nil
    }
    guard let model = find(tree, "timedLyricsModel") as? [String: Any],
          let data = model["lyricsData"] as? [String: Any],
          let cues = data["timedLyricsData"] as? [Any] else { return nil }
    return cues.count
}

// MARK: - Swift

func post(_ endpoint: String, _ body: [String: Any], headers: [String: String]) async -> (Int, Data, Int) {
    var request = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
    request.httpMethod = "POST"
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    let session = URLSession(configuration: configuration)
    let start = Date()
    do {
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data, Int(Date().timeIntervalSince(start) * 1000))
    } catch {
        return (0, Data(), Int(Date().timeIntervalSince(start) * 1000))
    }
}

func lyricsPage(_ video: String, webVersion: String) async -> String? {
    let context: [String: Any] = ["client": ["clientName": "WEB_REMIX", "clientVersion": webVersion, "hl": "en", "gl": "US"]]
    let (_, data, _) = await post("next", ["videoId": video, "context": context],
                                  headers: ["User-Agent": webAgent, "Origin": "https://music.youtube.com"])
    let text = String(decoding: data, as: UTF8.self)
    guard let range = text.range(of: #""browseId":"(MPLYt[^"]*)""#, options: .regularExpression) else { return nil }
    return String(text[range].dropFirst(12).dropLast())
}

func swiftAttempts(_ video: String, webVersion: String) async {
    guard let page = await lyricsPage(video, webVersion: webVersion) else {
        return log(video, "swift", "no lyrics page")
    }
    let context: [String: Any] = ["client": ["clientName": "ANDROID_MUSIC", "clientVersion": androidVersion,
                                             "androidSdkVersion": 34, "hl": "en", "gl": "US"]]
    for withAgent in [true, false] {
        var headers = ["X-YouTube-Client-Name": "21", "X-YouTube-Client-Version": androidVersion]
        if withAgent {
            headers["User-Agent"] = "com.google.android.apps.youtube.music/\(androidVersion) (Linux; U; Android 14) gzip"
        }
        let (status, data, ms) = await post("browse", ["browseId": page, "context": context], headers: headers)
        let lines = timedLines(data)
        log(video, "swift", withAgent ? "android agent" : "default agent", "HTTP \(status)",
            lines.map { "timed \($0) lines" } ?? "no timed", "\(data.count / 1024) KB", "\(ms) ms")
    }
}

// MARK: - Page

@MainActor
final class Page: NSObject, WKNavigationDelegate {
    let web: WKWebView
    var loaded: CheckedContinuation<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        web.customUserAgent = webAgent
        super.init()
        web.navigationDelegate = self
    }

    func load() async {
        let consent = HTTPCookie(properties: [.domain: ".youtube.com", .path: "/", .name: "SOCS", .value: "CAI",
                                              .secure: "TRUE", .expires: Date().addingTimeInterval(3600)])!
        await web.configuration.websiteDataStore.httpCookieStore.setCookie(consent)
        await withCheckedContinuation { continuation in
            loaded = continuation
            web.load(URLRequest(url: ytm))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in loaded?.resume(); loaded = nil }
    }

    func attempts(_ video: String) async {
        let script = """
        const context = ytcfg.get('INNERTUBE_CONTEXT');
        const next = await fetch('/youtubei/v1/next?prettyPrint=false', {
          method: 'POST', credentials: 'include', headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({context: context, videoId: video}) }).then(r => r.text());
        const page = (next.match(/"browseId":"(MPLYt[^"]*)"/) || [])[1];
        if (!page) return ['no lyrics page'];
        const android = {client: {clientName: 'ANDROID_MUSIC', clientVersion: version, androidSdkVersion: 34,
                                  hl: 'en', gl: 'US'}};
        const out = [];
        for (const credentials of ['include', 'omit']) {
          const start = performance.now();
          const response = await fetch('/youtubei/v1/browse?prettyPrint=false', {
            method: 'POST', credentials: credentials,
            headers: {'Content-Type': 'application/json', 'X-YouTube-Client-Name': '21',
                      'X-YouTube-Client-Version': version},
            body: JSON.stringify({context: android, browseId: page}) });
          const text = await response.text();
          const at = text.indexOf('"timedLyricsData":');
          let lines = 0;
          if (at >= 0) lines = (text.slice(at).match(/"cueRange"/g) || []).length;
          out.push(credentials + ' cookies\\tHTTP ' + response.status + '\\t'
                   + (lines ? 'timed ' + lines + ' lines' : 'no timed') + '\\t'
                   + Math.round(text.length / 1024) + ' KB\\t' + Math.round(performance.now() - start) + ' ms');
        }
        return out;
        """
        do {
            let result = try await web.callAsyncJavaScript(script, arguments: ["video": video, "version": androidVersion],
                                                           contentWorld: .page)
            for line in (result as? [String]) ?? ["no result"] { log(video, "page", line) }
        } catch {
            log(video, "page", "error: \(error)")
        }
    }
}

// MARK: - Run

@MainActor
func run() async {
    let videos = Array(CommandLine.arguments.dropFirst())
    let (_, home, _) = await { () async -> (Int, Data, Int) in
        var request = URLRequest(url: ytm)
        request.setValue(webAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        let start = Date()
        let (data, response) = (try? await URLSession.shared.data(for: request)) ?? (Data(), URLResponse())
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data, Int(Date().timeIntervalSince(start) * 1000))
    }()
    let html = String(decoding: home, as: UTF8.self)
    let version = html.range(of: #""INNERTUBE_CLIENT_VERSION":"[^"]+""#, options: .regularExpression)
        .map { String(html[$0].dropFirst(28).dropLast()) } ?? "1.20260927.17.00"
    log("start", "web client \(version)", "android \(androidVersion)", "\(videos.count) videos")

    for video in videos { await swiftAttempts(video, webVersion: version) }

    let page = Page()
    await page.load()
    log("page", "loaded \(page.web.url?.absoluteString ?? "?")")
    for video in videos { await page.attempts(video) }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { await run() }
DispatchQueue.main.asyncAfter(deadline: .now() + 120) { log("timeout"); exit(1) }
app.run()
