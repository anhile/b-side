import SwiftUI

/// The Vibe tiles' colours: each tile a gradient of its own, from a light
/// corner to a deep one where its name sits in white. Decided 2026-10-01
/// (DESIGN.md, Color): the one place with gradients, so the tiles invite a
/// click. Every deep colour holds white text at 4.5:1 or more.
enum VibePalette {
    struct Swatch {
        let name: String
        let light: Color
        let deep: Color
    }

    static let swatches: [Swatch] = [
        Swatch(name: "Ember", light: rgb(0xFF8A3D), deep: rgb(0xC4244C)),
        Swatch(name: "Violet", light: rgb(0x9A8AFF), deep: rgb(0x3A2A9C)),
        Swatch(name: "Lagoon", light: rgb(0x44D3C2), deep: rgb(0x0B5F72)),
        Swatch(name: "Sky", light: rgb(0x62B6FF), deep: rgb(0x1F46C2)),
        Swatch(name: "Moss", light: rgb(0x9AD873), deep: rgb(0x1D6644)),
        Swatch(name: "Rose", light: rgb(0xFFA0B4), deep: rgb(0xA3285A)),
        Swatch(name: "Amber", light: rgb(0xFFCB5C), deep: rgb(0xAE3D0C)),
        Swatch(name: "Plum", light: rgb(0xD685E6), deep: rgb(0x51257D)),
    ]

    /// The user's pick; otherwise Ember for Liked Music, and for the rest a
    /// colour from the tile's id, the same on every launch.
    static func index(for mood: Mood) -> Int {
        if let colour = mood.colour, swatches.indices.contains(colour) { return colour }
        if mood.id == Mood.liked.id { return 0 }
        let sum = mood.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return sum % swatches.count
    }

    static func swatch(for mood: Mood) -> Swatch { swatches[index(for: mood)] }

    private static func rgb(_ hex: Int) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
