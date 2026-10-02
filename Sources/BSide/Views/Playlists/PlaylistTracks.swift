import SwiftUI

/// One playlist's tracks. Back leads to the library; Play plays it from the
/// top; a track plays the playlist from that track. More tracks load as the
/// list nears its end.
struct PlaylistTracks: View {
    let playlist: Playlist

    @EnvironmentObject private var player: PlayerController
    @Environment(\.footerRoom) private var footerRoom

    /// The page's bar above names the playlist and holds Back and Play.
    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch player.tracksState {
        case .idle, .loading:
            SkeletonList()
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
        case .failed(let reason):
            EmptyState(symbol: "exclamationmark.triangle", title: "Could not load the tracks",
                       message: reason, actionTitle: "Try Again") { player.retryTracks() }
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
        case .loaded where player.tracks.isEmpty:
            EmptyState(symbol: "music.note.list", title: "No tracks",
                       message: "This playlist is empty, or its tracks are not available.")
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(player.tracks) { track in
                    Button {
                        player.playOpenPlaylist(from: track)
                    } label: {
                        TrackRow(track: track, isCurrent: isCurrent(track), isPlaying: player.state.isPlaying)
                    }
                    .buttonStyle(RowButtonStyle())
                    .help(track.title)
                    .contextMenu {
                        TrackMenu(videoID: track.videoID, title: track.title, artist: track.artist, artistID: track.artistID,
                                  albumID: track.albumID, liked: track.liked) {
                            if track.removable || player.canEditOpenPlaylist, !track.setVideoID.isEmpty,
                               let playlist = player.openPlaylist {
                                Button(role: .destructive) { player.remove(track, from: playlist) } label: {
                                    Label("Remove from Playlist", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                    .onAppear {
                        if track.index >= player.tracks.count - Self.loadMoreAhead { player.loadMoreTracks() }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.xxs)
            .background(OverlayScrollers())
        }
        .contentMargins(.top, Theme.Size.pageBar, for: .scrollContent)
        .contentMargins(.top, Theme.Size.pageBar, for: .scrollIndicators)
        .contentMargins(.bottom, footerRoom, for: .scrollContent)
        .contentMargins(.bottom, footerRoom, for: .scrollIndicators)
    }

    /// Rows from the end at which the next page is asked for.
    private static let loadMoreAhead = 5

    private func isCurrent(_ track: Track) -> Bool {
        player.source == .playlist(playlist.id) && player.state.videoID == track.videoID
    }
}
