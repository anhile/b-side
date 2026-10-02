import SwiftUI

/// A mood: a gradient of its own colour (VibePalette), the name and what it
/// plays in white in the deep corner, the kind of source in the other, and
/// the same symbol large and faded, half off the edge. A glass edge on top.
/// The playing tile has a white ring and a pulsing speaker.
struct MoodTile: View {
    let mood: Mood
    let subtitle: String
    let isCurrent: Bool
    let isPlaying: Bool
    @Environment(\.pageShown) private var pageShown
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.m) }

    var body: some View {
        let swatch = VibePalette.swatch(for: mood)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack {
                Spacer()
                Group {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .symbolEffect(.variableColor.iterative, isActive: isPlaying && pageShown) // tokens-ok: an effect, not a colour
                            .accessibilityLabel(isPlaying ? "Playing" : "Paused")
                    } else {
                        Image(systemName: mood.symbol)
                            .accessibilityHidden(true)
                    }
                }
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.onVibe)
            }
            Spacer(minLength: 0)
            Text(mood.name)
                .font(Theme.Text.title)
                .foregroundStyle(Theme.Colors.onVibe)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.onVibe.opacity(Theme.Opacity.vibeSubtitle))
                .lineLimit(1)
        }
        .padding(Theme.Space.s)
        .frame(width: Theme.Size.tileWidth, height: Theme.Size.tileHeight, alignment: .bottomLeading)
        .background { background(swatch) }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [Theme.Colors.onVibe.opacity(Theme.Opacity.vibeEdgeTop),
                                                       Theme.Colors.onVibe.opacity(Theme.Opacity.vibeEdgeBottom)],
                                              startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            // The playing tile's ring, in its own colour, a little outside
            // it: the deep shade on the light page, the light one on the dark.
            RoundedRectangle(cornerRadius: Theme.Radius.m + Theme.Size.currentRing * 1.5)
                .strokeBorder(colorScheme == .dark ? swatch.light : swatch.deep, lineWidth: Theme.Size.currentRing)
                .padding(-Theme.Size.currentRing * 1.5)
                .opacity(isCurrent ? 1 : 0)
        }
        .shadow(color: swatch.deep.opacity(Theme.Opacity.vibeShadow), radius: Theme.Size.vibeShadow,
                y: Theme.Size.vibeShadow / 2)
        .contentShape(shape)
    }

    /// Light corner top right, deep corner bottom left under the name, a
    /// glow in the light corner, the faded symbol, and a shade under the text.
    private func background(_ swatch: VibePalette.Swatch) -> some View {
        ZStack {
            LinearGradient(colors: [swatch.light, swatch.deep], startPoint: .topTrailing, endPoint: .bottomLeading)
            Circle()
                .fill(swatch.light)
                .frame(width: Theme.Size.vibeGlow, height: Theme.Size.vibeGlow)
                .blur(radius: Theme.Size.vibeGlow / 3)
                .opacity(Theme.Opacity.vibeGlow)
                .offset(x: Theme.Size.vibeGlow / 2, y: -Theme.Size.vibeGlow / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            Image(systemName: mood.symbol)
                .font(.system(size: Theme.Size.vibeMark))
                .foregroundStyle(Theme.Colors.onVibe.opacity(Theme.Opacity.vibeMark))
                .rotationEffect(.degrees(-14))
                .offset(x: Theme.Size.vibeMark / 4, y: Theme.Size.vibeMark / 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            LinearGradient(colors: [.clear, Theme.Colors.shadow.opacity(Theme.Opacity.vibeShade)],
                           startPoint: .center, endPoint: .bottom)
        }
    }
}

/// The last tile: a plus in a dashed outline. When it is the only tile it
/// says what to do.
struct AddTile: View {
    let isFirst: Bool

    var body: some View {
        VStack(spacing: Theme.Space.xxs) {
            Image(systemName: "plus")
                .font(Theme.Text.title)
                .foregroundStyle(Theme.Colors.textMuted)
            if isFirst {
                Text("Add a vibe")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .frame(width: Theme.Size.tileWidth, height: Theme.Size.tileHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .strokeBorder(Theme.Colors.border, style: StrokeStyle(lineWidth: 1, dash: [Theme.Space.xxs]))
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
    }
}

/// A tile that is not a button rises under the pointer the same way.
struct TileLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(!reduceMotion && hovering ? Theme.Motion.tileHover : 1)
            .onHover { hovering = $0 }
            .pointingHand()
            .animation(.snappy(duration: Theme.Motion.feedback * 2), value: hovering)
    }
}

/// Tiles rise a little under the pointer and dip when pressed, on a spring.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Lifted(configuration: configuration)
    }

    private struct Lifted: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? Theme.Motion.tilePress
                             : hovering ? Theme.Motion.tileHover : 1)
                .opacity(reduceMotion && configuration.isPressed ? Theme.Opacity.pressed : 1)
                .onHover { hovering = $0 }
                .pointingHand(isEnabled)
                .animation(.snappy(duration: Theme.Motion.feedback * 2), value: hovering)
                .animation(.snappy(duration: Theme.Motion.feedback), value: configuration.isPressed)
        }
    }
}
