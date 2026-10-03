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
            Button { navigation.newPlaylist = NewPlaylistRequest(videoID: videoID) } label: {
                Label("New Playlist…", systemImage: "plus")
            }
            .labelStyle(.titleAndIcon)
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
                .labelStyle(.titleAndIcon)
        }
        .onAppear { player.checkPlaylists(holding: videoID) }
        .disabled(videoID.isEmpty || !player.account.isSignedIn)
    }
}

/// Names a new playlist, or renames one of the user's. A new one is
/// private, as YouTube Music makes them; the privacy can be changed there.
/// System controls, as in the Vibe editor.
struct PlaylistNameSheet: View {
    private let request: NewPlaylistRequest?
    private let renaming: Playlist?
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(request: NewPlaylistRequest) {
        self.request = request
        renaming = nil
        _title = State(initialValue: "")
    }

    init(renaming: Playlist) {
        request = nil
        self.renaming = renaming
        _title = State(initialValue: renaming.title)
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespaces) }

    private var note: String {
        if renaming != nil { return "The name changes in your YouTube Music library too." }
        return request?.videoID != nil ? "The track goes into it. The playlist is private." : "The playlist is private."
    }

    private var canSave: Bool {
        !trimmed.isEmpty && trimmed != renaming?.title
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $title, prompt: Text("Road trip"))
                Text(note)
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(renaming == nil ? "Create" : "Rename") {
                    if let renaming {
                        player.renamePlaylist(renaming, to: trimmed)
                    } else {
                        player.createPlaylist(title: title, adding: request?.videoID)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
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
