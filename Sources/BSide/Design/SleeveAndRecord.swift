import AppKit
import QuartzCore
import SwiftUI

/// The Now Playing centrepiece: the artwork as a record sleeve and the record
/// itself, as two Core Animation layers. While music plays the sleeve moves
/// left and the record moves right, half the peek each, so the pair stays
/// centred; on pause both return to the middle and the record is hidden
/// inside the sleeve. Layer positions animate implicitly, and an interrupted
/// move always continues to the new target, however fast Play and Pause
/// alternate. The record turns on the same layer (see Spinning for why).
struct SleeveAndRecord: NSViewRepresentable {
    let url: URL?
    let spinning: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> SleeveAndRecordView {
        SleeveAndRecordView()
    }

    func updateNSView(_ view: SleeveAndRecordView, context: Context) {
        view.scheme = colorScheme
        view.reduceMotion = reduceMotion
        view.artworkURL = url
        view.setPlaying(spinning)
    }
}

final class SleeveAndRecordView: NSView {
    var scheme: ColorScheme = .light {
        didSet { if scheme != oldValue { drawnFor = nil; needsLayout = true } }
    }
    var reduceMotion = false
    var artworkURL: URL? {
        didSet { if artworkURL != oldValue { loadArtwork() } }
    }

    private let sleeveShadow = CALayer()   // carries the shadow; the sleeve clips its corners
    private let sleeve = CALayer()
    private let disc = CALayer()
    private var drawnFor: CGSize?
    private var artwork: CGImage?
    private var isPlaying = false
    private var restAngle: Double = 0
    private static let spinKey = "spin"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for item in [disc, sleeveShadow, sleeve] { item.anchorPoint = CGPoint(x: 0.5, y: 0.5) }
        disc.contentsGravity = .resizeAspect
        sleeve.contentsGravity = .resizeAspectFill
        sleeve.masksToBounds = true
        sleeve.cornerRadius = Theme.Radius.sleeve
        sleeveShadow.shadowOpacity = Float(Theme.Shadow.artworkOpacity)
        sleeveShadow.shadowRadius = Theme.Shadow.artworkRadius
        sleeveShadow.shadowOffset = CGSize(width: 0, height: -Theme.Shadow.artworkY)
        layer?.addSublayer(disc)
        layer?.addSublayer(sleeveShadow)
        sleeveShadow.addSublayer(sleeve)
    }

    required init?(coder: NSCoder) { nil }

    private var side: CGFloat { bounds.height }
    private var peek: CGFloat { bounds.width - side }

    override func layout() {
        super.layout()
        let square = CGRect(x: 0, y: 0, width: side, height: side)
        // A record is a little smaller than its sleeve, so no edge of it
        // shows above or below the sleeve.
        let discSquare = CGRect(x: 0, y: 0, width: side * Theme.Size.recordInSleeve, height: side * Theme.Size.recordInSleeve)
        disc.bounds = discSquare
        sleeveShadow.bounds = square
        sleeve.bounds = square
        sleeve.position = CGPoint(x: side / 2, y: side / 2)
        sleeveShadow.shadowPath = CGPath(roundedRect: square, cornerWidth: Theme.Radius.sleeve,
                                   cornerHeight: Theme.Radius.sleeve, transform: nil)
        sleeveShadow.shadowColor = NSColor(Theme.Colors.shadow).cgColor
        place(animated: false)
        if drawnFor != bounds.size, side > 0 {
            drawnFor = bounds.size
            let scale = window?.backingScaleFactor ?? 2
            disc.contentsScale = scale
            sleeve.contentsScale = scale
            disc.contents = render(RecordDisc(size: discSquare.width), size: discSquare.size, scale: scale)
            if artwork == nil {
                sleeve.contents = render(Artwork(url: nil, size: side, radius: 0), size: square.size, scale: scale)
            }
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        drawnFor = nil
        needsLayout = true
    }

    private func render<V: View>(_ view: V, size: CGSize, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// Where the two sit for the current state. Implicit layer animations
    /// move them; a change mid-move retargets the same animation.
    private func place(animated: Bool) {
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let shift = isPlaying ? peek / 2 : 0
        CATransaction.begin()
        if animated, !reduceMotion {
            CATransaction.setAnimationDuration(Theme.Motion.recordSlide)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        sleeveShadow.position = CGPoint(x: centre.x - shift, y: centre.y)
        disc.position = CGPoint(x: centre.x + shift, y: centre.y)
        CATransaction.commit()
    }

    func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        place(animated: true)
        spin(playing && !reduceMotion)
    }

    private func spin(_ spinning: Bool) {
        let current = (disc.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double) ?? restAngle
        disc.removeAnimation(forKey: Self.spinKey)
        if spinning {
            // Picks up where it stopped. Clockwise, as a record turns.
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = current
            turn.toValue = current - 2 * Double.pi
            turn.duration = Theme.Motion.recordTurn
            turn.repeatCount = .infinity
            disc.add(turn, forKey: Self.spinKey)
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
            disc.add(stop, forKey: Self.spinKey)
            disc.setValue(restAngle, forKeyPath: "transform.rotation.z")
        }
    }

    /// The previous picture stays until the new one is here, so nothing
    /// flashes; if the new one cannot be had, the placeholder takes its
    /// place rather than leaving the last track's cover up.
    private func loadArtwork() {
        guard let url = artworkURL else { return showPlaceholder() }
        Task { @MainActor [weak self] in
            let image = await ArtworkLoader.image(for: url)
            guard let self, self.artworkURL == url else { return }
            guard let image else { return self.showPlaceholder() }
            self.artwork = image
            self.sleeve.contents = image
        }
    }

    private func showPlaceholder() {
        artwork = nil
        drawnFor = nil // layout draws the placeholder
        needsLayout = true
    }
}
