import AppKit
import SwiftUI

/// AppKit's search field: the magnifier, the clear button and Escape to
/// clear, as everywhere on the Mac. SwiftUI has one only for toolbars.
/// The system's focus ring takes the system accent; this one draws its own
/// in B-Side's orange instead.
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    /// Takes the keyboard each time this changes.
    var focusRequest = 0

    @State private var focused = false

    var body: some View {
        Field(text: $text, prompt: prompt, focused: $focused, focusRequest: focusRequest)
            .overlay {
                Capsule()
                    .stroke(Theme.Colors.accent, lineWidth: Theme.Size.focusRing)
                    .padding(-Theme.Size.focusRing / 2)
                    .opacity(focused ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: focused)
    }

    private struct Field: NSViewRepresentable {
        @Binding var text: String
        let prompt: String
        @Binding var focused: Bool
        let focusRequest: Int

        func makeNSView(context: Context) -> NSSearchField {
            let field = FocusField()
            field.onFocus = { [weak coordinator = context.coordinator] in coordinator?.parent.focused = $0 }
            field.placeholderString = prompt
            field.delegate = context.coordinator
            field.target = context.coordinator
            field.action = #selector(Coordinator.changed(_:)) // also the clear button and Escape
            field.sendsSearchStringImmediately = true
            field.controlSize = Theme.scale > 1 ? .large : .regular
            field.font = .systemFont(ofSize: NSFont.systemFontSize * Theme.scale)
            field.focusRingType = .none // drawn by SearchField, in orange
            return field
        }

        func updateNSView(_ field: NSSearchField, context: Context) {
            context.coordinator.parent = self
            if field.stringValue != text { field.stringValue = text }
            if context.coordinator.handledRequest != focusRequest {
                context.coordinator.handledRequest = focusRequest
                // After this update: the field may not be in its window yet.
                DispatchQueue.main.async {
                    guard let window = field.window, window.firstResponder !== field.currentEditor() else { return }
                    window.makeFirstResponder(field)
                }
            }
        }

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        final class Coordinator: NSObject, NSSearchFieldDelegate {
            var parent: Field
            var handledRequest = 0
            init(_ parent: Field) { self.parent = parent }

            func controlTextDidChange(_ notification: Notification) {
                guard let field = notification.object as? NSSearchField else { return }
                parent.text = field.stringValue
            }

            @objc func changed(_ field: NSSearchField) {
                if parent.text != field.stringValue { parent.text = field.stringValue }
            }
        }
    }

    /// Says when it takes and loses the keyboard. AppKit's "began editing"
    /// comes only with the first key typed, too late for the ring; the
    /// window's first responder changes the moment the field is focused.
    private final class FocusField: NSSearchField {
        var onFocus: ((Bool) -> Void)?
        private var watch: NSKeyValueObservation?
        private var isFocused = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            watch = window?.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
                MainActor.assumeIsolated { self?.update(window.firstResponder) }
            }
        }

        private func update(_ responder: NSResponder?) {
            let focused = responder === self || (responder as? NSText)?.delegate === self
            guard focused != isFocused else { return }
            isFocused = focused
            onFocus?(focused)
        }
    }
}
