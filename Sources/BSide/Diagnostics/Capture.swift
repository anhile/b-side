import AppKit
import SwiftUI

/// Debug: pictures of the real window as it runs, for looking at the app
/// under a bad network without a screen. `-captureTo <folder>` with
/// `-captureAt 5,20,60` writes every page at those seconds after launch;
/// the window is moved off the screen first. Works with `-proxy`.
/// `-captureWidth 400` resizes the window first, as a drag of its corner
/// does; `-captureWidth "400 end"` also ends the drag, so the layout is
/// made again at that size.
@MainActor
enum Capture {
    private static var scheduled = false

    /// Once: the window's content is built again at a new size, and its
    /// task with it.
    static func schedule(navigation: Navigation) {
        guard let folder = Settings.defaults.string(forKey: Keys.captureTo), !scheduled else { return }
        scheduled = true
        let seconds = (Settings.defaults.string(forKey: Keys.captureAt) ?? "5")
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        Task { @MainActor in
            var passed: Double = 0
            for at in seconds.sorted() {
                try? await Task.sleep(for: .seconds(at - passed))
                passed = at
                await captureAll(navigation: navigation, into: URL(fileURLWithPath: folder), tag: Int(at))
            }
            EventLog.write("capture\tdone")
        }
    }

    private static func captureAll(navigation: Navigation, into folder: URL, tag: Int) async {
        guard let window = MainWindow.window else { return EventLog.write("capture\tno window") }
        if window.frame.origin.x > -1000 {
            window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            window.alphaValue = 1
            window.orderFrontRegardless()
        }
        if let words = Settings.defaults.string(forKey: Keys.captureWidth)?.split(separator: " "), let width = Double(words[0]) {
            var frame = window.frame
            frame.size = CGSize(width: width, height: width / Theme.Size.windowBase.width * Theme.Size.windowBase.height)
            // As a drag of the corner: the window says it starts, resizes, and says it ended.
            WindowSize.dragPlayed = true
            NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: window)
            try? await Task.sleep(for: .seconds(0.2)) // the picture is taken on the next turn
            window.setFrame(frame, display: true)
            try? await Task.sleep(for: .seconds(0.5))
            if words.last == "end" {
                WindowSize.dragPlayed = false
                NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
            }
            try? await Task.sleep(for: .seconds(1))
        }
        let shown = navigation.page
        for page in Page.allCases {
            navigation.page = page
            try? await Task.sleep(for: .seconds(0.5))
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = String(format: "t%03d-%@.png", tag, page.rawValue)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
        }
        navigation.page = shown
        EventLog.write("capture\tat \(tag) s")
    }
}
