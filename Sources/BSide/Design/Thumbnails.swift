import AppKit
import ImageIO

/// Small artwork for rows, tiles and headers, kept for the whole session.
/// Each picture is downloaded once, decoded at the size it is shown, and
/// handed out at once to every view that asks again: a list that comes
/// again (after a playlist is deleted, a page reopened) redraws with its
/// pictures instead of placeholders. A failed download is tried again,
/// and again on the next ask after a pause, never kept as a failure.
@MainActor
enum Thumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = Tuning.thumbnailCacheBytes
        return cache
    }()
    private static var loading: [String: Task<NSImage?, Never>] = [:]
    /// When a picture last failed, so a list of broken ones is not asked
    /// for on every redraw.
    private static var failedAt: [String: Date] = [:]

    /// The picture, if it is already here.
    static func cached(_ url: URL, pixels: Int) -> NSImage? {
        cache.object(forKey: key(url, pixels) as NSString)
    }

    static func image(for url: URL, pixels: Int) async -> NSImage? {
        let key = key(url, pixels)
        if let image = cache.object(forKey: key as NSString) { return image }
        if let running = loading[key] { return await running.value }
        if let failed = failedAt[key], Date().timeIntervalSince(failed) < Tuning.thumbnailRetryAfter { return nil }
        let task = Task { await download(url, pixels: pixels) }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image {
            failedAt[key] = nil
            cache.setObject(image, forKey: key as NSString, cost: pixels * pixels * 4)
        } else {
            failedAt[key] = Date()
        }
        return image
    }

    /// YouTube signs its thumbnail addresses, and the signature may change
    /// from one listing to the next for the same picture: the path names
    /// the picture, so the query is left out of the key.
    private static func key(_ url: URL, _ pixels: Int) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.host()?.hasSuffix("ytimg.com") == true { parts?.query = nil }
        return "\(pixels) \(parts?.url?.absoluteString ?? url.absoluteString)"
    }

    private static func download(_ url: URL, pixels: Int) async -> NSImage? {
        var failure = ""
        for attempt in 0..<Tuning.thumbnailAttempts {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Tuning.artworkRetryDelay * Double(attempt))) }
            do {
                let (data, response) = try await Net.session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0 // none for a file: the snapshots' covers
                if status == 200 || url.isFileURL, let image = decode(data, pixels: pixels) { return image }
                failure = "HTTP \(status), \(data.count) bytes"
            } catch {
                failure = error.localizedDescription
            }
        }
        EventLog.write("error\tthumbnail: \(failure) (\(url.host ?? "?"))")
        return nil
    }

    private static func decode(_ data: Data, pixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            // The longer side: a wide video frame still fills the square sharply.
            kCGImageSourceThumbnailMaxPixelSize: Int((Double(pixels) * 16 / 9).rounded(.up)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
