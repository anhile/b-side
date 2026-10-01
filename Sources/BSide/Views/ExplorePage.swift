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
                    SearchField(text: $query, prompt: "Songs, albums, artists, playlists")
                    EqualSegments(selection: $kind, options: SearchKind.allCases.map { ($0, $0.title) },
                                  label: "Kind")
                }
                .padding(Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
        .glass(in: Rectangle())
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
                player.play(MusicItem(id: 0, kind: .playlist, playlistID: page.songsPlaylistID, title: page.name))
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
                           message: "Find a song to play with its radio, an album or a playlist, or an artist.")
            } else {
                switch player.searchState {
                case .idle, .loading:
                    SkeletonList()
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
private struct ExploreScroll<Content: View>: View {
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

/// A row that does what its item does: a song plays (with its radio); an
/// album, a playlist or an artist opens. Albums and playlists also have a
/// play button at the end. Right-click goes to a song's artist or album.
private struct ItemRowButton: View {
    let item: MusicItem
    /// Within an album or playlist: plays it from this track instead.
    var playFromHere: (() -> Void)?
    var number: Int?

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        Button(action: primary) {
            ItemRow(item: item, isCurrent: isCurrent, isPlaying: player.state.isPlaying,
                    number: number, roomForPlay: showsPlay)
        }
        .buttonStyle(RowButtonStyle())
        .help(help)
        .overlay(alignment: .trailing) {
            if showsPlay {
                TransportButton(symbol: isCurrent && player.state.isPlaying ? "pause.fill" : "play.fill",
                                label: "Play \(item.title)", target: Theme.Size.artworkSmall,
                                color: isCurrent ? Theme.Colors.accentText : Theme.Colors.textMuted) {
                    isCurrent ? player.togglePlayPause() : player.play(item)
                }
                .padding(.trailing, Theme.Space.xxs)
            }
        }
        .contextMenu {
            if !item.artistID.isEmpty {
                Button("Go to Artist") {
                    navigation.open(.artist(id: item.artistID, name: artistName))
                }
            }
            if !item.albumID.isEmpty {
                Button("Go to Album") { navigation.open(.collection(id: item.albumID, title: "Album")) }
            }
        }
    }

    private var showsPlay: Bool {
        (item.kind == .album || item.kind == .playlist) && !item.playlistID.isEmpty
    }

    private var artistName: String {
        item.subtitle.components(separatedBy: " • ").first ?? item.title
    }

    private var help: String {
        switch item.kind {
        case .song: return playFromHere == nil ? "Play \(item.title) and its radio" : "Play from \(item.title)"
        case .album, .playlist: return "Show the tracks"
        case .artist: return "Show \(item.title)"
        }
    }

    private func primary() {
        if let playFromHere { return playFromHere() }
        if let route = ExploreRoute(item) {
            navigation.open(route)
        } else {
            player.play(item)
        }
    }

    private var isCurrent: Bool {
        guard player.hasTrack else { return false }
        if !item.videoID.isEmpty { return item.videoID == player.state.videoID }
        return !item.playlistID.isEmpty && player.source == .playlist(item.playlistID)
    }
}

/// Artwork (round for an artist, a track number in an album), title, and
/// what YouTube Music says under it; a track's length at the end.
struct ItemRow: View {
    let item: MusicItem
    let isCurrent: Bool
    let isPlaying: Bool
    var number: Int?
    var roomForPlay = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let number {
                Text("\(number)")
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.textMuted)
                    .frame(width: Theme.Size.artworkSmall)
            } else if item.kind == .artist {
                Artwork(url: item.artworkURL, size: Theme.Size.artworkSmall, radius: Theme.Size.artworkSmall / 2,
                        placeholder: "person.fill")
            } else {
                Artwork(url: item.artworkURL, size: Theme.Size.artworkSmall,
                        placeholder: item.kind == .song ? "music.note" : "music.note.list")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(Theme.Text.body)
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.text)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.xs)
            if isCurrent, !roomForPlay {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.accentText)
                    .accessibilityLabel(isPlaying ? "Playing" : "Paused")
            } else if !item.detail.isEmpty {
                Text(item.detail)
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            if roomForPlay {
                // Room for the play button that lies over the row.
                Color.clear.frame(width: Theme.Size.artworkSmall) // tokens-ok: empty room, not a colour
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Theme.Size.rowHeight)
        .contentShape(Rectangle())
    }
}

/// A page that is still loading or failed to.
private struct PageState: View {
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
private struct SectionTitle: View {
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

/// Photo and name, the top songs, then YouTube Music's rows of albums,
/// singles, playlists and related artists, each scrolling sideways.
private struct ArtistView: View {
    let id: String
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        if let page = player.artistPages[id] {
            ExploreScroll {
                VStack(spacing: 0) {
                    header(page)
                    if !page.songs.isEmpty {
                        SectionTitle(text: "Top songs")
                        // As in YouTube Music: from this song on through all of the
                        // artist's songs, not into a radio of others.
                        VStack(spacing: 0) {
                            ForEach(page.songs) { song in
                                ItemRowButton(item: song, playFromHere: page.songsPlaylistID.isEmpty ? nil : {
                                    player.play(list: page.songsPlaylistID, from: song.id)
                                })
                            }
                        }
                        .padding(.horizontal, Theme.Space.xs)
                    }
                    ForEach(page.shelves) { shelf in
                        ShelfRow(title: shelf.title, items: shelf.items)
                    }
                }
            }
        } else {
            PageState(id: id)
                .onAppear { player.loadArtist(id) }
        }
    }

    private func header(_ page: ArtistPage) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Artwork(url: page.artworkURL, size: Theme.Size.cover, radius: Theme.Size.cover / 2, placeholder: "person.fill")
            Text(page.name)
                .font(Theme.Text.title)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.s)
    }
}

/// Tiles in a row that scrolls sideways; a click opens the album, playlist
/// or artist. A mouse cannot scroll sideways, so the row also moves with the
/// arrows by its title, a page of tiles at a time, and with a drag, by as
/// many tiles as it was dragged. Either way it settles on a tile's edge.
private struct ShelfRow: View {
    let title: String
    let items: [MusicItem]
    @EnvironmentObject private var navigation: Navigation
    @State private var first: Int? = 0
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SectionTitle(text: title)
                if items.count > visible {
                    TransportButton(symbol: "chevron.left", label: "Previous", glyph: Theme.Size.transportGlyph,
                                    target: Theme.Size.pageTabTarget, color: Theme.Colors.textMuted) { move(by: -visible) }
                        .disabled(start == 0)
                        .padding(.top, Theme.Space.s)
                    TransportButton(symbol: "chevron.right", label: "Next", glyph: Theme.Size.transportGlyph,
                                    target: Theme.Size.pageTabTarget, color: Theme.Colors.textMuted) { move(by: visible) }
                        .disabled(start >= lastStart)
                        .padding(.top, Theme.Space.s)
                        .padding(.trailing, Theme.Space.xs)
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.Space.s) {
                    ForEach(items) { item in
                        Button {
                            if let route = ExploreRoute(item) { navigation.open(route) }
                        } label: {
                            Tile(item: item)
                        }
                        .buttonStyle(.plain)
                        .help(item.title)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.Space.m, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $first, anchor: .leading)
            .scrollIndicators(.never)
            .simultaneousGesture(
                DragGesture(minimumDistance: Theme.Space.xs).onEnded { drag in
                    move(by: Int((-drag.translation.width / step).rounded()))
                }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    /// One tile and the gap after it.
    private var step: CGFloat { Theme.Size.cover + Theme.Space.s }
    /// Whole tiles in view.
    private var visible: Int { max(1, Int((width - 2 * Theme.Space.m + Theme.Space.s) / step)) }
    private var start: Int { first ?? 0 }
    private var lastStart: Int { max(0, items.count - visible) }

    private func move(by tiles: Int) {
        guard tiles != 0 else { return }
        withAnimation(.easeInOut(duration: Theme.Motion.page)) {
            first = min(max(start + tiles, 0), lastStart)
        }
    }

    private struct Tile: View {
        let item: MusicItem
        @State private var hovering = false

        var body: some View {
            VStack(alignment: item.kind == .artist ? .center : .leading, spacing: Theme.Space.xxs) {
                Artwork(url: item.artworkURL, size: Theme.Size.cover,
                        radius: item.kind == .artist ? Theme.Size.cover / 2 : Theme.Radius.s,
                        placeholder: item.kind == .artist ? "person.fill" : "music.note.list")
                    .opacity(hovering ? Theme.Opacity.pressed : 1)
                Text(item.title)
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(item.kind == .artist ? .center : .leading)
                if !item.subtitle.isEmpty, item.kind != .artist {
                    Text(item.subtitle)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(width: Theme.Size.cover, alignment: item.kind == .artist ? .center : .leading)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
    }
}

// MARK: - Album or playlist

/// Artwork, title, the artist (a link to their page) and the year, then the
/// tracks: numbered in an album, with their artwork in a playlist. A track
/// plays the album or playlist from there.
private struct CollectionView: View {
    let id: String
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        if let page = player.collectionPages[id] {
            ExploreScroll {
                VStack(spacing: 0) {
                    header(page)
                    LazyVStack(spacing: 0) {
                        ForEach(page.tracks) { track in
                            ItemRowButton(item: withoutAlbumArtist(track, of: page),
                                          playFromHere: { player.play(page, from: track.id) },
                                          number: page.isAlbum ? track.id + 1 : nil)
                        }
                    }
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.top, Theme.Space.s)
                    if page.tracks.isEmpty {
                        Text("No tracks")
                            .font(Theme.Text.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .padding(Theme.Space.l)
                    }
                }
            }
        } else {
            PageState(id: id)
                .onAppear { player.loadCollection(id) }
        }
    }

    /// In an album, a track's artist is said once, in the header, unless
    /// the track has another (a guest, a compilation).
    private func withoutAlbumArtist(_ track: MusicItem, of page: CollectionPage) -> MusicItem {
        guard page.isAlbum, track.subtitle == page.artist else { return track }
        var track = track
        track.subtitle = ""
        return track
    }

    private func header(_ page: CollectionPage) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            Artwork(url: page.artworkURL, size: Theme.Size.cover, placeholder: "music.note.list")
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(page.title)
                    .font(Theme.Text.title)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(3)
                if !page.artist.isEmpty {
                    if page.artistID.isEmpty {
                        Text(page.artist)
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .lineLimit(1)
                    } else {
                        Button { navigation.open(.artist(id: page.artistID, name: page.artist)) } label: {
                            LinkText(text: page.artist)
                        }
                        .buttonStyle(.plain)
                        .help("Show \(page.artist)")
                    }
                }
                if !page.subtitle.isEmpty {
                    Text(page.subtitle)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.s)
    }
}

// MARK: - Search field

/// AppKit's search field: the magnifier, the clear button and Escape to
/// clear, as everywhere on the Mac. SwiftUI has one only for toolbars.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:)) // also the clear button and Escape
        field.sendsSearchStringImmediately = true
        field.controlSize = Theme.scale > 1 ? .large : .regular
        field.font = .systemFont(ofSize: NSFont.systemFontSize * Theme.scale)
        field.focusRingType = .default
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        @objc func changed(_ field: NSSearchField) {
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
    }
}

/// AppKit's segmented control with every segment as wide as the others, the
/// row as wide as it is given. SwiftUI's sizes each segment to its title,
/// and the selected title is bolder, so the segments shifted on each click.
struct EqualSegments<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let options: [(Value, String)]
    let label: String

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: options.map(\.1), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        control.controlSize = Theme.scale > 1 ? .large : .regular
        control.setAccessibilityLabel(label)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if let index = options.firstIndex(where: { $0.0 == selection }), control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: EqualSegments
        init(_ parent: EqualSegments) { self.parent = parent }

        @objc func changed(_ control: NSSegmentedControl) {
            guard parent.options.indices.contains(control.selectedSegment) else { return }
            parent.selection = parent.options[control.selectedSegment].0
        }
    }
}
