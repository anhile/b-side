import AppKit

/// The size of everything in the window: Small, Medium or Large (Settings,
/// Appearance), as Theme.scale. The window itself is dragged to any size
/// between Theme.Size.window and Theme.Size.windowMax; its text and
/// controls keep the size set here.
@MainActor
enum WindowSize {
    /// Lays the window out at this scale. Storing it builds the window's
    /// content again (BSideApp); the window grows if it is now too small.
    static func set(_ scale: CGFloat) {
        guard scale != Theme.scale else { return }
        Theme.scale = scale
        Settings.defaults.set(Double(scale), forKey: Keys.uiScale)
        guard let window = MainWindow.window else { return }
        let least = Theme.Size.window
        var frame = window.frame
        guard frame.width < least.width || frame.height < least.height else { return }
        let size = CGSize(width: max(frame.width, least.width), height: max(frame.height, least.height))
        frame.origin.y += frame.height - size.height // the top edge stays
        frame.size = size
        window.setFrame(frame, display: true, animate: true)
    }
}
