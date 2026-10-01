import AppKit
import ServiceManagement

/// Open at login, through `SMAppService.mainApp` (macOS 13+). The system's
/// Login Items list is the only record of it; nothing is stored here.
///
/// It exists for the media keys: the system sends Play only to a running
/// app, and with none it starts Apple Music (experiments 1 to 3 in
/// docs/research/default-player.md).
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        EventLog.write("login item\t\(enabled ? "on" : "off"), status \(status.rawValue)")
    }

    /// Whether this launch came from the Login Items. Valid only inside
    /// `applicationDidFinishLaunching`, while the launch Apple event is still
    /// the current one; the check sindresorhus/LaunchAtLogin-Modern uses.
    static func launchedAtLogin() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

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
