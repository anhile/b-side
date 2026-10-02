import SwiftUI

/// Square artwork, loaded at the size it is shown.
struct Artwork: View {
    let url: URL?
    let size: CGFloat
    var radius = Theme.Radius.s
    var placeholder = "music.note"

    var body: some View {
        AsyncImage(url: url?.withoutBars) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Theme.Colors.surface)
                .overlay {
                    Image(systemName: placeholder)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .accessibilityHidden(true)
    }
}
