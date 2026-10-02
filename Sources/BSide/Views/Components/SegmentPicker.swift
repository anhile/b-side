import AppKit
import SwiftUI

/// CUSTOM: the kinds of search, as segments of equal width. The current one
/// is an orange pill that slides to the next with a light spring; no track
/// under them, the titles stand on the page. The titles
/// are drawn twice, muted and white, the white ones cut to the pill's shape,
/// so a title turns white exactly where the pill passes under it. No hover
/// background, which would clash with the pill: a hovered title darkens.
/// Every title keeps its weight, so nothing changes width on a click.
struct SegmentPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    @State private var hovered: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentIndex: Int { options.firstIndex { $0.0 == selection } ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let isCurrent = index == currentIndex
                Button { selection = options[index].0 } label: {
                    title(index, color: hovered == index && !isCurrent ? Theme.Colors.text : Theme.Colors.textMuted)
                }
                .buttonStyle(SegmentStyle())
                .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .background { pill.foregroundStyle(Theme.Colors.accent) }
        .overlay {
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { title($0, color: Theme.Colors.accentOnWhite) }
            }
            .mask { pill }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : .snappy(duration: Theme.Motion.page), value: currentIndex)
        .animation(.easeOut(duration: Theme.Motion.feedback), value: hovered)
    }

    private func title(_ index: Int, color: Color) -> some View {
        Text(options[index].1)
            .font(Theme.Text.label.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.pageDotTarget)
            .contentShape(Capsule())
    }

    /// One segment wide, under the current one.
    private var pill: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(max(options.count, 1))
            Capsule()
                .frame(width: width, height: proxy.size.height)
                .offset(x: width * CGFloat(currentIndex))
        }
    }

    /// Dims while pressed; nothing else.
    private struct SegmentStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? Theme.Opacity.pressed : 1)
                .pointingHand()
                .animation(.easeOut(duration: Theme.Motion.feedback), value: configuration.isPressed)
        }
    }
}
