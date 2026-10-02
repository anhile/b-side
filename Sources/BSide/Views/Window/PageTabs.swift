import SwiftUI

/// CUSTOM: macOS has no page control. Three icons in fixed slots that never
/// move; a `surface` pill slides under the current one, which carries the
/// accent, and the current page's name stands to the left and cross-fades.
/// The pointer brightens the others, and their name appears after a moment.
struct PageTabs: View {
    @Binding var page: Page?

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Page.allCases) { item in
                PageTab(item: item, isCurrent: item == current, pill: pill,
                        // The last tab is near the window edge: its tooltip ends under it.
                        tooltipAlignment: item == Page.allCases.last ? .topTrailing : .top) { page = item }
            }
        }
        .animation(.easeOut(duration: Theme.Motion.page), value: current)
    }

    private var current: Page { page ?? .nowPlaying }
}

struct PageTab: View {
    let item: Page
    let isCurrent: Bool
    let pill: Namespace.ID
    var tooltipAlignment: Alignment = .top
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            Image(systemName: item.symbol)
                .font(Theme.Text.body)
                .foregroundStyle(isCurrent ? Theme.Colors.accentText : hovering ? Theme.Colors.text : Theme.Colors.textMuted)
                .frame(width: Theme.Size.pageTabTarget, height: Theme.Size.pageDotTarget)
                .background {
                    if isCurrent {
                        Capsule()
                            .fill(Theme.Colors.surface)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
        .tooltip(item.title, shortcut: item.shortcutLabel, alignment: tooltipAlignment, shown: hovering && !isCurrent)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// CUSTOM: a name under a control, after the pointer has rested on it for a
/// moment. The system tooltip cannot be told when to appear.
struct Tooltip: ViewModifier {
    let text: String
    /// Shown after the name, muted, as menus show shortcuts.
    let shortcut: String?
    /// Centred under the control, or flush with one of its edges.
    let alignment: Alignment
    let shown: Bool

    @State private var visible = false
    @State private var wait: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if visible {
                    HStack(spacing: Theme.Space.xs) {
                        Text(text)
                            .foregroundStyle(Theme.Colors.text)
                        if let shortcut {
                            Text(shortcut)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                    .font(Theme.Text.caption)
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.vertical, Theme.Space.xxs)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Colors.border))
                    .fixedSize()
                    .offset(y: Theme.Size.pageDotTarget + Theme.Space.xxs)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: visible)
            .onChange(of: shown) { _, isShown in
                wait?.cancel()
                if isShown {
                    wait = Task {
                        try? await Task.sleep(for: .seconds(Theme.Motion.tooltipDelay))
                        if !Task.isCancelled { visible = true }
                    }
                } else {
                    visible = false
                }
            }
    }
}

extension View {
    func tooltip(_ text: String, shortcut: String? = nil, alignment: Alignment = .top, shown: Bool) -> some View {
        modifier(Tooltip(text: text, shortcut: shortcut, alignment: alignment, shown: shown))
    }
}
