import AppKit
import SwiftUI

/// Large artwork as the sleeve, with the record out of it on the right while
/// music plays and inside it while paused. Both move, so the pair stays
/// centred. All of it is Core Animation (see SleeveAndRecord).
/// Grows into whatever height the page leaves, keeping the sleeve square
/// and the record's peek in proportion. `artworkLarge` is the smallest size.
struct ArtworkWithRecord: View {
    let url: URL?
    let spinning: Bool

    var body: some View {
        SleeveAndRecord(url: url, spinning: spinning)
            .aspectRatio((Theme.Size.artworkLarge + Theme.Size.recordPeek) / Theme.Size.artworkLarge, contentMode: .fit)
            .padding(Theme.Space.s) // a little smaller than the zone it sets
            .frame(maxWidth: .infinity, minHeight: Theme.Size.artworkLarge, maxHeight: .infinity)
            .padding(.horizontal, Theme.Space.m)
            .accessibilityHidden(true)
    }
}

/// CUSTOM: the vinyl record, the app's one piece of custom drawing. Grooves
/// in faint cream, an orange label with a hole, as on the icon. The turning
/// is done by `Spinning`, on the compositor.
struct Record: View {
    let size: CGFloat
    let spinning: Bool

    var body: some View {
        Spinning(spinning: spinning, period: Theme.Motion.recordTurn) {
            RecordDisc(size: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The still drawing of the record, at a given size.
struct RecordDisc: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.record)
            // Grooves only where they can be seen: none at row size.
            if size >= Theme.Size.artworkLarge / 2 {
                ForEach(1..<9) { ring in
                    Circle()
                        .strokeBorder(Theme.Colors.recordGroove.opacity(Theme.Opacity.groove), lineWidth: 1)
                        .padding(size * CGFloat(ring) * Theme.Size.recordGrooveStep)
                }
            }
            // A soft light across the surface, as on real vinyl. The disc is
            // otherwise symmetrical, and its turning would be invisible.
            if size >= Theme.Size.artworkLarge / 2 {
                Circle()
                    .fill(AngularGradient(stops: [
                        .init(color: .clear, location: 0), // tokens-ok: transparency, not a colour
                        .init(color: Theme.Colors.recordGroove.opacity(Theme.Opacity.sheen), location: 0.12),
                        .init(color: .clear, location: 0.26),
                        .init(color: .clear, location: 0.5),
                        .init(color: Theme.Colors.recordGroove.opacity(Theme.Opacity.sheen / 2), location: 0.62),
                        .init(color: .clear, location: 0.74),
                        .init(color: .clear, location: 1),
                    ], center: .center))
            }
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: size * Theme.Size.recordLabelRatio, height: size * Theme.Size.recordLabelRatio)
            Circle()
                .fill(Theme.Colors.accentOn)
                .frame(width: size * Theme.Size.recordHoleRatio, height: size * Theme.Size.recordHoleRatio)
        }
        .frame(width: size, height: size)
    }
}
