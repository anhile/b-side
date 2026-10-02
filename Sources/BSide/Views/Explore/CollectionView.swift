import AppKit
import SwiftUI

/// Artwork, title, the artist (a link to their page) and the year, then the
/// tracks: numbered in an album, with their artwork in a playlist. A track
/// plays the album or playlist from there.
struct CollectionView: View {
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
                        .pointingHand()
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
