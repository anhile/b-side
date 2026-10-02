import AppKit
import SwiftUI

/// CUSTOM: the track's progress, in place of the system slider, which can
/// neither change colour smoothly nor say where the pointer is. The
/// filled part is a light orange; under the pointer it turns full orange,
/// a thin tick marks where a click would go, and that time shows above
/// it, clear of the pointer. Dragging scrubs; the seek happens on release.
struct ProgressBar: View {
    let position: Double
    let duration: Double
    let time: (Double) -> String
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    @State private var pointer: CGFloat?
    @State private var dragging = false
    @Environment(\.isEnabled) private var isEnabled

    private var active: Bool { isEnabled && (pointer != nil || dragging) }

    var body: some View {
        let length = max(duration, 1)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let knob = Theme.Size.progressKnob
                let filled = width * CGFloat(min(max(position / length, 0), 1))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.text.opacity(Theme.Opacity.progressTrack))
                    Capsule()
                        .fill(Theme.Colors.accent.opacity(active ? 1 : Theme.Opacity.progressRest))
                        .frame(width: max(filled, Theme.Size.progressLine))
                }
                .frame(height: Theme.Size.progressLine)
                .overlay(alignment: .leading) {
                    // Where a click would go.
                    if isEnabled, !dragging, let pointer {
                        Capsule()
                            .fill(Theme.Colors.text)
                            .frame(width: Theme.Size.progressTick, height: Theme.Size.progressKnob.height)
                            .offset(x: min(max(pointer, 0), width) - Theme.Size.progressTick / 2)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.knob)
                        .shadow(color: Theme.Colors.shadow.opacity(Theme.Opacity.groove), radius: 1, y: 0.5)
                        .frame(width: knob.width, height: knob.height)
                        .offset(x: min(max(filled - knob.width / 2, 0), width - knob.width))
                        .opacity(isEnabled ? 1 : 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .pointingHand(isEnabled)
                .onContinuousHover { phase in
                    if case .active(let point) = phase { pointer = point.x } else { pointer = nil }
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        pointer = drag.location.x
                        onScrub(seconds(at: drag.location.x, width: width))
                    }
                    .onEnded { drag in
                        dragging = false
                        onCommit(seconds(at: drag.location.x, width: width))
                    })
            }
            .frame(height: Theme.Size.progressTarget)
            .overlay { pointerTime }
            labels
        }
        .animation(.easeOut(duration: Theme.Motion.page), value: active)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(time(position)) of \(time(duration))")
        .accessibilityAdjustableAction { direction in
            let step = Tuning.seekStep
            let target = direction == .increment ? position + step : position - step
            onCommit(min(max(target, 0), length))
        }
    }

    /// Elapsed on the left, the length on the right, and while the
    /// pointer is over the bar, the time under it.
    /// Elapsed on the left, the length on the right.
    private var labels: some View {
        HStack {
            Text(time(position))
            Spacer()
            Text(time(duration))
        }
        .font(Theme.Text.caption)
        .monospacedDigit()
        .foregroundStyle(Theme.Colors.textMuted)
    }

    /// While the pointer is over the bar, the time under it, just above
    /// the line, where the pointer does not cover it.
    private var pointerTime: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let half = Theme.Size.timeLabel / 2
            if active, let pointer {
                Text(time(seconds(at: pointer, width: width)))
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.accentText)
                    .fixedSize()
                    .position(x: min(max(pointer, half), width - half), y: -Theme.Space.xxs)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func seconds(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * max(duration, 0)
    }
}
