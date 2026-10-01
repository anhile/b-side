import SwiftUI

/// The tokens from DESIGN.md. Screens take colours, type, spacing, radii and
/// sizes from here and nowhere else; scripts/check-design.sh enforces it.
///
/// Type, spacing, radii and sizes are multiplied by `scale`: 1 for the
/// Compact size, 1.3 for Large (Settings, Appearance). Colours, opacities,
/// ratios and timings are not.
enum Theme {
    /// Set from Settings before the window is built again; see UISize.
    static var scale: CGFloat = UISize.current.scale

    /// Semantic colours. Light and dark values live in the asset catalog
    /// (Assets.xcassets/Colors) and follow the system appearance.
    enum Colors {
        static let bg = Color("bg")
        static let surface = Color("surface")
        static let text = Color("text")
        static let textMuted = Color("textMuted")
        static let border = Color("border")
        static let controlBorder = Color("controlBorder")
        /// Small shapes only: indicator, current dot, progress. Never a fill.
        static let accent = Color("accent")
        /// Orange text and small icons; readable on `bg` in both themes.
        static let accentText = Color("accentText")
        /// What sits on an accent shape.
        static let accentOn = Color("accentOn")
        static let record = Color("record")
        static let recordGroove = Color("recordGroove")
        /// The one shadow, under large artwork. Black in both themes.
        static let shadow = Color.black
        static let danger = Color.red
        static let success = Color.green
    }

    /// Type roles. The macOS text styles' sizes (26, 15, 13, 12, 11), so
    /// Compact looks exactly like the system styles.
    enum Text {
        static var display: Font { .system(size: 26 * scale, weight: .bold) }
        static var title: Font { .system(size: 15 * scale, weight: .semibold) }
        static var body: Font { .system(size: 13 * scale) }
        static var label: Font { .system(size: 12 * scale, weight: .medium) }
        static var caption: Font { .system(size: 11 * scale) }
    }

    enum Space {
        static var xxs: CGFloat { (4) * scale }
        static var xs: CGFloat { (8) * scale }
        static var s: CGFloat { (12) * scale }
        static var m: CGFloat { (16) * scale }
        static var l: CGFloat { (24) * scale }
        static var xl: CGFloat { (32) * scale }
    }

    enum Radius {
        /// The sleeve: near-square, as a real one.
        static var sleeve: CGFloat { (3) * scale }
        static var s: CGFloat { (6) * scale }
        static var m: CGFloat { (12) * scale }
        /// Inside a radius-m panel, 4 in: the corners stay concentric.
        static var nested: CGFloat { m - Space.xxs }
    }

    enum Size {
        static var window: CGSize { CGSize(width: 320 * scale, height: 440 * scale) }
        /// The system's title bar; the bar with the page tabs grows with the
        /// size, the system's does not.
        static let titleBar: CGFloat = 28
        static var tabBar: CGFloat { titleBar * scale }
        static var pageDotTarget: CGFloat { (24) * scale }
        static var pageTabTarget: CGFloat { (28) * scale }
        /// The Playlists page's bar under the title bar: one line, the
        /// compact filled button with 6 above and below.
        static var pageBar: CGFloat { (36) * scale }
        /// Two columns inside the window padding, with one gutter.
        static var tileWidth: CGFloat { (window.width - 2 * Space.m - Space.s) / 2 }
        static var tileHeight: CGFloat { (96) * scale }
        static var editorWidth: CGFloat { (300) * scale }
        static var artworkSmall: CGFloat { (36) * scale }
        /// The strip's artwork fills the panel, 4 in from its edges.
        static var artworkStrip: CGFloat { stripHeight - 2 * Space.xxs }
        static var artworkLarge: CGFloat { (160) * scale }
        /// Explore: an album's or artist's picture on its page, and the
        /// tiles in an artist's rows.
        static var cover: CGFloat { (96) * scale }
        /// How far the record shows from behind the large artwork.
        static var recordPeek: CGFloat { (48) * scale }
        static let recordInSleeve: CGFloat = 0.97   // a 12-inch record in its 12 3/8-inch sleeve
        /// Parts of the record as a share of its diameter, so it draws the
        /// same at 36 and at 160.
        static let recordLabelRatio: CGFloat = 0.35
        static let recordHoleRatio: CGFloat = 0.04
        static let recordGrooveStep: CGFloat = 0.045
        static var rowHeight: CGFloat { (44) * scale }
        static var stripHeight: CGFloat { (44) * scale }
        static var transportTarget: CGFloat { (32) * scale }
        static var transportGlyph: CGFloat { (15) * scale }
        static var playGlyph: CGFloat { (22) * scale }
        /// Pause at 15 has 60% of the ink of Next at 15; at 18 they weigh alike.
        static var stripPlayGlyph: CGFloat { (18) * scale }
        /// Every element of the transport row: the capsule and the circles.
        static var transportBar: CGFloat { (40) * scale }
        /// Like and Lyrics over the album cover.
        static var artworkAction: CGFloat { (48) * scale }
        /// The hover shape stops this short of the button's edge.
        static var hoverInset: CGFloat { (2) * scale }
        static var volumeGlyph: CGFloat { (20) * scale }
        static var volumeSlider: CGFloat { (120) * scale }
        static let settingsWidth: CGFloat = 460
        static var menuWidth: CGFloat { (260) * scale }
        static let logHeight: CGFloat = 200
        static let avatar: CGFloat = 40
        /// Symbol sizes for the largest and smallest glyphs. Everything else
        /// takes its size from the text style next to it.
        static var emptyGlyph: CGFloat { (28) * scale }
        static var skeletonLine: CGFloat { (10) * scale }
        static var skeletonTitle: CGFloat { (160) * scale }
        static var skeletonCaption: CGFloat { (72) * scale }
    }

    /// The artwork colour behind Now Playing: how much of it shows over
    /// `bg`, and the range it is kept in.
    enum Tint {
        static let opacity: Double = 0.38
        static let minSaturation: CGFloat = 0.30
        static let minBrightness: CGFloat = 0.40
        static let maxBrightness: CGFloat = 0.80
    }

    enum Shadow {
        /// The only shadow in the app, under large artwork.
        static var artworkRadius: CGFloat { 12 * scale }
        static var artworkY: CGFloat { 6 * scale }
        static let artworkOpacity: Double = 0.25
    }

    enum Opacity {
        static let pressed: Double = 0.7
        /// The dark veil over the album cover while its actions show.
        static let scrim: Double = 0.45
        /// The hover circle under icon buttons, in the text colour.
        static let hover: Double = 0.08
        static let disabled: Double = 0.35
        static let groove: Double = 0.18
        /// The light on the record's surface, which makes its turning visible.
        static let sheen: Double = 0.22
        static let skeletonDim: Double = 0.5
        /// The volume slider's orange at the lowest volume; it reaches full
        /// strength at 100%.
        static let volumeFloor: Double = 0.3
    }

    enum Motion {
        static let feedback: Double = 0.15
        static let tooltipDelay: Double = 1.5
        static let page: Double = 0.3
        /// Half a cycle of a skeleton's breathing.
        static let breathe: Double = 0.9
        /// One turn of the record; how it stops: the time, how far it runs
        /// on (radians), and how far it rolls back from there.
        static let recordTurn: Double = 4
        static let recordStop: Double = 0.7
        /// The record sliding into or out of the sleeve.
        static let recordSlide: Double = 0.5
        /// The background taking a new track's colour.
        static let tintChange: Double = 0.6
        static let recordOvershoot: Double = 0.18
        static let recordRollback: Double = 0.05
        /// The strip's title, when it does not fit: points per second, the
        /// pause before each pass, and the share of the width that fades at an edge.
        static let marqueeSpeed: Double = 24
        static let marqueePause: Double = 2
        static let marqueeFade: Double = 0.12
    }
}
