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
    /// Playing, but waiting for data: the clock stands.
    var isBuffering = false
    var isAd = false
    /// Seconds the ad still ran when the page reported at `adLeftAt`, -1
    /// when unknown; its place in a run of ads, 0 when the player shows none.
    var adLeft: Double = -1
    var adLeftAt = Date.distantPast
    var adIndex = 0
    var adCount = 0
    var queueIndex = -1
    var queueCount = 0
    /// The queue has more pages that are not loaded yet.
    var queueHasMore = false
    /// "LIKE", "INDIFFERENT", or "" when unknown.
    var like = ""
    /// The pages behind the artist's and the album's names, "" when unknown.
    var artistID = ""
    var albumID = ""

    var isLiked: Bool { like == "LIKE" }

    /// Seconds until the ad ends, nil when the page could not tell.
    func adRemaining(at date: Date) -> Double? {
        guard isAd, adLeft >= 0 else { return nil }
        return isPlaying ? max(0, adLeft - max(0, date.timeIntervalSince(adLeftAt))) : adLeft
    }

    /// More ads follow this one, so its end is not the music's return.
    var moreAdsFollow: Bool { adCount > 0 && adIndex < adCount }

    var hasPrevious: Bool { queueIndex > 0 }
    var hasNext: Bool { queueIndex >= 0 && (queueIndex < queueCount - 1 || queueHasMore) }
}

struct Playlist: Identifiable, Equatable {
    let id: String
    let title: String
    var subtitle = ""
    var artworkURL: URL?
    /// The library says it is the user's (it can be deleted).
    var isOwn = false
}

/// What a search on the Explore page looks for.
enum SearchKind: String, CaseIterable, Identifiable {
    case songs, albums, artists, playlists

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// One thing on YouTube Music, as a row or a tile on the Explore page: a
/// song (a video ID, played with its radio after it), an album or playlist
/// (opened by its browse ID, played by its playlist ID), or an artist. The
/// identity is the position in its list.
struct MusicItem: Identifiable, Equatable {
    enum Kind: String { case song, album, playlist, artist }

    let id: Int
    var kind = Kind.song
    var videoID = ""
    var playlistID = ""
    var browseID = ""
    let title: String
    var subtitle = ""
    /// A track's length, "3:41", where the list shows it.
    var detail = ""
    var artworkURL: URL?
    /// The pages behind the artist's and the album's names, when known.
    var artistID = ""
    var albumID = ""
    /// Liked when the list was loaded; see `PlayerController.isLiked`.
    var liked = false

    init(id: Int, kind: Kind = .song, videoID: String = "", playlistID: String = "", browseID: String = "",
         title: String, subtitle: String = "", detail: String = "", artworkURL: URL? = nil,
         artistID: String = "", albumID: String = "") {
        self.id = id
        self.kind = kind
        self.videoID = videoID
        self.playlistID = playlistID
        self.browseID = browseID
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.artworkURL = artworkURL
        self.artistID = artistID
        self.albumID = albumID
    }

    init?(_ body: [String: Any], id: Int) {
        guard let title = body["title"] as? String else { return nil }
        self.init(id: id, kind: Kind(rawValue: body["kind"] as? String ?? "") ?? .song,
                  videoID: body["videoId"] as? String ?? "", playlistID: body["playlistId"] as? String ?? "",
                  browseID: body["browseId"] as? String ?? "", title: title,
                  subtitle: body["subtitle"] as? String ?? "", detail: body["detail"] as? String ?? "",
                  artworkURL: (body["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                  artistID: body["artistId"] as? String ?? "", albumID: body["albumId"] as? String ?? "")
        liked = body["like"] as? String == "LIKE"
    }

    static func list(_ value: Any?) -> [MusicItem] {
        ((value as? [[String: Any]]) ?? []).enumerated().compactMap { MusicItem($1, id: $0) }
    }
}

/// An artist's page: top songs, the playlist of all their songs, and rows
/// of albums, singles, playlists and related artists, titled by YouTube Music.
struct ArtistPage: Equatable {
    struct Shelf: Equatable, Identifiable {
        let id: Int
        let title: String
        let items: [MusicItem]
    }

    let id: String
    let name: String
    var artworkURL: URL?
    var songsPlaylistID = ""
    var songs: [MusicItem] = []
    var shelves: [Shelf] = []
}

/// An album's or a playlist's page: its header, its tracks, and the
/// playlist ID that plays it.
struct CollectionPage: Equatable {
    let id: String
    var isAlbum = false
    let title: String
    var subtitle = ""
    var artist = ""
    var artistID = ""
    var artworkURL: URL?
    var playlistID = ""
    var tracks: [MusicItem] = []
}

/// One track in a playlist's list. A playlist can hold a track twice, so the
/// identity is the position.
struct Track: Identifiable, Equatable {
    var index: Int
    let videoID: String
    let title: String
    let artist: String
    var artworkURL: URL?
    /// The entry's place in its playlist, and the version the playlist holds
    /// (it may differ from the one that plays); empty outside a playlist.
    var setVideoID = ""
    var heldVideoID = ""
    /// YouTube Music lets the user take it out: the playlist is theirs.
    var removable = false
    /// The pages behind the artist's and the album's names, when known.
    var artistID = ""
    var albumID = ""
    /// Liked when the list was loaded; see `PlayerController.isLiked`.
    var liked = false
    /// "3:41", when the list says.
    var length = ""
    var id: Int { index }
}
