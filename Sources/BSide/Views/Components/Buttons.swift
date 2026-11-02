import SwiftUI
import AppKit

/// A quiet icon button in `text-muted` at text size, for secondary actions
/// such as refresh and settings.
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(symbol: symbol)
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
        .help(label)
        .accessibilityLabel(label)
    }

    struct Label: View {
        let symbol: String

        var body: some View {
            Image(systemName: symbol)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.Colors.textMuted)
                .frame(width: Theme.Size.pageDotTarget, height: Theme.Size.pageDotTarget)
                .contentShape(Rectangle())
        }
    }
}

/// The app's text button: a capsule outline in `control-border`, label in
/// `text`. One primary (filled) button per screen is `FilledButtonStyle`.
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Text.label)
            .foregroundStyle(Theme.Colors.text)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.xs)
            // A continuous capsule's outline draws stray ticks at its ends
            // on macOS 27; the circular one does not.
            .background(Capsule(style: .circular).strokeBorder(Theme.Colors.controlBorder))
            .contentShape(Capsule())
            .pointingHand(isEnabled)
            .opacity(configuration.isPressed ? Theme.Opacity.pressed : isEnabled ? 1 : Theme.Opacity.disabled)
    }
}

struct FilledButtonStyle: ButtonStyle {
    /// For a bar: the height of the small icon buttons, a smaller glyph.
    var compact = false
    /// The one way forward on a screen of its own (signing in): wider and
    /// taller, the label in body size.
    var prominent = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(prominent ? Theme.Text.body.weight(.semibold) : Theme.Text.label)
            .imageScale(compact ? .small : .medium)
            .foregroundStyle(Theme.Colors.bg)
            .frame(minWidth: prominent ? Theme.Size.prominentButton - 2 * Theme.Space.m : nil)
            .padding(.horizontal, compact ? Theme.Space.s : Theme.Space.m)
            .padding(.vertical, compact ? 0 : prominent ? Theme.Space.s : Theme.Space.xs)
            .frame(height: compact ? Theme.Size.pageDotTarget : nil)
            .background(Theme.Colors.text, in: Capsule())
            .contentShape(Capsule())
            .pointingHand(isEnabled)
            .opacity(configuration.isPressed ? Theme.Opacity.pressed : isEnabled ? 1 : Theme.Opacity.disabled)
    }
}

/// A text button with no shape: caption in `text-muted`, `text` under the
/// pointer. For a second, quieter choice next to a real button.
struct QuietButtonStyle: ButtonStyle {
    var font = Theme.Text.caption

    func makeBody(configuration: Configuration) -> some View {
        QuietLabel(configuration: configuration, font: font)
    }

    private struct QuietLabel: View {
        let configuration: Configuration
        let font: Font
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(font)
                .foregroundStyle(hovering ? Theme.Colors.text : Theme.Colors.textMuted)
                .padding(.vertical, Theme.Space.xxs)
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? Theme.Opacity.pressed : 1)
                .onHover { hovering = $0 }
                .pointingHand()
                .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
        }
    }
}

/// An icon-only button in `text`, with a square click target.
struct TransportButton: View {
    let symbol: String
    let label: String
    var glyph: CGFloat = Theme.Size.transportGlyph
    /// The round glass buttons pass their full size, so the hover fills them.
    var target: CGFloat = Theme.Size.transportTarget
    var color: Color = Theme.Colors.text
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: target, height: target)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Feedback for icon buttons, as if they were keys. Under the pointer a
/// light capsule rises behind the glyph, with a soft shadow; pressed, the
/// capsule sinks into a shade of the text colour and the glyph squeezes,
/// then springs back on release. It fills the button's frame: a circle on
/// square buttons and the round glass ones, the shape of the page pill on
/// the page tabs. With Reduce Motion the glyph stays still and dims.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration)
    }

    private struct HoverLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        private var pressed: Bool { configuration.isPressed && isEnabled }

        var body: some View {
            configuration.label
                .scaleEffect(pressed && !reduceMotion ? Theme.Motion.buttonPress : 1)
                .opacity(pressed && reduceMotion ? Theme.Opacity.pressed : 1)
                .background {
                    Capsule()
                        .fill(pressed ? Theme.Colors.text.opacity(Theme.Opacity.buttonSunk)
                                      : Theme.Colors.knob.opacity(colorScheme == .dark ? Theme.Opacity.buttonRaisedDark
                                                                                      : Theme.Opacity.buttonRaised))
                        .shadow(color: Theme.Colors.shadow.opacity(pressed ? 0 : Theme.Opacity.buttonShadow),
                                radius: Theme.Size.buttonShadow, y: Theme.Size.buttonShadow / 2)
                        .padding(Theme.Size.hoverInset)
                        .opacity((hovering || pressed) && isEnabled ? 1 : 0)
                }
                .onHover { hovering = $0 }
                .pointingHand(isEnabled)
                .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
                // Down at once, back with a small overshoot.
                .animation(pressed ? .easeOut(duration: Theme.Motion.buttonDown)
                                   : .spring(response: Theme.Motion.buttonSpring, dampingFraction: Theme.Motion.buttonBounce),
                           value: pressed)
        }
    }
}

/// Text that opens a page: muted like the text around it, underlined and in
/// `text` under the pointer, with the pointing hand.
struct LinkText: View {
    let text: String
    var font = Theme.Text.body
    @State private var hovering = false

    var body: some View {
        Text(text)
            .font(font)
            .underline(hovering)
            .foregroundStyle(hovering ? Theme.Colors.text : Theme.Colors.textMuted)
            .lineLimit(1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .pointingHand()
    }
}
