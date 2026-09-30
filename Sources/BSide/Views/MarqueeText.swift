import SwiftUI

/// CUSTOM: one line of text that scrolls sideways when it does not fit,
/// pauses at the start of each pass, and simply truncates with Reduce
/// Motion on. Driven by the clock, not by animation state, so it never
/// gets stuck.
struct MarqueeText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var overflows: Bool { textWidth > containerWidth + 1 }

    var body: some View {
        Group {
            if overflows, !reduceMotion {
                TimelineView(.animation) { context in
                    let travel = textWidth + Theme.Space.xl
                    let cycle = Theme.Motion.marqueePause + travel / Theme.Motion.marqueeSpeed
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                    let offset = max(0, phase - Theme.Motion.marqueePause) * Theme.Motion.marqueeSpeed
                    HStack(spacing: Theme.Space.xl) {
                        label
                        label.accessibilityHidden(true) // the copy that follows the first around
                    }
                    .offset(x: -offset)
                }
                .mask(
                    // Fades the text out at the right edge instead of cutting it.
                    LinearGradient(stops: [.init(color: Theme.Colors.text, location: 0),
                                           .init(color: Theme.Colors.text, location: Theme.Motion.marqueeFade),
                                           .init(color: .clear, location: 1)], // tokens-ok: mask, not a colour
                                   startPoint: .leading, endPoint: .trailing)
                )
            } else {
                label.lineLimit(1)
            }
        }
        // minWidth 0: the fixed-size text inside must not set the width of
        // the strip; whatever does not fit is clipped and scrolls.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
    }
}
