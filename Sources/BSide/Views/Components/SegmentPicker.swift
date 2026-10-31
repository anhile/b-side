import AppKit
import SwiftUI

/// CUSTOM: the kinds of search, as segments of equal width on a soft
/// track, as the system's segmented controls are: the current one a raised
/// pill in the page's colour, with a hairline and a little shadow, that
/// slides to the next with a light spring (since 2026-10-31; before, an
/// orange pill with no track, which competed with the buttons). The titles
/// are drawn twice, muted and in `text`, the second cut to the pill's
/// shape, so a title brightens exactly where the pill passes under it. A
/// hovered title darkens. Every title keeps its weight, so nothing changes
/// width on a click.
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
        .background {
            pill
                .foregroundStyle(Theme.Colors.bg)
                .shadow(color: Theme.Colors.shadow.opacity(Theme.Opacity.segmentShadow), radius: Theme.Space.xxs / 2, y: 1)
        }
        .overlay {
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { title($0, color: Theme.Colors.text) }
            }
            .mask { pill }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(Theme.Size.segmentInset)
        .background(Theme.Colors.text.opacity(Theme.Opacity.segmentTrack), in: Capsule())
        .animation(reduceMotion ? nil : .snappy(duration: Theme.Motion.page), value: currentIndex)
        .animation(.easeOut(duration: Theme.Motion.feedback), value: hovered)
    }

    private func title(_ index: Int, color: Color) -> some View {
        Text(options[index].1)
            .font(Theme.Text.label.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.segmentHeight)
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
