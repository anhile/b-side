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
    @State private var drag: TileDrag?
    /// Where each tile is in the grid, for the drag.
    @State private var frames: [Mood.ID: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Describing: Identifiable {
        let id = UUID()
        var replacing: Mood?
    }

    /// Two tiles across the window at its least size; wider, the tiles
    /// grow until a third column fits.
    private let columns = [GridItem(.adaptive(minimum: Theme.Size.tileWidth), spacing: Theme.Space.s)]

    /// A tile on its way to another place. A copy of it follows the pointer
    /// above the grid, and the tile itself, unseen, keeps its place in the
    /// grid, so the others make room around it.
    private struct TileDrag {
        let id: Mood.ID
        /// Where every place of the grid is, by its number. The tiles are
        /// all one size, so the places stay put while the tiles change them.
        let slots: [Int: CGRect]
        /// The tile's own place as the drag began.
        let start: CGRect
        var translation: CGSize = .zero
        /// The mouse is let go, and the copy is on its way to the tile's place.
        var settling = false
    }

    private static let grid = "tiles"

    private var moving: Animation? { reduceMotion ? nil : .snappy(duration: Theme.Motion.page) }

    private func move(_ mood: Mood, by step: Int) {
        withAnimation(moving) { player.move(mood, by: step) }
    }

    private func tile(_ mood: Mood) -> MoodTile {
        let locked = mood.needsAccount && player.account == .signedOut
        return MoodTile(mood: mood, subtitle: locked ? "Sign in to play" : mood.subtitle(playlists: player.playlists),
                        isCurrent: player.source == .mood(mood.id), isPlaying: player.state.isPlaying)
    }

    /// Our own drag, not the system's drag and drop: that one starts late
    /// and shows a picture of the tile while the tile stays where it was.
    private func reorder(_ mood: Mood) -> some Gesture {
        DragGesture(minimumDistance: Theme.Space.xxs, coordinateSpace: .named(Self.grid))
            .onChanged { value in
                if drag == nil, let start = frames[mood.id] {
                    var slots: [Int: CGRect] = [:]
                    for (place, mood) in player.moods.enumerated() { slots[place] = frames[mood.id] }
                    drag = TileDrag(id: mood.id, slots: slots, start: start)
                }
                guard let drag, drag.id == mood.id, !drag.settling else { return }
                self.drag?.translation = value.translation
                // Between the tiles the pointer is over no place, and nothing moves.
                guard let place = drag.slots.first(where: { $0.value.contains(value.location) })?.key,
                      player.moods.indices.contains(place), player.moods[place].id != mood.id else { return }
                withAnimation(moving) { player.move(mood.id, toPlaceOf: player.moods[place].id) }
            }
            .onEnded { _ in
                guard drag?.id == mood.id else { return }
                withAnimation(moving) { drag?.settling = true } completion: { drag = nil }
            }
    }

    /// The dragged tile's copy, a little larger, as a tile under the pointer is.
    @ViewBuilder private var floating: some View {
        if let drag, let place = player.moods.firstIndex(where: { $0.id == drag.id }) {
            let home = drag.slots[place] ?? drag.start
            tile(player.moods[place])
                .frame(width: drag.start.width, height: drag.start.height)
                .scaleEffect(drag.settling || reduceMotion ? 1 : Theme.Motion.tileHover)
                .offset(x: drag.settling ? home.minX : drag.start.minX + drag.translation.width,
                        y: drag.settling ? home.minY : drag.start.minY + drag.translation.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
                    tile(mood)
                        .modifier(TileLift())
                        .opacity(drag?.id == mood.id ? 0 : 1)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.grid)) } action: { frames[mood.id] = $0 }
                        .onTapGesture(perform: play)
                        .gesture(reorder(mood))
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
            .coordinateSpace(name: Self.grid)
            .overlay(alignment: .topLeading) { floating }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m) // air under the title bar
            .padding(.bottom, Theme.Space.xs)
            .background(OverlayScrollers())
        }
        .contentMargins(.bottom, footerRoom, for: .scrollContent)
        .contentMargins(.bottom, footerRoom, for: .scrollIndicators)
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
