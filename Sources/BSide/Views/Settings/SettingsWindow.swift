import AppKit
import SwiftUI

/// The one Settings window, opened from the app menu (Command-comma) and
/// from the menu bar. Our own window with the tabs in its toolbar, as
/// settings windows have them; not SwiftUI's Settings scene, which can be
/// opened from AppKit only through a private selector that stopped working.
@MainActor
final class SettingsWindow: NSObject, NSToolbarDelegate {
    private static var shared: SettingsWindow?

    static func show(player: PlayerController) {
        let window = shared ?? SettingsWindow(player: player)
        shared = window
        NSApp.activate(ignoringOtherApps: true)
        window.window.makeKeyAndOrderFront(nil)
    }

    /// A window of its own on one tab, for the snapshots.
    static func make(player: PlayerController, tab: SettingsView.Tab) -> (window: NSWindow, keep: AnyObject) {
        let made = SettingsWindow(player: player)
        made.show(tab)
        return (made.window, made)
    }

    let window: NSWindow
    private let player: PlayerController
    private var tab: SettingsView.Tab = .general

    private init(player: PlayerController) {
        self.player = player
        window = NSWindow(contentViewController: Self.pane(.general, player: player))
        super.init()
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "B-Side Settings"
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: "settings")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = Self.identifier(tab)
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        fit(keepingTop: false)
        window.center()
    }

    private static func identifier(_ tab: SettingsView.Tab) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(tab.rawValue)
    }

    @objc private func choose(_ item: NSToolbarItem) {
        if let tab = SettingsView.Tab(rawValue: item.itemIdentifier.rawValue) { show(tab) }
    }

    private func show(_ tab: SettingsView.Tab) {
        guard tab != self.tab else { return }
        self.tab = tab
        window.toolbar?.selectedItemIdentifier = Self.identifier(tab)
        window.contentViewController = Self.pane(tab, player: player)
        fit(keepingTop: true)
    }

    /// The pane decides nothing about the window: with any sizing option
    /// the hosting view's constraints resize the window during layout, and
    /// where the pane is taller than the screen (a laptop's), AppKit fits
    /// the window back to the screen, SwiftUI grows it again, and AppKit
    /// throws (crash, 2026-10-04). The window is sized here instead.
    private static func pane(_ tab: SettingsView.Tab, player: PlayerController) -> NSHostingController<AnyView> {
        let hosting = NSHostingController(rootView: AnyView(SettingsView(tab: tab).environmentObject(player)))
        // Measured once, before the window has it: the pane's ideal size.
        hosting.sizingOptions = .preferredContentSize
        hosting.view.layoutSubtreeIfNeeded()
        ideal[ObjectIdentifier(hosting)] = hosting.preferredContentSize.height
        hosting.sizingOptions = []
        return hosting
    }

    private static var ideal: [ObjectIdentifier: CGFloat] = [:]

    /// The pane's own height, no taller than the screen leaves room for;
    /// a taller pane scrolls. The top edge stays where it was on a tab change.
    private func fit(keepingTop: Bool) {
        guard let hosting = window.contentViewController as? NSHostingController<AnyView>,
              let wanted = Self.ideal.removeValue(forKey: ObjectIdentifier(hosting)), wanted > 0 else { return }
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? wanted
        let chrome = window.frame.height - window.contentLayoutRect.height
        let height = max(min(wanted, screen - chrome - Theme.Space.xl), Theme.Size.settingsMinHeight)
        let size = CGSize(width: Theme.Size.settingsWidth, height: height)
        guard keepingTop else { return window.setContentSize(size) }
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsView.Tab.allCases.map(Self.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        guard let tab = SettingsView.Tab(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(choose(_:))
        return item
    }
}
