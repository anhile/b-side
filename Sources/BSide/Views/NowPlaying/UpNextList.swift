import AppKit
import SwiftUI

/// What plays after the current track, in the artwork's place: a click
/// jumps to a track, its menu takes it out of the queue. The page sends
/// the next thirty; the list fills again as the queue moves on.
struct UpNextList: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        if player.upNext.isEmpty {
            Text(player.repeatMode == .all ? "Then the same again, from the top." : "Nothing after this track.")
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { bar }
        } else {
            // The bar the pages with a list have under the title bar, so
            // the list reads as one of them; the rows run under it.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.xxs) { // air between the glass shapes of two rows
                    ForEach(player.upNext) { track in
                        Button { player.playUpNext(track) } label: {
                            TrackRow(track: track, isCurrent: false, isPlaying: false)
                        }
                        .buttonStyle(RowButtonStyle())
                        .help("Play \(track.title)")
                        .contextMenu {
                            TrackMenu(videoID: track.videoID, title: track.title, artist: track.artist,
                                      artistID: track.artistID, albumID: track.albumID, liked: track.liked) {
                                Button(role: .destructive) { player.removeFromQueue(track) } label: {
                                    Label("Remove from Up Next", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, Theme.Space.xxs)
                .background(OverlayScrollers())
            }
            .contentMargins(.top, Theme.Size.pageBar, for: .scrollContent)
            .contentMargins(.top, Theme.Size.pageBar, for: .scrollIndicators)
            .overlay(alignment: .top) { bar }
        }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            Text("Up Next")
                .font(Theme.Text.label)
                .foregroundStyle(Theme.Colors.textMuted)
            Spacer()
            // Back to the artwork, under the page's tab, as the
            // Playlists bar has its button.
            IconButton(symbol: "xmark", label: "Hide Up Next") { navigation.showsQueue = false }
                .frame(width: Theme.Size.pageTabTarget)
        }
        .padding(.leading, Theme.Space.m)
        .padding(.trailing, Theme.Space.xs)
        .frame(height: Theme.Size.pageBar)
        .frame(maxWidth: .infinity)
        .barGlass(joined: .top)
    }
}
