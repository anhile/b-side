import SwiftUI

extension View {
    /// The pointing hand over something clickable in the main window: tiles,
    /// rows, segments, buttons, links, the progress bar. macOS 15 and later
    /// set it per view; macOS 14 pushes and pops it on hover.
    @ViewBuilder
    func pointingHand(_ enabled: Bool = true) -> some View {
        if #available(macOS 15, *) {
            pointerStyle(enabled ? .link : nil)
        } else {
            modifier(PushedPointingHand(enabled: enabled))
        }
    }
}

private struct PushedPointingHand: ViewModifier {
    let enabled: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in set(inside && enabled) }
            .onChange(of: enabled) { _, now in if !now { set(false) } }
            // Gone from under the pointer, e.g. when the page changes.
            .onDisappear { set(false) }
    }

    private func set(_ push: Bool) {
        guard push != pushed else { return }
        pushed = push
        push ? NSCursor.pointingHand.push() : NSCursor.pop()
    }
}
