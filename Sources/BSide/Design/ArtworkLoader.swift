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
    /// A bar's grey is under this, of 255; JPEG noise keeps it off zero.
    private static let barLevel: UInt8 = 24
    /// Rows where the bar runs into the picture.
    private static let barBleed = 2

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
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(withoutBars)
    }

    /// YouTube's 4:3 video thumbnails hold a 16:9 frame between two black
    /// bars. Cut off here, so the frame fills the square and the tint is
    /// not taken from the bars. Covers are square and are left alone.
    private static func withoutBars(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        guard width * 5 > height * 6 else { return image }
        let columns = 32
        var pixels = [UInt8](repeating: 0, count: columns * height)
        guard let context = CGContext(data: &pixels, width: columns, height: height, bitsPerComponent: 8,
                                      bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: height))
        func isBar(_ row: Int) -> Bool {
            pixels[row * columns..<(row + 1) * columns].allSatisfy { $0 < barLevel }
        }
        var top = 0, bottom = 0
        while top < height / 3, isBar(top) { top += 1 }
        while bottom < height / 3, isBar(height - 1 - bottom) { bottom += 1 }
        // Bars come in pairs; one dark edge is the picture itself.
        let bar = min(top, bottom)
        guard bar * 20 >= height else { return image }
        let cut = bar + barBleed
        return image.cropping(to: CGRect(x: 0, y: cut, width: width, height: height - cut * 2)) ?? image
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

extension URL {
    /// For small artwork. YouTube's 4:3 video thumbnails have black bars
    /// above and below; `mqdefault` is the same frame without them, 320
    /// wide, and there is one for every video.
    var withoutBars: URL {
        let barred: Set = ["default", "hqdefault", "sddefault"]
        guard host()?.hasSuffix("ytimg.com") == true, barred.contains(deletingPathExtension().lastPathComponent),
              var parts = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        parts.path = deletingLastPathComponent().appending(path: "mqdefault.\(pathExtension)").path()
        parts.query = nil
        return parts.url ?? self
    }
}
