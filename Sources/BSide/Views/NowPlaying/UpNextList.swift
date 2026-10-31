import AppKit
import SwiftUI

/// What plays after the current track, in the artwork's place: a click
/// jumps to a track, a drag puts it in another place, as the Playlists
/// rows are dragged, and its menu moves it or takes it out of the queue.
/// The page sends the next thirty; the list fills again as the queue moves
/// on.
struct UpNextList: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The row being dragged to another place.
    @State private var drag: RowDrag?
    /// Where each row is in the list, for the drag.
    @State private var frames: [Track.ID: CGRect] = [:]

    /// A copy follows the pointer while the row itself, unseen, keeps its
    /// place, so the others make room around it.
    private struct RowDrag {
        let id: Track.ID
        /// Where every place of the list is; the rows are all one height,
        /// so the places stay put while the rows change them.
        let slots: [Int: CGRect]
        let start: CGRect
        var translation: CGFloat = 0
        var settling = false
    }

    private static let listSpace = "upNext"
    private var moving: Animation? { reduceMotion ? nil : .snappy(duration: Theme.Motion.page) }

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
                        row(track)
                            .opacity(drag?.id == track.id ? 0 : 1)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.listSpace)) } action: { frames[track.id] = $0 }
                            .gesture(reorder(track))
                            .contextMenu { menu(for: track) }
                    }
                }
                .coordinateSpace(name: Self.listSpace)
                .overlay(alignment: .topLeading) { floating }
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, Theme.Space.xxs)
                .background(OverlayScrollers())
            }
            .contentMargins(.top, Theme.Size.pageBar, for: .scrollContent)
            .contentMargins(.top, Theme.Size.pageBar, for: .scrollIndicators)
            .overlay(alignment: .top) { bar }
        }
    }

    /// A click plays, a drag moves the row: not a Button, which would keep
    /// the mouse and never let a drag start.
    private func row(_ track: Track) -> some View {
        TrackRow(track: track, isCurrent: false, isPlaying: false)
            .modifier(RowHighlight())
            .contentShape(Rectangle())
            .onTapGesture { player.playUpNext(track) }
            .help("Play \(track.title), or drag it to another place")
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { player.playUpNext(track) }
    }

    @ViewBuilder private func menu(for track: Track) -> some View {
        TrackMenu(videoID: track.videoID, title: track.title, artist: track.artist,
                  artistID: track.artistID, albumID: track.albumID, liked: track.liked) {
            Button { withAnimation(moving) { player.moveUpNext(track, by: -1) } } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(track.id == player.upNext.first?.id)
            Button { withAnimation(moving) { player.moveUpNext(track, by: 1) } } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(track.id == player.upNext.last?.id)
            Divider()
            Button(role: .destructive) { player.removeFromQueue(track) } label: {
                Label("Remove from Up Next", systemImage: "minus.circle")
            }
        }
    }

    private func reorder(_ track: Track) -> some Gesture {
        DragGesture(minimumDistance: Theme.Space.xxs, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if drag == nil, let start = frames[track.id] {
                    var slots: [Int: CGRect] = [:]
                    for (place, row) in player.upNext.enumerated() { slots[place] = frames[row.id] }
                    drag = RowDrag(id: track.id, slots: slots, start: start)
                }
                guard let drag, drag.id == track.id, !drag.settling else { return }
                self.drag?.translation = value.translation.height
                // Up and down only; the pointer may leave the rows sideways.
                let y = value.location.y
                let rows = player.upNext
                guard let place = drag.slots.first(where: { $0.value.minY <= y && y < $0.value.maxY })?.key,
                      rows.indices.contains(place), rows[place].id != track.id else { return }
                withAnimation(moving) { player.moveUpNext(track.id, toPlaceOf: rows[place].id) }
            }
            .onEnded { _ in
                guard drag?.id == track.id else { return }
                player.commitUpNextMove(track)
                withAnimation(moving) { drag?.settling = true } completion: { drag = nil }
            }
    }

    /// The dragged row's copy, lifted a little, under the pointer.
    @ViewBuilder private var floating: some View {
        if let drag, let place = player.upNext.firstIndex(where: { $0.id == drag.id }) {
            let home = drag.slots[place] ?? drag.start
            TrackRow(track: player.upNext[place], isCurrent: false, isPlaying: false)
                .frame(width: drag.start.width, height: drag.start.height)
                .background(RowGlass(shown: true))
                .offset(x: drag.start.minX, y: drag.settling ? home.minY : drag.start.minY + drag.translation)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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
