import AppKit
import SwiftUI

/// What can be done with a track, the same wherever it is listed or plays:
/// like it, put it in a playlist, play it next, start its radio, go to its
/// artist or album, copy its link. `extra` comes after the playlists: what only that
/// place offers.
struct TrackMenu<Extra: View>: View {
    let videoID: String
    var title = ""
    var artist = ""
    var artistID = ""
    var albumID = ""
    /// What the list said when it was loaded.
    var liked = false
    /// Now Playing has its own Like, with the shortcut.
    var showsLike = true
    @ViewBuilder var extra: Extra

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        // A menu on the Mac shows a Label's title alone unless asked.
        Group { items }
            .labelStyle(.titleAndIcon)
    }

    @ViewBuilder private var items: some View {
        if showsLike {
            let isLiked = player.isLiked(videoID, listed: liked)
            Button { player.setLike(videoID, on: !isLiked) } label: {
                Label(isLiked ? "Remove Like" : "Like", systemImage: isLiked ? "heart.slash" : "heart")
            }
            .disabled(videoID.isEmpty || !player.account.isSignedIn)
        }
        AddToPlaylistMenu(videoID: videoID)
        extra
        Divider()
        Button { player.playNext(videoID, title: title, artist: artist) } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        .disabled(videoID.isEmpty || !player.hasTrack || videoID == player.state.videoID)
        Button { player.playRadio(of: videoID) } label: {
            Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
        }
        .disabled(videoID.isEmpty)
        Button { navigation.open(.artist(id: artistID, name: artist)) } label: {
            Label("Go to Artist", systemImage: "person")
        }
        .disabled(artistID.isEmpty || videoID.isEmpty)
        Button { navigation.open(.collection(id: albumID, title: "Album")) } label: {
            Label("Go to Album", systemImage: "square.stack")
        }
        .disabled(albumID.isEmpty || videoID.isEmpty)
        Divider()
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Tuning.trackLink + videoID, forType: .string)
        } label: {
            Label("Copy Link", systemImage: "link")
        }
        .disabled(videoID.isEmpty)
    }
}

extension TrackMenu where Extra == EmptyView {
    init(videoID: String, title: String = "", artist: String = "", artistID: String = "", albumID: String = "",
         liked: Bool = false) {
        self.init(videoID: videoID, title: title, artist: artist, artistID: artistID, albumID: albumID,
                  liked: liked) { EmptyView() }
    }
}
