import SwiftUI

/// Waiting, said without words: a soft light runs across the view, inside
/// a shape the size of the view (the progress line's capsule, a cover's
/// rounded square), again and again. The shape, not the view, holds the
/// light in: a faint track would make it as faint.
/// With Reduce Motion the view breathes instead, its opacity rising and
/// falling. Drawn only while active.
struct Shimmer: ViewModifier {
    let active: Bool
    let colour: Color
    let shape: AnyShape

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Snapshots: the light held halfway, instead of wherever it is.
    @Environment(\.previewShimmerPhase) private var fixedPhase

    func body(content: Content) -> some View {
        if !active {
            content
        } else if reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / Theme.Motion.shimmerFrameRate)) { context in
                let phase = fixedPhase ?? Self.phase(at: context.date)
                content.opacity(1 - Theme.Opacity.shimmerBreath * (0.5 - 0.5 * cos(phase * 2 * .pi)))
            }
        } else {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1 / Theme.Motion.shimmerFrameRate)) { context in
                    let phase = fixedPhase ?? Self.phase(at: context.date)
                    GeometryReader { proxy in
                        let band = proxy.size.width * Theme.Size.shimmerBand
                        LinearGradient(colors: [colour.opacity(0), colour, colour.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + phase * (proxy.size.width + band))
                    }
                }
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    /// 0 to 1 over one pass.
    private static func phase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Theme.Motion.shimmerPeriod)
            / Theme.Motion.shimmerPeriod
    }
}

extension View {
    func shimmer<S: Shape>(_ active: Bool, colour: Color, in shape: S) -> some View {
        modifier(Shimmer(active: active, colour: colour, shape: AnyShape(shape)))
    }
}

extension EnvironmentValues {
    @Entry var previewShimmerPhase: Double?
}
