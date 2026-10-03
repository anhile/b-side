import SwiftUI

/// A row with a control at its end, over the row so the row's hover spans
/// it, shown only under the pointer. The row that plays has the playing
/// mark in the control's place until the pointer comes.
struct HoverReveal<Content: View, Control: View>: View {
    /// Nil on a row that is not the one playing; else whether it plays now.
    var playing: Bool?
    @ViewBuilder let content: Content
    @ViewBuilder let control: Control

    @State private var hovering = false

    var body: some View {
        content
            .overlay(alignment: .trailing) {
                ZStack {
                    if let playing {
                        PlayingMark(isPlaying: playing)
                            .frame(width: Theme.Size.artworkSmall)
                            .padding(.trailing, Theme.Space.xxs)
                            .opacity(hovering ? 0 : 1)
                    }
                    control
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(hovering)
                }
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
    }
}

/// The speaker on the row that plays, its waves moving while the music
/// does and the page is in view.
struct PlayingMark: View {
    let isPlaying: Bool
    @Environment(\.pageShown) private var pageShown

    var body: some View {
        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
            .symbolEffect(.variableColor.iterative, isActive: isPlaying && pageShown) // tokens-ok: an effect, not a colour
            .font(Theme.Text.body)
            .foregroundStyle(Theme.Colors.accentText)
            .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}

/// A list row that is a button: glass under the pointer, while pressed
/// and while `selected` (the playlist that plays), nothing otherwise. No
/// separators; the 44 rhythm groups them.
struct RowButtonStyle: ButtonStyle {
    var selected = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pointingHand()
            .background(RowGlass(shown: configuration.isPressed || hovering || selected))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
    }
}

/// The shape under a row while the pointer is over it, or while it is the
/// one that plays: glass (since 2026-10-03; before, a flat `surface` fill),
/// as the controls stand on. With Reduce Transparency, `surface` outlined.
struct RowGlass: View {
    let shown: Bool

    var body: some View {
        Color.clear // tokens-ok: the glass is the modifier's
            .glass(in: RoundedRectangle(cornerRadius: Theme.Radius.s))
            .opacity(shown ? 1 : 0)
    }
}

/// The look of RowButtonStyle on a row that is not a Button: glass under
/// it while the pointer is over it, or while it is selected.
struct RowHighlight: ViewModifier {
    var selected = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .pointingHand()
            .background(RowGlass(shown: hovering || selected))
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
                PlayingMark(isPlaying: isPlaying)
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
