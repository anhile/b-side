import SwiftUI

/// Asks for the New Playlist sheet; the track goes into the new playlist.
struct NewPlaylistRequest: Identifiable {
    let id = UUID()
    var videoID: String?
}

/// "Add to Playlist" in a track's menus: a new playlist, then the user's own
/// playlists, checked where the track already is. A submenu wherever it is
/// put.
struct AddToPlaylistMenu: View {
    let videoID: String

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        Menu {
            Button("New Playlist…") { navigation.newPlaylist = NewPlaylistRequest(videoID: videoID) }
            let own = player.ownPlaylists
            if !own.isEmpty {
                Divider()
                let holding = player.playlistsHolding[videoID] ?? []
                ForEach(own) { playlist in
                    // A checkmark where the track already is; unchecking
                    // takes it out, as YouTube Music's Save dialog does.
                    Toggle(playlist.title, isOn: Binding(
                        get: { holding.contains(playlist.id) },
                        set: { $0 ? player.add(videoID, to: playlist) : player.removeAnywhere(videoID, from: playlist) }))
                }
            }
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
        .onAppear { player.checkPlaylists(holding: videoID) }
        .disabled(videoID.isEmpty || !player.account.isSignedIn)
    }
}

/// Names a new playlist. Private, as YouTube Music makes them; the privacy
/// can be changed there. System controls, as in the Vibe editor.
struct NewPlaylistSheet: View {
    let request: NewPlaylistRequest
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $title, prompt: Text("Road trip"))
                if request.videoID != nil {
                    Text("The track goes into it. The playlist is private.")
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                } else {
                    Text("The playlist is private.")
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    player.createPlaylist(title: title, adding: request.videoID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Theme.Space.m)
        }
        .frame(width: Theme.Size.editorWidth)
    }
}

/// A word that something was done, in a small glass capsule over the
/// bottom of the window.
struct NoticeView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark")
            .font(Theme.Text.label)
            .foregroundStyle(Theme.Colors.text)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.s)
            .frame(height: Theme.Size.pageDotTarget)
            .glass(in: Capsule())
            .padding(.horizontal, Theme.Space.m)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
