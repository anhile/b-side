import AppKit
import SwiftUI

/// One job: find something on YouTube Music and play it. A search field in
/// the page's glass bar, with the kind of result under it once there is a
/// query. A song plays on click; an album, a playlist or an artist opens its
/// page over the search, and Back in the bar returns.
struct ExplorePage: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation
    @Environment(\.footerRoom) private var footerRoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var kind = SearchKind.songs
    @State private var barHeight: CGFloat = 0
    /// Counts the arrivals on the search, each of which puts the typing there.
    @State private var focusRequest = 0

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                if let route = navigation.explorePath.last {
                    routePage(route)
                        .id(navigation.explorePath.count)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                } else {
                    searchContent
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                }
            }
            .clipped()
            .environment(\.exploreBarHeight, barHeight)
            bar
        }
        .animation(.easeInOut(duration: Theme.Motion.page), value: navigation.explorePath.count)
        // Arriving on the search, by a tab, a shortcut or Back: type at once.
        .onChange(of: navigation.page) {
            if showsSearch { focusRequest += 1 }
            // Leaving: give the keyboard back, so Space plays and pauses again.
            if navigation.page != .explore, let window = MainWindow.window, window.firstResponder is NSText {
                window.makeFirstResponder(nil)
            }
        }
        .onChange(of: navigation.explorePath.isEmpty) { if showsSearch { focusRequest += 1 } }
        .onAppear { if showsSearch { focusRequest += 1 } }
        .onAppear {
            if query.isEmpty, let last = player.lastSearch {
                query = last.query
                kind = last.kind
            }
        }
        // Typing waits for a pause before it asks.
        .task(id: Ask(query: query, kind: kind)) {
            try? await Task.sleep(for: .seconds(Self.typingPause))
            guard !Task.isCancelled else { return }
            player.search(query, kind: kind)
        }
    }

    private struct Ask: Equatable {
        let query: String
        let kind: SearchKind
    }

    private static let typingPause = 0.35

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var showsSearch: Bool { navigation.page == .explore && navigation.explorePath.isEmpty }

    // MARK: - Bar

    /// The same glass line as on Playlists, right under the title bar. Over
    /// the search: the field, and the kinds once there is a query. Over a
    /// page: Back, its name, and Play.
    private var bar: some View {
        Group {
            if let route = navigation.explorePath.last {
                routeBar(route)
                    .frame(height: Theme.Size.pageBar)
                    .padding(.horizontal, Theme.Space.xs)
            } else {
                // The kinds stay while the field is empty, so nothing moves
                // when typing starts.
                VStack(spacing: Theme.Space.xs) {
                    SearchField(text: $query, prompt: "What do you want to hear?", focusRequest: focusRequest)
                    SegmentPicker(selection: $kind, options: SearchKind.allCases.map { ($0, $0.title) })
                }
                .padding(Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
        .barGlass(joined: .top)
    }

    private func routeBar(_ route: ExploreRoute) -> some View {
        HStack(spacing: Theme.Space.xxs) {
            TransportButton(symbol: "chevron.left", label: backLabel,
                            target: Theme.Size.pageTabTarget, color: Theme.Colors.textMuted) {
                navigation.exploreBack()
            }
            Text(title(of: route))
                .font(Theme.Text.label)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .help(title(of: route))
            Spacer(minLength: Theme.Space.xs)
            Button { play(route) } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(FilledButtonStyle(compact: true))
            .disabled(!canPlay(route))
        }
    }

    private var backLabel: String {
        if navigation.explorePath.count == 1, let origin = navigation.exploreOrigin { return "Back to \(origin.title)" }
        return "Back"
    }

    private func title(of route: ExploreRoute) -> String {
        switch route {
        case .artist(let id, let name): return player.artistPages[id]?.name ?? name
        case .collection(let id, let title): return player.collectionPages[id]?.title ?? title
        }
    }

    private func canPlay(_ route: ExploreRoute) -> Bool {
        switch route {
        case .artist(let id, _):
            guard let page = player.artistPages[id] else { return false }
            return !page.songsPlaylistID.isEmpty || !page.songs.isEmpty
        case .collection(let id, _):
            return player.collectionPages[id]?.playlistID.isEmpty == false
        }
    }

    /// An artist: all their songs, or the top song's radio when YouTube Music
    /// has no such playlist. An album or playlist: from the top.
    private func play(_ route: ExploreRoute) {
        switch route {
        case .artist(let id, _):
            guard let page = player.artistPages[id] else { return }
            if !page.songsPlaylistID.isEmpty {
                player.play(artist: page)
            } else if let first = page.songs.first {
                player.play(first)
            }
        case .collection(let id, _):
            if let page = player.collectionPages[id] { player.play(page) }
        }
    }

    @ViewBuilder
    private func routePage(_ route: ExploreRoute) -> some View {
        switch route {
        case .artist(let id, _): ArtistView(id: id)
        case .collection(let id, _): CollectionView(id: id)
        }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchContent: some View {
        Group {
            if let blocked = blockingState(for: player) {
                blocked
            } else if !hasQuery {
                EmptyState(symbol: "magnifyingglass", title: "Search YouTube Music",
                           message: "Start typing to find something to play.")
                    .background { FloatingNotes(running: navigation.page == .explore) }
            } else {
                switch player.searchState {
                case .idle, .loading:
                    // Where the results' rows will be: the list's own top room.
                    SkeletonList(round: kind == .artists)
                        .padding(.top, Theme.Space.xxs)
                        .frame(maxHeight: .infinity, alignment: .top)
                case .failed(let reason):
                    EmptyState(symbol: "exclamationmark.triangle", title: "Search failed",
                               message: reason, actionTitle: "Try Again") { player.retrySearch() }
                case .loaded where player.searchResults.isEmpty:
                    EmptyState(symbol: "magnifyingglass", title: "Nothing found",
                               message: "Try other words, or another kind.")
                case .loaded:
                    results
                }
            }
        }
        // The list runs under the bar and the strip and keeps their room as
        // scroll margins; everything else stays between them.
        .padding(.top, showsList ? 0 : barHeight)
        .padding(.bottom, showsList ? 0 : footerRoom)
    }

    private var showsList: Bool {
        blockingState(for: player) == nil && hasQuery && player.searchState == .loaded && !player.searchResults.isEmpty
    }

    private var results: some View {
        ExploreScroll {
            LazyVStack(spacing: 0) {
                ForEach(player.searchResults) { item in
                    ItemRowButton(item: item)
                }
            }
            .padding(.horizontal, Theme.Space.xs)
        }
    }
}

// MARK: - Shared parts

private struct ExploreBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// How much of the top Explore's bar covers; its lists scroll under it.
    var exploreBarHeight: CGFloat {
        get { self[ExploreBarHeightKey.self] }
        set { self[ExploreBarHeightKey.self] = newValue }
    }
}

/// A scroll view that runs under Explore's bar and the strip, keeping their
/// room as margins, as the lists on the other pages do.
struct ExploreScroll<Content: View>: View {
    @Environment(\.exploreBarHeight) private var barHeight
    @Environment(\.footerRoom) private var footerRoom
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.vertical, Theme.Space.xxs)
                .background(OverlayScrollers())
        }
        .contentMargins(.top, barHeight, for: .scrollContent)
        .contentMargins(.top, barHeight, for: .scrollIndicators)
        .contentMargins(.bottom, footerRoom, for: .scrollContent)
        .contentMargins(.bottom, footerRoom, for: .scrollIndicators)
    }
}

/// A page that is still loading or failed to.
struct PageState: View {
    let id: String
    @EnvironmentObject private var player: PlayerController
    @Environment(\.exploreBarHeight) private var barHeight
    @Environment(\.footerRoom) private var footerRoom

    var body: some View {
        Group {
            if player.exploreFailures.contains(id) {
                EmptyState(symbol: "exclamationmark.triangle", title: "Could not load this page",
                           message: "Check the connection and try again.",
                           actionTitle: "Try Again") { player.retryExplorePage(id) }
            } else {
                SkeletonList()
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.top, barHeight)
        .padding(.bottom, footerRoom)
    }
}

/// A section's name over its rows or tiles, as YouTube Music names it.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Text.label)
            .foregroundStyle(Theme.Colors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.xxs)
    }
}

// MARK: - Artist
