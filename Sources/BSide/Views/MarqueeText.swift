import AppKit
import QuartzCore
import SwiftUI

/// CUSTOM: one line of text that scrolls sideways when it does not fit,
/// pauses at the start of each pass, and fades at the edges. The movement
/// is a Core Animation keyframe, so SwiftUI draws nothing while it runs;
/// a SwiftUI-driven version cost a quarter of a CPU core. With Reduce
/// Motion on, the text simply truncates.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    /// Where the text sits when it fits. Scrolling always starts at the left.
    var centered = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        } else {
            MarqueeHost(text: text, font: font, color: color, centered: centered)
                .accessibilityLabel(text)
        }
    }
}

private struct MarqueeHost: NSViewRepresentable {
    let text: String
    let font: Font
    let color: Color
    let centered: Bool

    func makeNSView(context: Context) -> MarqueeView {
        MarqueeView()
    }

    func updateNSView(_ view: MarqueeView, context: Context) {
        view.centered = centered
        view.set(text: text, font: font, color: color)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarqueeView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.textWidth, height: nsView.lineHeight)
    }
}

final class MarqueeView: NSView {
    var centered = false {
        didSet { if centered != oldValue { configured = nil; needsLayout = true } }
    }
    private var text = ""
    private var font: Font = .body
    private var color: Color = .primary // tokens-ok: replaced before the first draw
    private var label: NSHostingView<AnyView>?
    private let mask = CAGradientLayer()
    private var configured: (String, CGFloat)?

    private(set) var textWidth: CGFloat = 0
    private(set) var lineHeight: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor] // tokens-ok: a mask
    }

    required init?(coder: NSCoder) { nil }

    func set(text: String, font: Font, color: Color) {
        guard text != self.text || configured == nil else { return }
        self.text = text
        self.font = font
        self.color = color
        let single = NSHostingView(rootView: AnyView(line(text)))
        textWidth = single.fittingSize.width
        lineHeight = single.fittingSize.height
        configured = nil
        needsLayout = true
    }

    private func line(_ text: String) -> some View {
        Text(text).font(font).foregroundStyle(color).fixedSize()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        if let configured, configured == (text, width) { return }
        configured = (text, width)
        label?.removeFromSuperview()
        layer?.mask = nil

        let overflows = textWidth > width + 1
        let gap = Theme.Space.xl
        let root: AnyView = overflows
            ? AnyView(HStack(spacing: gap) { line(text); line(text) })
            : AnyView(line(text))
        let label = NSHostingView(rootView: root)
        label.wantsLayer = true
        let x = !overflows && centered ? (width - textWidth) / 2 : 0
        label.frame = NSRect(x: x, y: 0, width: overflows ? textWidth * 2 + gap : textWidth, height: bounds.height)
        addSubview(label)
        self.label = label
        guard overflows else { return }

        // Rests, then travels one text length plus the gap, and repeats.
        let travel = textWidth + gap
        let pause = Theme.Motion.marqueePause
        let cycle = pause + travel / Theme.Motion.marqueeSpeed
        let move = CAKeyframeAnimation(keyPath: "position.x")
        move.values = [0, 0, -travel]
        move.keyTimes = [0, NSNumber(value: pause / cycle), 1]
        move.isAdditive = true
        move.duration = cycle
        move.repeatCount = .infinity
        label.layer?.add(move, forKey: "marquee")

        // Fades at both edges while moving; only at the right while resting,
        // so the first letters read.
        let fade = Theme.Motion.marqueeFade
        mask.frame = bounds
        mask.locations = [0, 0, NSNumber(value: 1 - fade), 1]
        let edges = CAKeyframeAnimation(keyPath: "locations")
        edges.values = [[0, 0, 1 - fade, 1], [0, 0, 1 - fade, 1], [0, fade, 1 - fade, 1], [0, fade, 1 - fade, 1]]
        edges.keyTimes = [0, NSNumber(value: pause / cycle), NSNumber(value: pause / cycle + 0.02), 1]
        edges.duration = cycle
        edges.repeatCount = .infinity
        mask.add(edges, forKey: "edges")
        layer?.mask = mask
    }
}
