import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case nowPlaying, vibe, playlists, explore

    var id: String { rawValue }

    /// The pages with a bar of their own right under the window's top bar.
    static let withBar: Set<Page?> = [.playlists, .explore]

    var title: String {
        switch self {
        case .vibe: return "Vibes"
        case .playlists: return "Playlists"
        case .nowPlaying: return "Now Playing"
        case .explore: return "Explore"
        }
    }

    /// Command-1, 2, 3, in page order.
    var shortcutKey: Character {
        Character(String((Page.allCases.firstIndex(of: self) ?? 0) + 1))
    }

    var shortcutLabel: String { "⌘\(shortcutKey)" }

    /// Waves, a list with play, a record, a magnifier.
    var symbol: String {
        switch self {
        case .vibe: return "waveform"
        case .playlists: return "music.note.list"
        case .nowPlaying: return "opticaldisc"
        case .explore: return "magnifyingglass"
        }
    }
}

/// Which page of the main window is showing. Shared with the menu bar.
@MainActor
final class Navigation: ObservableObject {
    @Published var page: Page? = UserDefaults.standard.string(forKey: Keys.page).flatMap(Page.init) ?? .nowPlaying
    /// Now Playing shows the lyrics in place of the artwork.
    @Published var showsLyrics = false {
        didSet { if showsLyrics { showsQueue = false } }
    }
    /// Now Playing shows what plays next in place of the artwork. One of
    /// the two at a time.
    @Published var showsQueue = false {
        didSet { if showsQueue { showsLyrics = false } }
    }
    /// The New Playlist sheet, and the track to put in it, if any.
    @Published var newPlaylist: NewPlaylistRequest?
    /// The Rename sheet, for this playlist.
    @Published var renamingPlaylist: Playlist?
    /// The pages opened on Explore over the search, the last one showing.
    @Published private(set) var explorePath: [ExploreRoute] = []
    /// The page an Explore page was opened from, where Back returns from
    /// the first one; nil when it was opened on Explore itself.
    private var exploreReturn: Page?
    var exploreOrigin: Page? { exploreReturn }

    /// Opens an artist's or an album's page on Explore. From another page it
    /// starts over, and Back on it returns to that page.
    func open(_ route: ExploreRoute) {
        if let current = page, current != .explore {
            explorePath = [route]
            exploreReturn = current
        } else if explorePath.last != route {
            explorePath.append(route)
        }
        page = .explore
    }

    /// One page back on Explore: the one before, the search, or the page the
    /// first one was opened from.
    func exploreBack() {
        guard !explorePath.isEmpty else { return }
        explorePath.removeLast()
        if explorePath.isEmpty, let origin = exploreReturn {
            exploreReturn = nil
            page = origin
        }
    }

    /// Snapshots only.
    func setExplorePath(_ path: [ExploreRoute]) { explorePath = path }
}

/// A page Explore can open over its search.
enum ExploreRoute: Equatable {
    /// An artist, by browse ID ("UC…"), and the name to show while it loads.
    case artist(id: String, name: String)
    /// An album ("MPREb…") or a playlist ("VL…"), by browse ID.
    case collection(id: String, title: String)

    var title: String {
        switch self {
        case .artist(_, let name): return name
        case .collection(_, let title): return title
        }
    }

    /// The route to what a tile or a row stands for, if it opens a page.
    init?(_ item: MusicItem) {
        switch item.kind {
        case .artist where !item.browseID.isEmpty: self = .artist(id: item.browseID, name: item.title)
        case .album where !item.browseID.isEmpty, .playlist where !item.browseID.isEmpty:
            self = .collection(id: item.browseID, title: item.title)
        default: return nil
        }
    }
}
