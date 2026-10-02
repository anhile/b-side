import SwiftUI

/// One job: start music for how I feel right now, in one click.
struct VibePage: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.footerRoom) private var footerRoom

    /// The tile being edited, or a new one.
    @State private var editing: Mood?
    /// The New Vibe sheet: a new tile from words, or one made from words
    /// made again.
    @State private var describing: Describing?
    /// The tile being dragged to another place.
    @State private var dragged: Mood.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Describing: Identifiable {
        let id = UUID()
        var replacing: Mood?
    }

    private let columns = [
        GridItem(.fixed(Theme.Size.tileWidth), spacing: Theme.Space.s),
        GridItem(.fixed(Theme.Size.tileWidth), spacing: Theme.Space.s),
    ]

    private func move(_ mood: Mood, by step: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: Theme.Motion.page)) { player.move(mood, by: step) }
    }

    var body: some View {
        if let blocked = blockingState(for: player) {
            blocked
                .padding(.bottom, footerRoom)
        } else if player.account == .unknown {
            SkeletonList()
                .padding(.top, Theme.Space.s)
                .padding(.bottom, footerRoom)
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(player.moods) { mood in
                    let locked = mood.needsAccount && player.account == .signedOut
                    let play = { locked ? player.showSignIn() : player.play(mood) }
                    // A click plays, a drag moves the tile: not a Button,
                    // which would keep the mouse and never let a drag start.
                    MoodTile(mood: mood, subtitle: locked ? "Sign in to play" : mood.subtitle(playlists: player.playlists),
                             isCurrent: player.source == .mood(mood.id), isPlaying: player.state.isPlaying)
                        .modifier(TileLift())
                        .onTapGesture(perform: play)
                        .onDrag {
                            dragged = mood.id
                            return NSItemProvider(object: mood.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: TileDrop(target: mood.id, dragged: $dragged) { id in
                            withAnimation(reduceMotion ? nil : .snappy(duration: Theme.Motion.page)) {
                                player.move(id, toPlaceOf: mood.id)
                            }
                        })
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, play)
                        .help(mood.name)
                        .contextMenu {
                            Group {
                                Button {
                                    if case .described = mood.source { describing = Describing(replacing: mood) } else { editing = mood }
                                } label: {
                                    Label("Edit…", systemImage: "pencil")
                                }
                                Divider()
                                Button { move(mood, by: -1) } label: { Label("Move Earlier", systemImage: "arrow.left") }
                                    .disabled(mood.id == player.moods.first?.id)
                                Button { move(mood, by: 1) } label: { Label("Move Later", systemImage: "arrow.right") }
                                    .disabled(mood.id == player.moods.last?.id)
                                Divider()
                                Button(role: .destructive) { player.remove(mood) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .labelStyle(.titleAndIcon)
                        }
                }
                Button {
                    describing = Describing()
                } label: {
                    AddTile(isFirst: player.moods.isEmpty)
                }
                .buttonStyle(TileButtonStyle())
                .help("Add a vibe")
                .accessibilityLabel("Add a vibe")
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m) // air under the title bar
            .padding(.bottom, Theme.Space.xs)
            .background(OverlayScrollers())
        }
        .contentMargins(.bottom, footerRoom, for: .scrollContent)
        .contentMargins(.bottom, footerRoom, for: .scrollIndicators)
        // A drop between the tiles ends the drag too.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            defer { dragged = nil }
            return dragged != nil
        }
        .sheet(item: $describing) { describing in
            NewVibeSheet(replacing: describing.replacing) {
                // After this sheet is gone: one sheet at a time.
                DispatchQueue.main.async { editing = Mood(name: "", source: .likedShuffled) }
            }
        }
        .sheet(item: $editing) { mood in
            MoodEditor(mood: mood, playlists: player.playlists) { saved in
                player.save(saved)
            }
        }
    }
}

/// Moves the dragged tile to the place of the tile it is over, as it gets
/// there, so the others make room before the drop.
private struct TileDrop: DropDelegate {
    let target: Mood.ID
    @Binding var dragged: Mood.ID?
    let move: (Mood.ID) -> Void

    func dropEntered(info: DropInfo) {
        if let dragged, dragged != target { move(dragged) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: dragged == nil ? .cancel : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragged = nil }
        return dragged != nil
    }
}
