import SwiftUI

/// CUSTOM: a word in a small capsule. With a symbol it is a part of what
/// was understood and has an x that takes it out; without one, a click
/// uses it.
struct Chip: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xxs) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .imageScale(.small)
                }
                Text(title)
                    .lineLimit(1)
                if symbol != nil {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .foregroundStyle(hovering ? Theme.Colors.text : Theme.Colors.textMuted)
                }
            }
            .font(Theme.Text.caption)
            .foregroundStyle(Theme.Colors.text)
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.xxs)
            .background(Theme.Colors.text.opacity(hovering ? Theme.Opacity.hover : 0), in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.Colors.controlBorder) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHand()
        .help(symbol == nil ? "Use these words" : "Leave out \(title)")
        .accessibilityLabel(symbol == nil ? title : "Leave out \(title)")
    }
}

/// Lays its children out in rows, wrapping to the next row when one is
/// full, as words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
