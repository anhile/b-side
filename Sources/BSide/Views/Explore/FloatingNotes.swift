import AppKit
import SwiftUI

/// Music notes drifting up behind an empty Explore, barely visible: some
/// life on a page that has nothing yet. Drawn in one Canvas, 30 frames a
/// second, and only while the page shows; still with Reduce Motion.
///
/// The notes keep to lanes, a cover's width apart, two to a lane at an even
/// distance, so they never meet: each lane rises at its own steady pace, and
/// a note sways and tilts within its lane, never into the next.
struct FloatingNotes: View {
    let running: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The glyph and its size against `emptyGlyph`.
    private static let variants: [(String, Double)] = [("music.note", 1), ("music.quarternote.3", 0.8),
                                                        ("music.note", 0.7), ("music.note.list", 0.8)]
    private static let perLane = 2
    /// One sway, there and back, in seconds; and the tilt at its widest, in degrees.
    private static let swayPeriod = 9.0
    private static let tilt = 10.0
    /// The clear oval around the empty state's text, against the width and
    /// a cover's height; notes start fading at this share of the way in.
    private static let clearWidth = 0.42
    private static let clearHeight = 0.8
    private static let clearStart = 0.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / Theme.Motion.notesFrameRate, paused: !running || reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let lanes = max(3, Int(size.width / Theme.Size.cover) + 1)
                let span = size.height + Theme.Size.cover
                for lane in 0..<lanes {
                    // Steady per lane, a little different between lanes; the
                    // golden ratio spreads the starts so no two lanes line up.
                    let golden = (Double(lane) * 0.618).truncatingRemainder(dividingBy: 1)
                    let speed = Theme.Motion.notesRise * (0.85 + 0.3 * golden)
                    let laneX = size.width * (Double(lane) + 0.5) / Double(lanes)
                    for slot in 0..<Self.perLane {
                        let id = (lane + slot * 2) % Self.variants.count
                        guard let note = context.resolveSymbol(id: id) else { continue }
                        let start = (golden + Double(slot) / Double(Self.perLane)) * span
                        let rise = (time * speed + start).truncatingRemainder(dividingBy: span)
                        let phase = 2 * .pi * (time / Self.swayPeriod + golden + Double(slot) * 0.5)
                        let point = CGPoint(x: laneX + sin(phase) * Theme.Motion.notesSway,
                                            y: size.height + Theme.Size.cover / 2 - rise)
                        // Fade in from the bottom and out at the top, and give
                        // way to the text in the middle.
                        let edge = min(rise, span - rise) / Theme.Size.cover
                        let fromText = hypot((point.x - size.width / 2) / (size.width * Self.clearWidth),
                                             (point.y - size.height / 2) / (Theme.Size.cover * Self.clearHeight))
                        let clear = (fromText - Self.clearStart) / (1 - Self.clearStart)
                        var layer = context
                        layer.opacity = Theme.Opacity.decoration * min(1, max(0, edge)) * min(1, max(0, clear))
                        layer.translateBy(x: point.x, y: point.y)
                        layer.rotate(by: .degrees(cos(phase) * Self.tilt))
                        layer.draw(note, at: .zero)
                    }
                }
            } symbols: {
                ForEach(Self.variants.indices, id: \.self) { index in
                    Image(systemName: Self.variants[index].0)
                        .font(.system(size: Theme.Size.emptyGlyph * Self.variants[index].1))
                        .foregroundStyle(Theme.Colors.text)
                        .tag(index)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
