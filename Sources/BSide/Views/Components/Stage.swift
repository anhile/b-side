import SwiftUI

/// The one layout of the screens without music: Welcome, signing in and
/// "Nothing playing". A stage of one height for the picture, a display
/// title, two lines of body text (room for two always), the actions in a
/// space of one height (empty while there are none), and a note at the
/// bottom. The same on all three, so one hands over to the next with
/// nothing moving. In a short window the note goes first, then the stage
/// shrinks.
struct StageLayout<Stage: View, Actions: View>: View {
    let title: String
    let text: String
    var note: (text: String, symbol: String)?
    @ViewBuilder let stage: () -> Stage
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .vertical) {
            layout(scale: 1, withNote: true)
            layout(scale: 1, withNote: false)
            layout(scale: Theme.Size.stageCompact, withNote: false)
        }
    }

    private func layout(scale: CGFloat, withNote: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.m)
            stage()
                .frame(height: Theme.Size.stage)
                .scaleEffect(scale)
                .frame(height: Theme.Size.stage * scale)
            Text(title)
                .font(Theme.Text.display)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(Theme.Size.stageCompact)
                .contentTransition(.opacity)
                .padding(.top, scale < 1 ? Theme.Space.l : Theme.Space.xl)
            Text(text)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.Colors.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: Theme.Size.stageText)
                .contentTransition(.opacity)
                .padding(.top, Theme.Space.xs)
            VStack(spacing: Theme.Space.s) { actions() }
                .frame(height: Theme.Size.stageActions, alignment: .top)
                .padding(.top, Theme.Space.l)
            Spacer(minLength: Theme.Space.m)
            if withNote, let note {
                Label(note.text, systemImage: note.symbol)
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, Theme.Space.m)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A sleeve behind the stage's record: a Vibe colour and a glyph.
struct StageSleeve: Hashable {
    let colour: Int
    let symbol: String

    /// Likes, playlists and vibes: what an account brings.
    static let account = [StageSleeve(colour: 1, symbol: Page.playlists.symbol),
                          StageSleeve(colour: 2, symbol: Page.vibe.symbol),
                          StageSleeve(colour: 0, symbol: "heart.fill")]

    /// The first three Vibe tiles, the one Play Vibe plays behind the record.
    @MainActor
    static func vibes(of player: PlayerController) -> [StageSleeve] {
        var moods = Array(player.moods.prefix(3))
        if let first = player.vibeMood, let index = moods.firstIndex(where: { $0.id == first.id }) {
            moods.append(moods.remove(at: index))
        }
        // Three colours, even when two tiles share one: the next free one.
        var used: Set<Int> = []
        let sleeves = moods.map { mood in
            var colour = VibePalette.index(for: mood)
            while used.contains(colour) { colour = (colour + 1) % VibePalette.swatches.count }
            used.insert(colour)
            return StageSleeve(colour: colour, symbol: mood.symbol)
        }
        return sleeves.count == 3 ? sleeves : account
    }
}

/// The record, and behind it three sleeves that fan out after a beat,
/// turned a little, as records leaned in a crate: left, right, and the
/// third behind, above the record. Folded, the sleeves are out of sight
/// behind the record (Welcome).
struct RecordWithSleeves: View {
    var sleeves = StageSleeve.account
    var fanned = true
    var spinning = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Where each sleeve settles, against its size, and its turn in degrees.
    private static let places: [(x: CGFloat, y: CGFloat, angle: Double)] = [(-0.55, 0.06, -12), (0.55, 0.06, 12),
                                                                            (0, -backRise, 0)]
    /// How far the sleeve behind stands above the record, against its size.
    static let backRise: CGFloat = 0.2

    var body: some View {
        Record(size: Theme.Size.artworkLarge, spinning: spinning)
            .shadow(color: Theme.Colors.shadow.opacity(Theme.Opacity.signInShadow),
                    radius: Theme.Space.s, y: Theme.Space.xxs)
            .background { fan }
            .padding(.top, Theme.Size.signInSleeve * Self.backRise)
            .onAppear {
                if reduceMotion { appeared = true; return }
                withAnimation(.spring(duration: Theme.Motion.signInFan, bounce: 0.25).delay(Theme.Motion.signInFanDelay)) {
                    appeared = true
                }
            }
            .onDisappear { appeared = false }
            .animation(.spring(duration: Theme.Motion.signInFan, bounce: 0.25), value: fanned)
            .accessibilityHidden(true)
    }

    private var out: Bool { fanned && appeared }

    private var fan: some View {
        let size = Theme.Size.signInSleeve
        return ZStack {
            ForEach(Array(zip(sleeves.prefix(3), Self.places).enumerated()), id: \.offset) { _, pair in
                let (sleeve, place) = pair
                let swatch = VibePalette.swatches[sleeve.colour % VibePalette.swatches.count]
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(LinearGradient(colors: [swatch.light, swatch.deep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: place.x < 0 ? .topLeading : .topTrailing) {
                        Image(systemName: sleeve.symbol)
                            .font(.system(size: Theme.Size.signInSleeveGlyph, weight: .semibold))
                            .foregroundStyle(Theme.Colors.onVibe)
                            .padding(Theme.Space.s)
                    }
                    .frame(width: size, height: size)
                    .shadow(color: swatch.deep.opacity(Theme.Opacity.vibeShadow), radius: Theme.Space.s, y: Theme.Space.xxs)
                    .rotationEffect(.degrees(out ? place.angle : 0))
                    .offset(x: out ? place.x * size : 0, y: out ? place.y * size : 0)
                    .opacity(out ? 1 : 0)
            }
        }
    }
}
