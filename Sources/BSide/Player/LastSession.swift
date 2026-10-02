import Foundation

/// What played when B-Side was last open. The next launch shows it paused
/// where it stopped, as Music and Spotify do; Play goes on from there, in
/// the playlist or vibe it came from. Nothing is loaded for it until Play.
struct LastSession: Codable, Equatable {
    var videoID: String
    var title: String
    var artist: String
    var artwork: String?
    var artistID: String
    var albumID: String
    var like: String
    var position: Double
    var duration: Double
    /// The list it played from, and whether shuffled; nil for a radio.
    var listID: String?
    var shuffle: Bool
    /// "mood" or "playlist" with its ID, or "other".
    var sourceKind: String
    var sourceID: String
    /// The name of a list from Explore, which the library does not have.
    var listTitle: String?
    var listKind: String?

    static func load() -> LastSession? {
        guard let data = Settings.defaults.data(forKey: Keys.lastSession) else { return nil }
        return try? JSONDecoder().decode(LastSession.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Settings.defaults.set(data, forKey: Keys.lastSession)
    }

    static func clear() {
        Settings.defaults.removeObject(forKey: Keys.lastSession)
    }
}
