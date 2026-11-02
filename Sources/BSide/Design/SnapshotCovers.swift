import SwiftUI

/// Made-up covers for the snapshots: a Vibe colour's gradient with one
/// shape on it, drawn once per run into a temporary folder and handed out
/// as file URLs, so the artwork goes through the same loaders as a real
/// one. One cover per made-up album, so a track shows the same picture on
/// every page; nothing is downloaded.
@MainActor
enum SnapshotCovers {
    enum Shape: String { case sun, band, rings }

    /// "After Midnight" by The Low Hours: Night Drive's album.
    static var afterMidnight: URL? { cover("after-midnight", swatch: 0, shape: .band) }
    static var sideB: URL? { cover("side-b", swatch: 7, shape: .rings) }
    static var marigold: URL? { cover("marigold", swatch: 6, shape: .sun) }
    static var vela: URL? { cover("vela", swatch: 3, shape: .rings) }
    static var juneAvenue: URL? { cover("june-avenue", swatch: 4, shape: .band) }
    static var focus: URL? { cover("focus", swatch: 1, shape: .rings) }
    static var workout: URL? { cover("workout", swatch: 5, shape: .sun) }
    /// The Low Hours' photo, and the account's.
    static var lowHours: URL? { cover("low-hours", swatch: 2, shape: .sun) }
    static var account: URL? { cover("account", swatch: 7, shape: .sun) }

    private static var made: [String: URL] = [:]
    private static let side: CGFloat = 600

    private static func cover(_ name: String, swatch: Int, shape: Shape) -> URL? {
        if let url = made[name] { return url }
        let folder = FileManager.default.temporaryDirectory.appending(path: "b-side-snapshot-covers")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).png")
        let renderer = ImageRenderer(content: Art(swatch: VibePalette.swatches[swatch], shape: shape).frame(width: side, height: side))
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else { return nil }
        made[name] = url
        return url
    }

    private struct Art: View {
        let swatch: VibePalette.Swatch
        let shape: Shape

        var body: some View {
            ZStack {
                LinearGradient(colors: [swatch.light, swatch.deep], startPoint: .topTrailing, endPoint: .bottomLeading)
                switch shape {
                case .sun:
                    Circle()
                        .fill(.white.opacity(0.85))
                        .frame(width: side * 0.42, height: side * 0.42)
                        .offset(x: side * 0.16, y: -side * 0.14)
                case .band:
                    Rectangle()
                        .fill(.black.opacity(0.75))
                        .frame(width: side * 1.6, height: side * 0.24)
                        .rotationEffect(.degrees(-38))
                case .rings:
                    ForEach([0.78, 0.56, 0.34], id: \.self) { ratio in
                        Circle()
                            .stroke(.white.opacity(0.8), lineWidth: side * 0.035)
                            .frame(width: side * ratio, height: side * ratio)
                    }
                }
            }
            .frame(width: side, height: side)
            .clipped()
        }
    }
}
