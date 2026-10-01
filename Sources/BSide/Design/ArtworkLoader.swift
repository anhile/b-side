import AppKit
import ImageIO

/// Downloads a track's artwork once for everyone who shows it (the sleeve,
/// the tint), retries once when it fails, and keeps the last few images.
/// A failure is logged and answered with nil, so the caller shows its
/// placeholder instead of the previous track's picture.
@MainActor
enum ArtworkLoader {
    private static var images: [URL: CGImage] = [:]
    private static var order: [URL] = []
    private static var loading: [URL: Task<CGImage?, Never>] = [:]
    /// The current, previous and next few tracks.
    private static let keep = 8
    /// Room for a 16:9 video frame shown filling a square.
    private static let wideRoom: CGFloat = 16 / 9

    static func image(for url: URL) async -> CGImage? {
        if let image = images[url] { return image }
        if let running = loading[url] { return await running.value }
        let task = Task { await download(url) }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image {
            images[url] = image
            order.append(url)
            if order.count > keep { images[order.removeFirst()] = nil }
        }
        return image
    }

    /// Decoded near the size it is shown, the large artwork on a Retina
    /// screen, not at the size it comes (often 1200 or more): a fraction of
    /// the memory for each kept picture.
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            // The longer side: a wide video frame still fills the square.
            kCGImageSourceThumbnailMaxPixelSize: Int(Theme.Size.artworkLarge * scale * Self.wideRoom),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func download(_ url: URL) async -> CGImage? {
        var failure = ""
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Tuning.artworkRetryDelay)) }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let image = decode(data) {
                    return image
                }
                failure = "HTTP \(status), \(data.count) bytes"
            } catch {
                failure = error.localizedDescription
            }
        }
        EventLog.write("error\tartwork: \(failure) (\(url.host ?? "?"))")
        return nil
    }
}
