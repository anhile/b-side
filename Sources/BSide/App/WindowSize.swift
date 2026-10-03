import AppKit

/// The window's size, from Compact to Large. Everything in the window is
/// laid out from Theme.scale, so a new size means the window built again;
/// while the corner is dragged, the content is scaled as a picture instead,
/// and the real layout follows when the mouse is let go.
@MainActor
enum WindowSize {
    /// What the window's width asks for: its scale, within the range.
    static func scale(forWidth width: CGFloat) -> CGFloat {
        min(max(width / Theme.Size.windowBase.width, Theme.scaleRange.lowerBound), Theme.scaleRange.upperBound)
    }

    /// Lays the window out at this scale, and sizes it to match unless it
    /// already does (the end of a drag). Storing the scale builds the
    /// window's content again (BSideApp).
    static func set(_ wanted: CGFloat) {
        let scale = (min(max(wanted, Theme.scaleRange.lowerBound), Theme.scaleRange.upperBound) * 100).rounded() / 100
        guard scale != Theme.scale else { return }
        Theme.scale = scale
        Settings.defaults.set(Double(scale), forKey: Keys.uiScale)
        guard let window = MainWindow.window else { return }
        let size = Theme.Size.window
        guard abs(window.frame.width - size.width) > 1 else { return }
        var frame = window.frame
        frame.origin.y += frame.height - size.height // the top edge stays
        frame.size = size
        settingFrame = true
        window.setFrame(frame, display: true, animate: true)
        settingFrame = false
    }

    private static var settingFrame = false
    /// Debug: a capture plays a drag of the corner (Capture), which a
    /// window resized by code cannot tell from the zoom button.
    static var dragPlayed = false

    /// The window's content as it is, for stretching while the corner is
    /// dragged.
    static func picture(of window: NSWindow) -> NSImage? {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// The window's size changed: the end of a drag of its corner, or the
    /// zoom button, or Settings. The layout catches up once the size has
    /// settled (not on every step of a drag, and not on our own resize).
    static func resized(_ window: NSWindow) {
        guard !window.inLiveResize, !settingFrame, !dragPlayed, !Settings.isSnapshot else { return }
        set(scale(forWidth: window.frame.width))
    }
}
