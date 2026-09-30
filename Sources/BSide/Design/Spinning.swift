import AppKit
import QuartzCore
import SwiftUI

/// Turns its content round and round on the compositor, not in SwiftUI: a
/// SwiftUI animation redraws the whole view graph every frame and cost a
/// third of a CPU core. The content is drawn once into an image on a layer
/// of our own (AppKit manages a view's layer and moves it under us), and
/// Core Animation rotates that layer for free.
struct Spinning<Content: View>: NSViewRepresentable {
    let spinning: Bool
    /// Seconds per turn.
    let period: Double
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> SpinningView {
        SpinningView()
    }

    func updateNSView(_ view: SpinningView, context: Context) {
        view.render = { size, scale in
            let renderer = ImageRenderer(content: content()
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = scale
            return renderer.cgImage
        }
        view.scheme = colorScheme
        view.setSpinning(spinning && !reduceMotion, period: period)
    }
}

final class SpinningView: NSView {
    var render: ((CGSize, CGFloat) -> CGImage?)?
    var scheme: ColorScheme = .light {
        didSet { if scheme != oldValue { drawnFor = nil; needsLayout = true } }
    }

    private let disc = CALayer()
    private var drawnFor: CGSize?
    private var isSpinning = false
    private var restAngle: Double = 0
    private static let key = "spin"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        disc.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        disc.contentsGravity = .resizeAspect
        layer?.addSublayer(disc)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        disc.bounds = bounds
        disc.position = CGPoint(x: bounds.midX, y: bounds.midY)
        if drawnFor != bounds.size, bounds.width > 0 {
            drawnFor = bounds.size
            let scale = window?.backingScaleFactor ?? 2
            disc.contentsScale = scale
            disc.contents = render?(bounds.size, scale)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        drawnFor = nil
        needsLayout = true
    }

    func setSpinning(_ spinning: Bool, period: Double) {
        guard spinning != isSpinning else { return }
        isSpinning = spinning
        let current = (disc.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double) ?? restAngle
        disc.removeAllAnimations()
        if spinning {
            // Picks up where it stopped. Clockwise, as a record turns.
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = current
            turn.toValue = current - 2 * Double.pi
            turn.duration = period
            turn.repeatCount = .infinity
            disc.add(turn, forKey: Self.key)
            disc.setValue(current, forKeyPath: "transform.rotation.z")
        } else {
            // Stops like a turntable: runs on a little, then rolls back.
            let overshoot = current - Theme.Motion.recordOvershoot
            restAngle = current + Theme.Motion.recordRollback
            let stop = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            stop.values = [current, overshoot, restAngle]
            stop.keyTimes = [0, 0.45, 1]
            stop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            stop.duration = Theme.Motion.recordStop
            disc.add(stop, forKey: Self.key)
            disc.setValue(restAngle, forKeyPath: "transform.rotation.z")
        }
    }
}
