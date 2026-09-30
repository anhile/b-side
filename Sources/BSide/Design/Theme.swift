import SwiftUI

/// The tokens from DESIGN.md. Screens take colours, type, spacing, radii and
/// sizes from here and nowhere else; scripts/check-design.sh enforces it.
enum Theme {
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

    /// Type roles. System text styles, so the user's settings apply.
    enum Text {
        static let display: Font = .largeTitle.weight(.bold)
        static let title: Font = .title3.weight(.semibold)
        static let body: Font = .body
        static let label: Font = .callout.weight(.medium)
        static let caption: Font = .subheadline
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        /// The sleeve: near-square, as a real one.
        static let sleeve: CGFloat = 3
        static let s: CGFloat = 6
        static let m: CGFloat = 12
    }

    enum Size {
        static let window = CGSize(width: 320, height: 440)
        static let titleBar: CGFloat = 28
        static let pageDotTarget: CGFloat = 24
        static let pageTabTarget: CGFloat = 28
        /// Two columns inside the window padding, with one gutter.
        static let tileWidth: CGFloat = (window.width - 2 * Space.m - Space.s) / 2
        static let tileHeight: CGFloat = 96
        static let editorWidth: CGFloat = 300
        static let artworkSmall: CGFloat = 36
        static let artworkStrip: CGFloat = 24
        static let artworkLarge: CGFloat = 160
        /// How far the record shows from behind the large artwork.
        static let recordPeek: CGFloat = 48
        /// Parts of the record as a share of its diameter, so it draws the
        /// same at 36 and at 160.
        static let recordLabelRatio: CGFloat = 0.35
        static let recordHoleRatio: CGFloat = 0.04
        static let recordGrooveStep: CGFloat = 0.045
        static let rowHeight: CGFloat = 44
        static let stripHeight: CGFloat = 44
        static let transportTarget: CGFloat = 32
        static let transportGlyph: CGFloat = 15
        static let playGlyph: CGFloat = 22
        /// Every element of the transport row: the capsule and the circles.
        static let transportBar: CGFloat = 40
        static let volumeGlyph: CGFloat = 20
        static let volumeSlider: CGFloat = 120
        static let settingsWidth: CGFloat = 460
        static let menuWidth: CGFloat = 260
        static let logHeight: CGFloat = 200
        static let avatar: CGFloat = 40
        /// Symbol sizes for the largest and smallest glyphs. Everything else
        /// takes its size from the text style next to it.
        static let emptyGlyph: CGFloat = 28
        static let skeletonLine: CGFloat = 10
        static let skeletonTitle: CGFloat = 160
        static let skeletonCaption: CGFloat = 72
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
        static let artworkRadius: CGFloat = 12
        static let artworkY: CGFloat = 6
        static let artworkOpacity: Double = 0.25
    }

    enum Opacity {
        static let pressed: Double = 0.7
        static let disabled: Double = 0.35
        static let groove: Double = 0.18
        /// The light on the record's surface, which makes its turning visible.
        static let sheen: Double = 0.22
        static let skeletonDim: Double = 0.5
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
