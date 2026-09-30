import AppKit
import SwiftUI

/// A colour taken from artwork, for the Now Playing background. The image is
/// averaged at 8 by 8, then pulled into a range that keeps the page's text
/// readable when it is blended over `bg`.
enum ArtworkTint {
    private static var cache: [URL: Color] = [:]

    @MainActor
    static func color(for url: URL?) async -> Color? {
        guard let url else { return nil }
        if let cached = cache[url] { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let averaged = average(cgImage) else { return nil }
        let color = Color(nsColor: tamed(averaged))
        cache[url] = color
        return color
    }

    /// Mean colour of the image at 16 by 16, each pixel weighted by its
    /// saturation, so the cover's colour outweighs its black bars, white
    /// margins and grey shadows.
    private static func average(_ image: CGImage) -> NSColor? {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var sum = (r: 0.0, g: 0.0, b: 0.0, weight: 0.0)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            let saturation = high > 0 ? (high - low) / high : 0
            let weight = 0.05 + saturation * saturation // grey still counts a little, so a grey cover gets grey
            sum.r += r * weight; sum.g += g * weight; sum.b += b * weight; sum.weight += weight
        }
        guard sum.weight > 0 else { return nil }
        return NSColor(red: sum.r / sum.weight, green: sum.g / sum.weight, blue: sum.b / sum.weight, alpha: 1)
    }

    /// Enough colour to be seen, never so dark or so light that text on the
    /// blend fails.
    private static func tamed(_ color: NSColor) -> NSColor {
        guard let c = color.usingColorSpace(.deviceRGB) else { return color }
        let saturation = max(c.saturationComponent, Theme.Tint.minSaturation)
        let brightness = min(max(c.brightnessComponent, Theme.Tint.minBrightness), Theme.Tint.maxBrightness)
        return NSColor(hue: c.hueComponent, saturation: saturation, brightness: brightness, alpha: 1)
    }
}
