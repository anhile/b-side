import SwiftUI

/// Square artwork, loaded at the size it is shown. A picture already
/// loaded (Thumbnails) shows at once; a new one fades in over the
/// placeholder. While the address changes, the placeholder shows, never the
/// previous picture.
struct Artwork: View {
    let url: URL?
    let size: CGFloat
    var radius = Theme.Radius.s
    var placeholder = "music.note"

    @Environment(\.displayScale) private var displayScale
    /// The picture loaded here, and for which address.
    @State private var loaded: (url: URL, image: NSImage)?

    private var source: URL? { url?.withoutBars }
    /// The longer side to decode at: the shown size on this screen.
    private var pixels: Int { Int((size * displayScale).rounded(.up)) }

    private var image: NSImage? {
        guard let source else { return nil }
        if let loaded, loaded.url == source { return loaded.image }
        return Thumbnails.cached(source, pixels: pixels)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Theme.Colors.surface)
                .overlay {
                    Image(systemName: placeholder)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .task(id: source) {
            guard let source, Thumbnails.cached(source, pixels: pixels) == nil else { return }
            guard let image = await Thumbnails.image(for: source, pixels: pixels), !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Theme.Motion.feedback)) { loaded = (source, image) }
        }
        .accessibilityHidden(true)
    }
}
