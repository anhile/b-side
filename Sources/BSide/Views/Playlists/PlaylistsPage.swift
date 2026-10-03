import SwiftUI

/// One job: pick one of my playlists, private ones included. A row opens
/// the playlist's tracks; its play button plays it straight away.
struct PlaylistsPage: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation
    @Environment(\.footerRoom) private var footerRoom
    @Environment(\.pageShown) private var pageShown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The row being dragged to another place.
    @State private var drag: RowDrag?
    /// Where each row is in the list, for the drag.
    @State private var frames: [Playlist.ID: CGRect] = [:]
    /// The playlist Delete… asks about.
    @State private var deleting: Playlist?

    /// A row on its way to another place, as a vibe tile is: a copy follows
    /// the pointer over the list while the row itself, unseen, keeps its
    /// place, so the others make room around it.
    private struct RowDrag {
        let id: Playlist.ID
        /// Where every place of the list is, by its number; the rows are all
        /// one height, so the places stay put while the rows change them.
        let slots: [Int: CGRect]
        let start: CGRect
        var translation: CGFloat = 0
        var settling = false
    }

    private static let listSpace = "playlists"

    private var moving: Animation? { reduceMotion ? nil : .snappy(duration: Theme.Motion.page) }

    private let likedMusic = Playlist(id: Tuning.likedMusicID, title: "Liked Music", subtitle: "Auto playlist")

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                if let playlist = player.openPlaylist {
                    PlaylistTracks(playlist: playlist)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                } else {
                    library
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                }
            }
            .clipped()
            // No button for it: the list is asked for again whenever the
            // page comes into view, at most twice a minute.
            .task(id: pageShown) { if pageShown { player.refreshPlaylists() } }
            bar
        }
        .animation(.easeInOut(duration: Theme.Motion.page), value: player.openPlaylist?.id)
    }

    private var library: some View {
        Group {
            if let blocked = blockingState(for: player) {
                blocked
                    .padding(.top, Theme.Size.pageBar)
                    .padding(.bottom, footerRoom)
            } else if player.account == .signedOut {
                EmptyState(symbol: "person.crop.circle", title: "Sign in for your playlists",
                           message: "Your playlists and Liked Music live in your YouTube Music account.",
                           actionTitle: "Sign In…", action: { player.showSignIn() })
                    .padding(.top, Theme.Size.pageBar)
                    .padding(.bottom, footerRoom)
            } else {
                content
            }
        }
    }

    /// One glass line right under the title bar, the width of the window.
    /// It stays while the lists slide under it; only what it says changes.
    /// The trailing button sits under the Playlists tab, in a slot as wide.
    private var bar: some View {
        ZStack {
            if let playlist = player.openPlaylist {
                tracksBar(playlist)
            } else {
                libraryBar
            }
        }
        .frame(height: Theme.Size.pageBar)
        .frame(maxWidth: .infinity)
        .barGlass(joined: .top)
    }

    /// Quiet: the tabs already say which page this is. The count is the one
    /// piece of information the rows cannot give.
    private var libraryBar: some View {
        HStack(spacing: 0) {
            Text(headerText)
                .font(Theme.Text.label)
                .foregroundStyle(Theme.Colors.textMuted)
            Spacer()
            IconButton(symbol: "plus", label: "New Playlist") {
                navigation.newPlaylist = NewPlaylistRequest()
            }
            .disabled(!player.account.isSignedIn || player.phase != .ready)
            .frame(width: Theme.Size.pageTabTarget)
        }
        .padding(.leading, Theme.Space.m)
        .padding(.trailing, Theme.Space.xs)
        .transition(.opacity)
    }

    private func tracksBar(_ playlist: Playlist) -> some View {
        HStack(spacing: Theme.Space.xxs) {
            TransportButton(symbol: "chevron.left", label: "Back to playlists",
                            target: Theme.Size.pageTabTarget, color: Theme.Colors.textMuted) {
                player.closePlaylist()
            }
            Text(playlist.title)
                .font(Theme.Text.label)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .help(playlist.title)
            Spacer(minLength: Theme.Space.xs)
            Button { player.play(playlist) } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(FilledButtonStyle(compact: true))
            .disabled(player.tracksState != .loaded || player.tracks.isEmpty)
        }
        .padding(.horizontal, Theme.Space.xs)
        .transition(.opacity)
    }

    private var headerText: String {
        guard player.playlistsState == .loaded, !player.playlists.isEmpty else { return "Playlists" }
        return "\(rows.count) playlists"
    }

    @ViewBuilder
    private var content: some View {
        switch player.playlistsState {
        case .idle, .loading:
            SkeletonList()
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
        case .failed(let reason):
            EmptyState(symbol: "exclamationmark.triangle", title: "Could not load playlists",
                       message: reason, actionTitle: "Try Again", action: { player.loadPlaylists() })
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
        case .loaded:
            list
        }
    }

    private var rows: [Playlist] {
        [likedMusic] + player.playlists.filter { $0.id != Tuning.likedMusicID }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { playlist in
                    row(playlist)
                        .opacity(drag?.id == playlist.id ? 0 : 1)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.listSpace)) } action: { frames[playlist.id] = $0 }
                        .gesture(reorder(playlist), including: playlist.id == Tuning.likedMusicID ? .none : .all)
                        .contextMenu { menu(for: playlist) }
                }
            }
            .coordinateSpace(name: Self.listSpace)
            .overlay(alignment: .topLeading) { floating }
            // The hover shape sits 8 inside the window edge, and the row's own
            // padding brings its content to the 16 window padding.
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.xxs)
            .background(OverlayScrollers())
        }
        .confirmationDialog(
            "Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible, presenting: deleting
        ) { playlist in
            Button("Delete", role: .destructive) { player.deletePlaylist(playlist) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The playlist goes from your YouTube Music library. The tracks stay in it.")
        }
        .contentMargins(.top, Theme.Size.pageBar, for: .scrollContent)
        .contentMargins(.top, Theme.Size.pageBar, for: .scrollIndicators)
        .contentMargins(.bottom, footerRoom, for: .scrollContent)
        .contentMargins(.bottom, footerRoom, for: .scrollIndicators)
    }
}

extension PlaylistsPage {
    /// A click opens, a drag moves the row: not a Button, which would keep
    /// the mouse and never let a drag start. Hover and the playing mark as
    /// the other lists have them.
    private func row(_ playlist: Playlist) -> some View {
        let isCurrent = player.source == .playlist(playlist.id) && player.hasTrack
        return HoverReveal(playing: isCurrent ? player.state.isPlaying : nil) {
            PlaylistRow(playlist: playlist, isCurrent: isCurrent, subtitle: player.subtitle(of: playlist))
                .modifier(RowHighlight(selected: isCurrent))
                .onTapGesture { player.open(playlist) }
                .help("Show the tracks")
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default) { player.open(playlist) }
        } control: {
            playButton(for: playlist, isCurrent: isCurrent)
                .padding(.trailing, Theme.Space.xxs)
        }
    }

    /// Liked Music stays first; the user's own playlists can be renamed and
    /// deleted, any other (saved from elsewhere) only moved.
    @ViewBuilder private func menu(for playlist: Playlist) -> some View {
        Group {
            Button { player.play(playlist) } label: { Label("Play", systemImage: "play.fill") }
            if playlist.id != Tuning.likedMusicID {
                if playlist.isOwn {
                    Divider()
                    Button { navigation.renamingPlaylist = playlist } label: { Label("Rename…", systemImage: "pencil") }
                }
                Divider()
                Button { move(playlist, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                    .disabled(playlist.id == movable.first?.id)
                Button { move(playlist, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                    .disabled(playlist.id == movable.last?.id)
                if playlist.isOwn {
                    Divider()
                    Button(role: .destructive) { deleting = playlist } label: { Label("Delete…", systemImage: "trash") }
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .disabled(!player.account.isSignedIn || player.phase != .ready)
    }

    /// The rows the user can move: all but Liked Music.
    private var movable: [Playlist] { rows.dropFirst().map { $0 } }

    private func move(_ playlist: Playlist, by step: Int) {
        withAnimation(moving) { player.movePlaylist(playlist, by: step) }
    }

    private func reorder(_ playlist: Playlist) -> some Gesture {
        DragGesture(minimumDistance: Theme.Space.xxs, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if drag == nil, let start = frames[playlist.id] {
                    var slots: [Int: CGRect] = [:]
                    for (place, row) in rows.enumerated() { slots[place] = frames[row.id] }
                    drag = RowDrag(id: playlist.id, slots: slots, start: start)
                }
                guard let drag, drag.id == playlist.id, !drag.settling else { return }
                self.drag?.translation = value.translation.height
                // Up and down only; the pointer may leave the rows sideways.
                let y = value.location.y
                guard let place = drag.slots.first(where: { $0.value.minY <= y && y < $0.value.maxY })?.key,
                      rows.indices.contains(place), rows[place].id != playlist.id, rows[place].id != Tuning.likedMusicID else { return }
                withAnimation(moving) { player.movePlaylist(playlist.id, toPlaceOf: rows[place].id) }
            }
            .onEnded { _ in
                guard drag?.id == playlist.id else { return }
                withAnimation(moving) { drag?.settling = true } completion: { drag = nil }
            }
    }

    /// The dragged row's copy, lifted a little, under the pointer.
    @ViewBuilder private var floating: some View {
        if let drag, let place = rows.firstIndex(where: { $0.id == drag.id }) {
            let home = drag.slots[place] ?? drag.start
            row(rows[place])
                .frame(width: drag.start.width, height: drag.start.height)
                .background(RowGlass(shown: true))
                .offset(x: drag.start.minX, y: drag.settling ? home.minY : drag.start.minY + drag.translation)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Plays the playlist from the top; on the one that plays, pauses and
    /// resumes it instead.
    fileprivate func playButton(for playlist: Playlist, isCurrent: Bool) -> some View {
        let pauses = isCurrent && player.state.isPlaying
        return TransportButton(symbol: pauses ? "pause.fill" : "play.fill",
                               label: pauses ? "Pause" : "Play \(playlist.title)",
                               target: Theme.Size.artworkSmall,
                               color: isCurrent ? Theme.Colors.accentText : Theme.Colors.textMuted) {
            isCurrent ? player.togglePlayPause() : player.play(playlist)
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    let isCurrent: Bool
    /// The subtitle as shown: without the author when it is the user.
    var subtitle: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if playlist.id == Tuning.likedMusicID {
                // Liked Music has no artwork of its own; the record stands in.
                Record(size: Theme.Size.artworkSmall, spinning: false)
            } else {
                Artwork(url: playlist.artworkURL, size: Theme.Size.artworkSmall, placeholder: "music.note.list")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(playlist.title)
                    .font(Theme.Text.body)
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.text)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.xs)
            // Room for the play button that lies over the row.
            Color.clear.frame(width: Theme.Size.artworkSmall) // tokens-ok: empty room, not a colour
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Theme.Size.rowHeight)
        .contentShape(Rectangle())
    }
}
