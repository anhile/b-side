import AppKit
import ServiceManagement

/// Space plays and pauses while the main window is in front, as in other
/// players. Not a menu shortcut: a menu shortcut takes Space from every text
/// field too, in Settings and in the mood editor.
@MainActor
enum SpaceKey {
    private static var monitor: Any?

    static func install(_ action: @escaping () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let space: UInt16 = 49 // kVK_Space
            guard event.keyCode == space,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  let window = NSApp.keyWindow, window === MainWindow.window,
                  !(window.firstResponder is NSText) else { return event }
            action()
            return nil
        }
    }
}
