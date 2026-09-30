import AppKit
import QuartzCore
import SwiftUI

/// Turns its content round and round on the compositor, not in SwiftUI: a
/// SwiftUI animation redraws the whole view graph every frame and cost a
/// third of a CPU core. A Core Animation transform costs nothing measurable.
struct Spinning<Content: View>: NSViewRepresentable {
    let spinning: Bool
    /// Seconds per turn.
    let period: Double
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> SpinningHostingView<Content> {
        let view = SpinningHostingView(rootView: content())
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: SpinningHostingView<Content>, context: Context) {
        view.rootView = content()
        view.setSpinning(spinning && !reduceMotion, period: period)
    }
}

final class SpinningHostingView<Content: View>: NSHostingView<Content> {
    private static var key: String { "spin" }
    private var isSpinning = false

    override func layout() {
        super.layout()
        // AppKit keeps a layer's anchor at the corner; turning needs the centre.
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.position = CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Where the record rests when it is not turning, in radians.
    private var restAngle: Double = 0

    func setSpinning(_ spinning: Bool, period: Double) {
        guard spinning != isSpinning, let layer else { return }
        isSpinning = spinning
        let current = (layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double) ?? restAngle
        layer.removeAllAnimations()
        if spinning {
            // Picks up where it stopped. Clockwise, as a record turns.
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = current
            turn.toValue = current - 2 * Double.pi
            turn.duration = period
            turn.repeatCount = .infinity
            layer.add(turn, forKey: Self.key)
            layer.setValue(current, forKeyPath: "transform.rotation.z")
        } else {
            // Stops like a turntable: runs on a little, then rolls back.
            let overshoot = current - Theme.Motion.recordOvershoot
            restAngle = current + Theme.Motion.recordRollback
            let stop = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            stop.values = [current, overshoot, restAngle]
            stop.keyTimes = [0, 0.45, 1]
            stop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            stop.duration = Theme.Motion.recordStop
            layer.add(stop, forKey: Self.key)
            layer.setValue(restAngle, forKeyPath: "transform.rotation.z")
        }
    }
}
