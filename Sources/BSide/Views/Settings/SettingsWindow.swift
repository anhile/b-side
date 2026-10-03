import AppKit
import SwiftUI

/// The one Settings window, opened from the app menu (Command-comma) and
/// from the menu bar. Our own window, not SwiftUI's Settings scene: that
/// scene can be opened from AppKit only through a private selector, which
/// stopped working.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(player: PlayerController) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(player))
            let made = NSWindow(contentViewController: hosting)
            made.styleMask = [.titled, .closable, .miniaturizable]
            made.title = "B-Side Settings"
            made.isReleasedWhenClosed = false
            made.center()
            window = made
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
