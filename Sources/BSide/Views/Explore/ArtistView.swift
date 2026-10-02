import AppKit
import SwiftUI

/// Photo and name, the top songs, then YouTube Music's rows of albums,
/// singles, playlists and related artists, each scrolling sideways.
struct ArtistView: View {
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
                                    player.play(list: page.songsPlaylistID, from: song.id, title: page.name, kind: .artist)
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
struct ShelfRow: View {
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
                        .pointingHand()
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
