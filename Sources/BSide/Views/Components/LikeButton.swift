import SwiftUI

/// CUSTOM: the heart, on Now Playing and in the strip. Orange and filled
/// once liked. A like is celebrated a little: the heart bounces, a thin
/// ring spreads from it and a few small hearts fly out and fade; taking
/// the like back only empties the heart. With Reduce Motion, only the
/// colour changes. Its name and Command-L show in the app's tooltip, over
/// the button: under it lie the progress line and, in the strip, the
/// window's edge.
struct LikeButton: View {
    let liked: Bool
    var target: CGFloat = Theme.Size.transportTarget
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Snapshots: the burst held at this point of its way, the tooltip shown.
    @Environment(\.previewLikeBurst) private var fixedBurst
    @State private var hovering = false
    /// A burst on its way out: its start, so a new like starts a new one.
    @State private var burst: Date?

    /// The small hearts: their direction in degrees, from straight up.
    private static let sparks: [Double] = [-70, -35, 0, 35, 70, 180]

    var body: some View {
        Button(action: action) {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: Theme.Size.transportGlyph, weight: .semibold))
                .foregroundStyle(liked ? Theme.Colors.accentText : Theme.Colors.textMuted)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? false : liked)
                .frame(width: target, height: target)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
        .overlay { celebration.allowsHitTesting(false) }
        .onHover { hovering = $0 }
        .tooltip(liked ? "Remove Like" : "Like", shortcut: "\u{2318}L", above: true, shown: (hovering || fixedBurst != nil) && isEnabled)
        .accessibilityLabel(liked ? "Remove Like" : "Like")
        .onChange(of: liked) { _, now in
            guard now, !reduceMotion else { return }
            burst = Date()
        }
    }

    /// The ring and the small hearts, drawn for one burst's length.
    @ViewBuilder private var celebration: some View {
        if let fixedBurst {
            burstFrame(fixedBurst)
        } else if let burst {
            TimelineView(.animation) { context in
                burstFrame(min(context.date.timeIntervalSince(burst) / Theme.Motion.likeBurst, 1))
            }
            .task(id: burst) {
                try? await Task.sleep(for: .seconds(Theme.Motion.likeBurst))
                if self.burst == burst { self.burst = nil }
            }
            .accessibilityHidden(true)
        }
    }

    /// The burst at a point of its way, 0 to 1.
    private func burstFrame(_ progress: Double) -> some View {
        let out = 1 - pow(1 - progress, 3) // fast, then slowing
        return ZStack {
            Circle()
                .strokeBorder(Theme.Colors.accent, lineWidth: Theme.Size.likeRing * (1 - progress))
                .frame(width: Theme.Size.transportGlyph, height: Theme.Size.transportGlyph)
                .scaleEffect(1 + out * Theme.Size.likeRingGrowth)
                .opacity(1 - progress)
            ForEach(Self.sparks, id: \.self) { angle in
                let radians = (angle - 90) * .pi / 180
                Image(systemName: "heart.fill")
                    .font(.system(size: Theme.Size.likeSpark))
                    .foregroundStyle(Theme.Colors.accent)
                    .scaleEffect(0.4 + 0.6 * (1 - progress))
                    .offset(x: cos(radians) * Theme.Size.likeSparkReach * out,
                            y: sin(radians) * Theme.Size.likeSparkReach * out)
                    .opacity(progress < 0.15 ? progress / 0.15 : 1 - progress)
            }
        }
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    @Entry var previewLikeBurst: Double?
}
