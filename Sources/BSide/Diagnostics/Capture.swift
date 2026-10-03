import AppKit
import SwiftUI

/// Debug: pictures of the real window as it runs, for looking at the app
/// under a bad network without a screen. `-captureTo <folder>` with
/// `-captureAt 5,20,60` writes every page at those seconds after launch;
/// the window is moved off the screen first. Works with `-proxy`.
@MainActor
enum Capture {
    static func schedule(navigation: Navigation) {
        guard let folder = Settings.defaults.string(forKey: Keys.captureTo) else { return }
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
