import SwiftUI

/// The head of an artist's, album's or playlist's page in the colour of
/// its artwork, as Now Playing is: the colour from the top of the window,
/// under the bar, fading out a little below the header. The colour is the
/// one Now Playing takes from a cover (ArtworkTint).
struct HeaderWash: ViewModifier {
    let url: URL?
    @Environment(\.exploreBarHeight) private var barHeight
    @State private var tint: Color?

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) {
                let colour = tint ?? ArtworkTint.cached(for: url) ?? Theme.Colors.bg
                LinearGradient(colors: [colour.opacity(Theme.Tint.opacity), colour.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    // Up under the bar, and on past the header.
                    .padding(.top, -(barHeight + Theme.Space.xxs))
                    .padding(.bottom, -Theme.Size.headerWashTail)
                    .animation(.easeInOut(duration: Theme.Motion.tintChange), value: tint)
                    .allowsHitTesting(false)
            }
            .task(id: url) { tint = await ArtworkTint.color(for: url) }
    }
}

extension View {
    func headerWash(_ url: URL?) -> some View {
        modifier(HeaderWash(url: url))
    }
}

/// What a page is, small, over its name: "Artist", "Album", "Playlist".
struct PageKind: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Text.caption.weight(.semibold))
            .foregroundStyle(Theme.Colors.textMuted)
            .textCase(.uppercase)
            .tracking(Theme.Size.kindTracking)
    }
}
