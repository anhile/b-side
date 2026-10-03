import SwiftUI

/// The tokens from DESIGN.md. Screens take colours, type, spacing, radii and
/// sizes from here and nowhere else; scripts/check-design.sh enforces it.
///
/// Type, spacing, radii and sizes are multiplied by `scale`: 1 at the
/// Small size, 1.15 at Medium, 1.3 at Large (Settings, Appearance).
/// Colours, opacities, ratios and timings are not.
enum Theme {
    /// Set by WindowSize before the window is built again; see UISize.
    static var scale: CGFloat = UISize.currentScale

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
        /// White on an accent shape: only the chosen Explore search kind, by
        /// the owner's choice (3.0:1, so semibold and never small).
        static let accentOnWhite = Color.white
        static let record = Color("record")
        static let recordGroove = Color("recordGroove")
        /// The one shadow, under large artwork. Black in both themes.
        static let shadow = Color.black
        /// Text and marks on a Vibe tile's gradient, in both themes.
        static let onVibe = Color.white
        /// The progress bar's knob, as the system's sliders have it.
        static let knob = Color.white
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
        /// The window's least size.
        static var window: CGSize { CGSize(width: windowBase.width * scale, height: windowBase.height * scale) }
        /// Where it starts: room for Up Next and a few more rows.
        static var windowStart: CGSize { CGSize(width: 432 * scale, height: 600 * scale) }
        /// The window drags to any size up to twice the least, in either direction.
        static var windowMax: CGSize { CGSize(width: window.width * 2, height: window.height * 2) }
        static let windowBase = CGSize(width: 320, height: 440)
        /// The system's title bar; the bar with the page tabs grows with the
        /// size, the system's does not.
        static let titleBar: CGFloat = 28
        /// From the window's edge to where a title starts, past the three
        /// window buttons.
        static let trafficLights: CGFloat = 76
        static var tabBar: CGFloat { titleBar * scale }
        static var pageDotTarget: CGFloat { (24) * scale }
        static var pageTabTarget: CGFloat { (28) * scale }
        /// The Playlists page's bar under the title bar: one line, the
        /// compact filled button with 6 above and below.
        static var pageBar: CGFloat { (36) * scale }
        /// The line along the bottom of Now Playing with the source and the
        /// output device.
        static var sourceBar: CGFloat { (32) * scale }
        /// Two columns inside the window padding, with one gutter.
        /// A tile's least width: two in the window at its least size. In a
        /// wider window the tiles grow, then a third column comes.
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
        /// A strip at least this wide has Previous and Like as well.
        static var stripWide: CGFloat { (400) * scale }
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
        /// The search field's ring while it has the keyboard.
        static var focusRing: CGFloat { (2) * scale }
        static var volumeGlyph: CGFloat { (20) * scale }
        static var volumeSlider: CGFloat { (120) * scale }
        /// The progress bar: its line, its knob, how tall it is to the
        /// pointer, and the room a time label takes beside it.
        static var progressLine: CGFloat { (4) * scale }
        /// The hairline above Now Playing's bottom line.
        static let hairline: CGFloat = 1
        static var progressKnob: CGSize { CGSize(width: 20 * scale, height: 12 * scale) }
        static var progressTarget: CGFloat { (20) * scale }
        static var progressTick: CGFloat { (2) * scale }
        static var timeLabel: CGFloat { (36) * scale }
        static let settingsWidth: CGFloat = 460
        /// Settings' least height, for a short pane on any screen.
        static let settingsMinHeight: CGFloat = 200
        static var menuWidth: CGFloat { (260) * scale }
        static let logHeight: CGFloat = 200
        static let avatar: CGFloat = 40
        /// The app icon in Settings, General, About; a setting's icon.
        static let aboutIcon: CGFloat = 56
        static let settingIcon: CGFloat = 22
        /// Symbol sizes for the largest and smallest glyphs. Everything else
        /// takes its size from the text style next to it.
        static var emptyGlyph: CGFloat { (28) * scale }
        /// Skeleton rows match the rows they stand for: a `body` title line
        /// and a `caption` line under it, their middles where the text's are.
        static var skeletonLine: CGFloat { (10) * scale }
        static var skeletonCaptionLine: CGFloat { (8) * scale }
        static var skeletonGap: CGFloat { (5.5) * scale }
        static var skeletonTitle: CGFloat { (160) * scale }
        static var skeletonCaption: CGFloat { (120) * scale }
        /// A Vibe tile's large faded symbol and the glow in its light corner.
        static var vibeMark: CGFloat { tileHeight * 0.8 }
        static var vibeGlow: CGFloat { tileHeight * 1.1 }
        static var vibeShadow: CGFloat { (8) * scale }
        /// The colour choices in the Vibe editor.
        static var swatch: CGFloat { (18) * scale }
        static let currentRing: CGFloat = 2
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
        /// The source's colour over the glass of Now Playing's bottom line:
        /// a wash that is this strong under the rule and fades to nothing
        /// at the window's edge, and the rule above it.
        static let sourceWash: Double = 0.14
        static let sourceRule: Double = 0.25
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
        /// The notes drifting behind an empty Explore: barely there.
        static let decoration: Double = 0.12
        /// The progress bar's empty line, in the text colour; its filled part
        /// in a light accent, full under the pointer.
        static let progressTrack: Double = 0.14
        static let progressRest: Double = 0.45
        /// A Vibe tile: its faded symbol, the glow in the light corner, the
        /// shade under its name, the glass edge from top to bottom, the
        /// subtitle, and the coloured shadow under it.
        static let vibeMark: Double = 0.16
        static let vibeGlow: Double = 0.7
        static let vibeShade: Double = 0.22
        static let vibeEdgeTop: Double = 0.45
        static let vibeEdgeBottom: Double = 0.08
        static let vibeSubtitle: Double = 0.8
        static let vibeShadow: Double = 0.35
    }

    enum Motion {
        /// The notes behind an empty Explore: how fast they rise (points per
        /// second), how far they sway, and how many frames a second they take.
        static let notesRise: Double = 9
        static let notesSway: Double = 14
        static let notesFrameRate: Double = 30
        /// A Vibe tile rises a little under the pointer and dips when pressed.
        static let tileHover: Double = 1.03
        static let tilePress: Double = 0.96
        static let feedback: Double = 0.15
        static let tooltipDelay: Double = 1.5
        static let page: Double = 0.3
        /// A tab changes the page at once, and the page fades in.
        static let pageFadeIn: Double = 0.15
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
