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
            content.background(
                shape.fill(Theme.Colors.surface)
                    .overlay(shape.strokeBorder(Theme.Colors.controlBorder))
            )
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
