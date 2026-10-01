import SwiftUI

/// The control layer from DESIGN.md: page dots, transport, the speaker and
/// the gear float on glass. macOS 26 draws real glass; 14 and 15 draw the
/// system material in the same shape; with Reduce Transparency on, both
/// become `surface` with a `control-border` outline. Controls that sit
/// together share one shape; glass never sits on glass.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.previewReduceTransparency) private var previewReduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency || previewReduceTransparency {
            content
                .background(shape.fill(Theme.Colors.surface))
                .overlay(shape.strokeBorder(Theme.Colors.controlBorder).allowsHitTesting(false))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    func glass<S: InsettableShape>(in shape: S) -> some View {
        modifier(GlassSurface(shape: shape))
    }

    /// For bars from edge to edge that meet another bar: the window's top
    /// bar and the pages' bars under it. Glass lights a rim along every
    /// edge, and two rims where bars meet read as a gap; `joined` names the
    /// edges that meet another bar, which then get no rim.
    func barGlass(joined: Edge.Set = []) -> some View {
        modifier(BarSurface(joined: joined))
    }
}

struct BarSurface: ViewModifier {
    var joined: Edge.Set = []
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.previewReduceTransparency) private var previewReduceTransparency

    /// Past the rim and its glow.
    private static let bleed: CGFloat = 8

    func body(content: Content) -> some View {
        if reduceTransparency || previewReduceTransparency {
            content.background(Theme.Colors.surface)
        } else if #available(macOS 26, *) {
            if joined.isEmpty {
                content.glassEffect(.regular, in: Rectangle())
            } else {
                // The glass runs on past the joined edges and is cut at the
                // bar's frame, which leaves their rims outside. Not one
                // GlassEffectContainer around the window: on macOS 27 it
                // hangs the window when the search field takes focus.
                content
                    .background {
                        Color.clear
                            .glassEffect(.regular, in: Rectangle())
                            .padding(joined, -Self.bleed)
                    }
                    .clipped()
            }
        } else {
            content.background(.regularMaterial)
        }
    }
}

/// Thin scrollers that show only while scrolling, whatever the system's
/// "Show scroll bars" setting: the window is too narrow for the wide kind.
/// Put it in the background of a ScrollView's content.
struct OverlayScrollers: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            enclosingScrollView?.scrollerStyle = .overlay
        }
    }

    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ nsView: View, context: Context) {}
}

/// Snapshots cannot set the system's Reduce Transparency; this stands in.
private struct PreviewReduceTransparencyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var previewReduceTransparency: Bool {
        get { self[PreviewReduceTransparencyKey.self] }
        set { self[PreviewReduceTransparencyKey.self] = newValue }
    }
}

/// Snapshots only: shows the Like and Lyrics overlay on the artwork, which
/// otherwise needs the pointer.
private struct PreviewArtworkHoverKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var previewArtworkHover: Bool {
        get { self[PreviewArtworkHoverKey.self] }
        set { self[PreviewArtworkHoverKey.self] = newValue }
    }
}
