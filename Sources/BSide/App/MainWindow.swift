import AppKit
import ServiceManagement

/// The main window, for starting in the menu bar. SwiftUI creates the window
/// at launch either way; a menu-bar start hides it before it is drawn, so the
/// player and the status item start as usual.
@MainActor
enum MainWindow {
    private(set) static weak var window: NSWindow?
    private static var hiddenAtLaunch = false
    /// Nil until AppDelegate has classified the launch.
    private static var launchedInMenuBar: Bool?
    private static var waiting: [(Bool) -> Void] = []
    /// Called whenever the window is shown from the menu bar or on reopen.
    static var onShow: (() -> Void)?

    /// AppDelegate's verdict, once per launch. The player starts before it
    /// (SwiftUI builds the window first) and waits for it.
    static func launched(inMenuBar: Bool) {
        launchedInMenuBar = inMenuBar
        waiting.forEach { $0(inMenuBar) }
        waiting = []
    }

    static func whenLaunched(_ action: @escaping (Bool) -> Void) {
        if let launchedInMenuBar {
            action(launchedInMenuBar)
        } else {
            waiting.append(action)
        }
    }

    /// Called when the window's content is attached to it.
    static func attach(_ window: NSWindow) {
        self.window = window
        if hiddenAtLaunch { hide(window) }
    }

    /// No Dock icon, no window: B-Side lives in the menu bar until shown.
    static func startInMenuBar() {
        hiddenAtLaunch = true
        NSApp.setActivationPolicy(.accessory)
        if let window { hide(window) }
    }

    /// Brings the window and the Dock icon back. False when the window was
    /// closed and SwiftUI has to create it again.
    @discardableResult
    static func show() -> Bool {
        hiddenAtLaunch = false
        onShow?()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return false }
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Transparent at once, so nothing flashes; ordered out once SwiftUI has
    /// finished ordering it front.
    private static func hide(_ window: NSWindow) {
        window.alphaValue = 0
        DispatchQueue.main.async {
            guard hiddenAtLaunch else { return }
            window.orderOut(nil)
        }
    }
}
