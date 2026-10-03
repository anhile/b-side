import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
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
    /// Room for a 16:9 video frame as wide as the square.
    private static let wideRoom: CGFloat = 16 / 9
    /// The blur of the backdrop behind a wide frame, as a share of its side.
    private static let backdropBlur: CGFloat = 0.12
    /// A cover inside a wide frame: its edge is a step of this much in
    /// brightness (of 255), in this share of the rows, within this many pixels
    /// of where a square's side would be.
    private static let coverEdgeStep = 10
    private static let coverEdgeRows = 0.4
    private static let coverEdgeSlack = 3
    /// The backdrop is darkened a little, so the frame stands out from it.
    private static let backdropDim: CGFloat = 0.25
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
            // The longer side: a wide video frame is still sharp across the square.
            kCGImageSourceThumbnailMaxPixelSize: Int(Theme.Size.artworkLarge * scale * Self.wideRoom),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(withoutBars).map(squared)
    }

    /// A wide video frame, whole, in a square: the frame across the middle,
    /// and the same frame, enlarged and blurred, behind it. Filling the
    /// square instead cut a fifth off each side, and with it the words many
    /// video thumbnails carry. Covers are square and are left alone.
    private static func squared(_ image: CGImage) -> CGImage {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard width * 5 > height * 6 else { return image }
        if let cover = coverInside(image) { return cover }
        let square = CGRect(x: 0, y: 0, width: width, height: width)
        let grow = width / height
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = CIImage(cgImage: image).clampedToExtent()
        filter.radius = Float(width * backdropBlur / grow)
        let fill = CGAffineTransform(translationX: -(width * grow - width) / 2, y: 0).scaledBy(x: grow, y: grow)
        guard let blurred = filter.outputImage?.transformed(by: fill),
              let backdrop = CIContext().createCGImage(blurred, from: square),
              let context = CGContext(data: nil, width: image.width, height: image.width, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        context.draw(backdrop, in: square)
        context.setFillColor(gray: 0, alpha: backdropDim)
        context.fill(square)
        context.draw(image, in: CGRect(x: 0, y: (width - height) / 2, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// A song's video thumbnail is often its square cover in the middle of a
    /// wide frame, with a colour or a blur on both sides. Then the cover is
    /// the picture: it is cut out. Told by a straight edge running down the
    /// frame where the square's sides would be, on both sides.
    private static func coverInside(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let left = (width - height) / 2, right = left + height
        /// The share of rows with a step in brightness at the column, at its best within a few pixels.
        func edge(at column: Int) -> Double {
            (-coverEdgeSlack...coverEdgeSlack).map { shift -> Double in
                let x = column + shift
                guard x > 0, x < width else { return 0 }
                let rows = (0..<height).filter { abs(Int(pixels[$0 * width + x]) - Int(pixels[$0 * width + x - 1])) >= coverEdgeStep }
                return Double(rows.count) / Double(height)
            }.max() ?? 0
        }
        guard edge(at: left) >= coverEdgeRows, edge(at: right) >= coverEdgeRows else { return nil }
        return image.cropping(to: CGRect(x: left, y: 0, width: height, height: height))
    }

    /// YouTube's 4:3 video thumbnails hold a 16:9 frame between two black
    /// bars. Cut off here, so the bars are not in the square and the tint
    /// is not taken from them. Covers are square and are left alone.
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
                let (data, response) = try await Net.session.data(from: url)
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
