import Foundation

/// The optional B-Side server that reads a vibe's words with a larger model
/// (server/ in this repository). Off by default: the words leave the Mac
/// only when the user turns it on in Settings. The app still checks every
/// artist against YouTube Music search, as with Apple's model.
@MainActor
enum VibeServer {
    static let defaultAddress = "https://api.b-side.anhile.com"

    /// The server is slower than the Mac's own model is to fall back to.
    private static let timeout: TimeInterval = 10

    /// `-vibeServer <url>` turns it on with that address, for testing.
    static var isOn: Bool {
        UserDefaults.standard.string(forKey: Keys.vibeServerDebug) != nil || Settings.bool(Keys.vibeServer)
    }

    static var address: URL? {
        let text = UserDefaults.standard.string(forKey: Keys.vibeServerDebug)
            ?? Settings.defaults.string(forKey: Keys.vibeServerAddress) ?? defaultAddress
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true,
              url.host != nil else { return nil }
        return url
    }

    /// A random ID made once, so the server can count this Mac's vibes
    /// without knowing anything about it.
    static var installID: String {
        if let id = Settings.defaults.string(forKey: Keys.vibeInstallID) { return id }
        let id = UUID().uuidString.lowercased()
        Settings.defaults.set(id, forKey: Keys.vibeInstallID)
        return id
    }

    enum Failure: Error {
        /// The server said no, with its reason for the user ("This Mac has
        /// made its 10 vibes this month.").
        case refused(String)
        case unreachable
    }

    private struct Reply: Decodable {
        let name: String
        let tags: [String]
        let artists: [String]
        let vocals: String
    }

    private struct Refusal: Decodable { let error: String }

    static func read(_ words: String, mix: VibeSpec.Mix) async throws -> VibeMaker.Reading {
        guard let base = address else { throw Failure.unreachable }
        var request = URLRequest(url: base.appending(path: "v1/vibe"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["words": words, "mix": mix.key, "install": installID])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if let refusal = try? JSONDecoder().decode(Refusal.self, from: data) { throw Failure.refused(refusal.error) }
            throw Failure.unreachable
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        return VibeMaker.Reading(name: reply.name, tags: reply.tags, artists: reply.artists,
                                 vocals: VibeSpec.Vocals(model: reply.vocals), matchedMoods: nil, byServer: true)
    }

    struct Health: Equatable {
        let open: Bool
        let perMonth: Int
    }

    /// Whether the server makes vibes now; nil when it cannot be reached.
    static func health(at base: URL) async -> Health? {
        let request = URLRequest(url: base.appending(path: "v1/health"), timeoutInterval: timeout)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Health(open: body["vibes"] as? Bool ?? false, perMonth: body["perMonth"] as? Int ?? 0)
    }
}

extension VibeSpec.Mix {
    /// The server's name for it.
    var key: String {
        switch self {
        case .familiar: "familiar"
        case .both: "both"
        case .new: "new"
        }
    }
}
