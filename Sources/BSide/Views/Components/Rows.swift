import SwiftUI

/// A row with a control at its end, over the row so the row's hover spans
/// it, shown only under the pointer, or always while `pinned` (the playing
/// one keeps its pause button).
struct HoverReveal<Content: View, Control: View>: View {
    var pinned = false
    @ViewBuilder let content: Content
    @ViewBuilder let control: Control

    @State private var hovering = false

    var body: some View {
        content
            .overlay(alignment: .trailing) {
                control
                    .opacity(hovering || pinned ? 1 : 0)
                    .allowsHitTesting(hovering || pinned)
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
    }
}

/// A list row that is a button: `surface` under the pointer and while
/// pressed, nothing otherwise. No separators; the 44 rhythm groups them.
struct RowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pointingHand()
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .fill(Theme.Colors.surface)
                    .opacity(configuration.isPressed || hovering ? 1 : 0)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
    }
}

/// Rows while the list loads: shapes in `surface` where artwork and text will
/// be, breathing slowly. Still with Reduce Motion.
struct SkeletonList: View {
    /// Round artwork, for a list of artists.
    var round = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6) { index in
                HStack(spacing: Theme.Space.xs) {
                    RoundedRectangle(cornerRadius: round ? Theme.Size.artworkSmall / 2 : Theme.Radius.s)
                        .fill(Theme.Colors.surface)
                        .frame(width: Theme.Size.artworkSmall, height: Theme.Size.artworkSmall)
                    VStack(alignment: .leading, spacing: Theme.Size.skeletonGap) {
                        Capsule().fill(Theme.Colors.surface)
                            .frame(width: Theme.Size.skeletonTitle - CGFloat(index % 3) * Theme.Space.l,
                                   height: Theme.Size.skeletonLine)
                        Capsule().fill(Theme.Colors.surface)
                            .frame(width: Theme.Size.skeletonCaption - CGFloat(index % 2) * Theme.Space.l,
                                   height: Theme.Size.skeletonCaptionLine)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.xs)
                .frame(height: Theme.Size.rowHeight)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.xs)
        .opacity(dimmed ? Theme.Opacity.skeletonDim : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Theme.Motion.breathe).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
        .accessibilityLabel("Loading")
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Artwork(url: track.artworkURL, size: Theme.Size.artworkSmall)
            VStack(alignment: .leading, spacing: 0) {
                Text(track.title.isEmpty ? "Untitled" : track.title)
                    .font(Theme.Text.body)
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.text)
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.xs)
            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.accentText)
                    .accessibilityLabel(isPlaying ? "Playing" : "Paused")
            } else if !track.length.isEmpty {
                // As in an album's and a search's rows.
                Text(track.length)
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Theme.Size.rowHeight)
        .contentShape(Rectangle())
    }
}
