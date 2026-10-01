import Foundation

/// Time-synced lyrics, from two sources, tried in order (see
/// docs/research/live-lyrics.md):
///
/// 1. YouTube Music's own lyrics page, asked for as its Android app: the web
///    client gets only the text. Sent from here without cookies, so it is
///    not tied to the account and does not touch the player page.
/// 2. LRCLIB, a free, open database of timed lyrics, matched by title,
///    artist and length. For tracks YouTube Music has no timings for, videos
///    among them.
///
/// Each answers in well under a second; nothing is asked until the lyrics
/// are opened.
enum TimedLyrics {
    struct Result {
        let lines: [LyricLine]
        let source: String
    }

    static func find(page: String, title: String, artist: String, duration: Double) async -> Result? {
        if !page.isEmpty, let result = await youTube(page: page) { return result }
        guard !title.isEmpty, duration > 0 else { return nil }
        return await lrclib(title: title, artist: artist, duration: duration)
    }

    // MARK: - YouTube Music

    /// ytmusicapi's client version, which Google still answered on 2026-09-30.
    private static let androidVersion = "7.21.50"
    private static let browse = URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = Tuning.lyricsWait
        return URLSession(configuration: configuration)
    }()

    private static func youTube(page: String) async -> Result? {
        var request = URLRequest(url: browse)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("21", forHTTPHeaderField: "X-YouTube-Client-Name") // ANDROID_MUSIC
        request.setValue(androidVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        let context: [String: Any] = ["client": ["clientName": "ANDROID_MUSIC", "clientVersion": androidVersion,
                                                 "androidSdkVersion": 34, "hl": "en", "gl": "US"]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["context": context, "browseId": page])
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            EventLog.write("lyrics\tYouTube Music timed: no answer")
            return nil
        }
        // About 600 KB, nearly all of it the Android app's UI; the timings
        // are near the start. Only that object is parsed.
        guard let model = JSONCut.object(after: "timedLyricsModel", in: data),
              let lyricsData = model["lyricsData"] as? [String: Any],
              let cues = lyricsData["timedLyricsData"] as? [[String: Any]], !cues.isEmpty else {
            EventLog.write("lyrics\tYouTube Music timed: none (\(data.count / 1024) KB)")
            return nil
        }
        let lines: [LyricLine] = cues.compactMap { cue in
            guard let range = cue["cueRange"] as? [String: Any],
                  let start = Double("\(range["startTimeMilliseconds"] ?? "")") else { return nil }
            return LyricLine(start: start / 1000, text: cue["lyricLine"] as? String ?? "")
        }
        guard !lines.isEmpty else { return nil }
        EventLog.write("lyrics\tYouTube Music timed: \(lines.count) lines (\(data.count / 1024) KB)")
        return Result(lines: lines, source: lyricsData["sourceMessage"] as? String ?? "")
    }

    // MARK: - LRCLIB

    private static let lrclib = URL(string: "https://lrclib.net/api/")!
    /// LRCLIB asks clients to say who they are.
    private static let agent = "B-Side (open-source YouTube Music player for macOS)"

    private static func lrclib(title: String, artist: String, duration: Double) async -> Result? {
        let seconds = Int(duration.rounded())
        let attempts: [(String, [URLQueryItem])] = [
            ("get", [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist),
                     .init(name: "duration", value: "\(seconds)")]),
            ("get", [.init(name: "track_name", value: cleanTitle(title)),
                     .init(name: "artist_name", value: firstArtist(artist)),
                     .init(name: "duration", value: "\(seconds)")]),
            ("search", [.init(name: "track_name", value: cleanTitle(title)),
                        .init(name: "artist_name", value: firstArtist(artist))]),
        ]
        var tried = Set<String>()
        for (endpoint, query) in attempts {
            var components = URLComponents(url: lrclib.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
            components.queryItems = query
            guard let url = components.url, tried.insert(url.absoluteString).inserted else { continue }
            guard let data = await get(url) else { continue }
            let json = try? JSONSerialization.jsonObject(with: data)
            let items = (json as? [[String: Any]]) ?? (json as? [String: Any]).map { [$0] } ?? []
            // A different length is a different edit, and its timings would drift.
            let match = items
                .filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
                .filter { abs(($0["duration"] as? Double ?? 0) - duration) <= Tuning.lyricsLengthTolerance }
                .min { abs(($0["duration"] as? Double ?? 0) - duration) < abs(($1["duration"] as? Double ?? 0) - duration) }
            if let lrc = match?["syncedLyrics"] as? String {
                let lines = parseLRC(lrc)
                if !lines.isEmpty {
                    EventLog.write("lyrics\tLRCLIB \(endpoint): \(lines.count) lines")
                    return Result(lines: lines, source: "Source: LRCLIB")
                }
            }
        }
        EventLog.write("lyrics\tLRCLIB: none")
        return nil
    }

    /// One retry: LRCLIB answers 503 now and then.
    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            guard let (data, response) = try? await session.data(for: request) else { continue }
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: return data
            case 503: continue
            default: return nil
            }
        }
        return nil
    }

    /// "Song (feat. X) [Official Video]" → "Song"; "Song - Remastered 2011" → "Song".
    static func cleanTitle(_ title: String) -> String {
        var clean = title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: #"\s+-\s+.*(remaster|version|edit|live|mix).*$"#, with: "",
                                           options: [.regularExpression, .caseInsensitive])
        return clean.trimmingCharacters(in: .whitespaces)
    }

    /// "A & B", "A, B", "A feat. B" → "A".
    static func firstArtist(_ artist: String) -> String {
        let parts = artist.components(separatedBy: CharacterSet(charactersIn: ",&"))
        let first = parts.first ?? artist
        return first.replacingOccurrences(of: #"\s+(feat\.?|ft\.?|x|and)\s+.*$"#, with: "",
                                          options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// "[01:02.34] words" lines; other lines are skipped.
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        lrc.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.first == "[", let close = line.firstIndex(of: "]") else { return nil }
            let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { return nil }
            let words = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return LyricLine(start: minutes * 60 + seconds, text: words)
        }
    }
}

/// Cuts one JSON object out of a large reply by its key and parses only
/// that, as player.js does with its responses.
enum JSONCut {
    static func object(after key: String, in data: Data) -> [String: Any]? {
        let marker = Data("\"\(key)\":".utf8)
        guard let found = data.range(of: marker) else { return nil }
        let bytes = [UInt8](data[found.upperBound...])
        guard bytes.first == UInt8(ascii: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        for (offset, byte) in bytes.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"): depth += 1
            case UInt8(ascii: "}"):
                depth -= 1
                if depth == 0 {
                    let slice = Data(bytes[0...offset])
                    return (try? JSONSerialization.jsonObject(with: slice)) as? [String: Any]
                }
            default: break
            }
        }
        return nil
    }
}
