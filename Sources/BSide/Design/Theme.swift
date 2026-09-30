import SwiftUI

/// Layout tokens from DESIGN.md. Screens take spacing, radii and sizes from
/// here and nowhere else.
///
/// Colours and type roles are added with the design pass. Until then screens
/// use the system's colours and text styles.
enum Theme {
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 12
    }

    enum Size {
        static let window = CGSize(width: 320, height: 440)
        static let titleBar: CGFloat = 28
        static let pageDot: CGFloat = 6
        static let pageDotTarget: CGFloat = 24
        static let heroButton: CGFloat = 96
        static let heroGlyph: CGFloat = 36
        static let artworkSmall: CGFloat = 36
        static let volumeWidth: CGFloat = 88
        static let volumeGlyph: CGFloat = 16
        static let artworkNowPlaying: CGFloat = 48
        static let rowHeight: CGFloat = 44
        static let settingsWidth: CGFloat = 460
        static let logHeight: CGFloat = 160
    }

    enum Opacity {
        static let pressed: Double = 0.7
    }

    enum Motion {
        static let page: Double = 0.3
    }
}
