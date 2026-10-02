import AppKit
import SwiftUI

/// SwiftUI's Slider is horizontal only on macOS; AppKit's is vertical when
/// it is taller than wide. Its fill is the accent, fainter the quieter it
/// plays, so the level reads at a glance.
struct VerticalSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isVertical = true
        slider.isContinuous = true
        slider.controlSize = .small
        Self.fill(slider)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        if slider.doubleValue != value { slider.doubleValue = value }
        Self.fill(slider)
    }

    static func fill(_ slider: NSSlider) {
        let span = slider.maxValue - slider.minValue
        let level = span > 0 ? (slider.doubleValue - slider.minValue) / span : 1
        let floor = Theme.Opacity.volumeFloor
        slider.trackFillColor = NSColor(Theme.Colors.accent).withAlphaComponent(floor + (1 - floor) * level) // tokens-ok: the accent token, for AppKit
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: VerticalSlider
        init(_ parent: VerticalSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) {
            parent.value = slider.doubleValue
            VerticalSlider.fill(slider)
        }
    }
}
