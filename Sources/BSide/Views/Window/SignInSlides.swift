import SwiftUI

/// What the sign-in screen shows in turn, as the website does: the account
/// first, then the app's parts, each with a picture drawn from the app's
/// own pieces (Vibe colours, the record, rows, the menu).
enum SignInSlide: Int, CaseIterable, Identifiable {
    case music, vibes, nowPlaying, lyrics, explore, menuBar

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .music: "Your music"
        case .vibes: "Vibes"
        case .nowPlaying: "Now Playing"
        case .lyrics: "Lyrics"
        case .explore: "Explore"
        case .menuBar: "Out of the way"
        }
    }

    var text: String {
        switch self {
        case .music: "Your playlists, likes and mixes\nfrom YouTube\u{00A0}Music, in one small player."
        case .vibes: "One click for a mood: your moods\nas tiles, each in a colour of its own."
        case .nowPlaying: "The record turns while it plays,\nand slides into its sleeve on pause."
        case .lyrics: "Lyrics that follow the song.\nClick a line to play from there."
        case .explore: "All of YouTube\u{00A0}Music, one search away.\nWorks without an account too."
        case .menuBar: "Close the window, the music plays on.\nThe record waits in the menu bar."
        }
    }

    var next: SignInSlide { Self(rawValue: (rawValue + 1) % Self.allCases.count) ?? .music }
}

/// The picture of one slide, centred on the stage.
struct SignInSlideStage: View {
    let slide: SignInSlide

    var body: some View {
        Group {
            switch slide {
            case .music: RecordWithSleeves()
            case .vibes: VibesPicture()
            case .nowPlaying: NowPlayingPicture()
            case .lyrics: LyricsPicture()
            case .explore: ExplorePicture()
            case .menuBar: MenuBarPicture()
            }
        }
        .accessibilityHidden(true)
    }
}

private func gradient(_ colour: Int) -> LinearGradient {
    let swatch = VibePalette.swatches[colour]
    return LinearGradient(colors: [swatch.light, swatch.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Four tiles, as on the Vibe page.
private struct VibesPicture: View {
    private let tiles: [(colour: Int, name: String, symbol: String)] = [
        (0, "Liked Music", "heart.fill"), (3, "Focus", "scope"),
        (1, "Night drive", "moon.stars.fill"), (6, "Sunday", "sun.max.fill"),
    ]

    var body: some View {
        let size = Theme.Size.slideTile
        VStack(spacing: Theme.Space.xs) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: Theme.Space.xs) {
                    ForEach(tiles[(row * 2)..<(row * 2 + 2)], id: \.name) { tile in
                        RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                            .fill(gradient(tile.colour))
                            .overlay(alignment: .bottomLeading) {
                                Text(tile.name)
                                    .font(Theme.Text.label)
                                    .foregroundStyle(Theme.Colors.onVibe)
                                    .padding(Theme.Space.s)
                            }
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: tile.symbol)
                                    .font(Theme.Text.caption)
                                    .foregroundStyle(Theme.Colors.onVibe)
                                    .padding(Theme.Space.s)
                            }
                            .frame(width: size.width, height: size.height)
                            .shadow(color: VibePalette.swatches[tile.colour].deep.opacity(Theme.Opacity.vibeShadow),
                                    radius: Theme.Space.xs, y: Theme.Space.xxs)
                    }
                }
            }
        }
    }
}

/// A sleeve with the record half out of it, turning.
private struct NowPlayingPicture: View {
    var body: some View {
        let size = Theme.Size.slideSleeve
        ZStack {
            Record(size: size * Theme.Size.recordInSleeve, spinning: true)
                .offset(x: size * 0.3)
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(gradient(2))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: Theme.Size.slideGlyph, weight: .semibold))
                        .foregroundStyle(Theme.Colors.onVibe.opacity(Theme.Opacity.slideGlyph))
                }
                .frame(width: size, height: size)
                .shadow(color: Theme.Colors.shadow.opacity(Theme.Opacity.signInShadow), radius: Theme.Space.s, y: Theme.Space.xxs)
                .offset(x: -size * 0.15)
        }
    }
}

/// Lines of a song, the one being sung bright, moving on by itself.
private struct LyricsPicture: View {
    private let lines = ["Porch light on, the kettle warm", "Rain keeps time on the glass",
                         "Every record knows my name", "Turn it over, play it twice",
                         "Side B sounds like home"]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: Theme.Motion.slideLyricLine)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / Theme.Motion.slideLyricLine)
            let current = reduceMotion ? 2 : tick % lines.count
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index])
                        // The same size sung or not, so a line never runs out of room.
                        .font(index == current ? Theme.Text.body.weight(.semibold) : Theme.Text.body)
                        .foregroundStyle(index == current ? Theme.Colors.text : Theme.Colors.textMuted)
                        .opacity(index == current ? 1 : Theme.Opacity.slideLyric)
                        .lineLimit(1)
                }
            }
            .animation(.easeInOut(duration: Theme.Motion.page), value: current)
            .padding(Theme.Space.m)
            .frame(width: Theme.Size.slideWidth, alignment: .leading)
            .background(VibePalette.swatches[5].light.opacity(Theme.Opacity.signInWash),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
        }
    }
}

/// The search field and three results.
private struct ExplorePicture: View {
    private let results: [(colour: Int, title: String, kind: String, round: Bool)] = [
        (7, "Late Coffee", "Song · Marlow Trio", false),
        (4, "Rainy Window", "Album · June Harbor", false),
        (3, "Marlow Trio", "Artist", true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.textMuted)
                Text("slow jazz")
                    .foregroundStyle(Theme.Colors.text)
                Spacer(minLength: 0)
            }
            .font(Theme.Text.body)
            .padding(.horizontal, Theme.Space.s)
            .frame(height: Theme.Size.pageTabTarget)
            .background(Theme.Colors.surface, in: Capsule())
            .overlay(Capsule(style: .circular).strokeBorder(Theme.Colors.controlBorder))
            ForEach(results, id: \.title) { result in
                HStack(spacing: Theme.Space.s) {
                    Group {
                        if result.round {
                            Circle().fill(gradient(result.colour))
                        } else {
                            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous).fill(gradient(result.colour))
                        }
                    }
                    .frame(width: Theme.Size.artworkSmall, height: Theme.Size.artworkSmall)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(result.title)
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.text)
                        Text(result.kind)
                            .font(Theme.Text.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                }
            }
        }
        .frame(width: Theme.Size.slideWidth, alignment: .leading)
    }
}

/// The menu bar with the record in it, and its menu open under it.
private struct MenuBarPicture: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
            HStack(spacing: Theme.Space.s) {
                Spacer(minLength: 0)
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Image(systemName: Page.nowPlaying.symbol) // the app's icon in the menu bar
                Text("9:41")
            }
            .font(Theme.Text.caption)
            .foregroundStyle(Theme.Colors.text)
            .padding(.horizontal, Theme.Space.s)
            .frame(width: Theme.Size.slideWidth, height: Theme.Size.slideMenuBar)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.xs) {
                    RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                        .fill(gradient(7))
                        .frame(width: Theme.Size.artworkSmall, height: Theme.Size.artworkSmall)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Late Coffee").font(Theme.Text.label).foregroundStyle(Theme.Colors.text)
                        Text("Marlow Trio").font(Theme.Text.caption).foregroundStyle(Theme.Colors.textMuted)
                    }
                }
                HStack(spacing: Theme.Space.l) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "pause.fill")
                    Image(systemName: "forward.fill")
                }
                .font(Theme.Text.body)
                .foregroundStyle(Theme.Colors.text)
                .frame(maxWidth: .infinity)
                ForEach(["Vibes", "Playlists"], id: \.self) { item in
                    HStack {
                        Text(item)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                    }
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.text)
                }
            }
            .padding(Theme.Space.s)
            .frame(width: Theme.Size.slideMenu)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(Theme.Colors.border))
            .shadow(color: Theme.Colors.shadow.opacity(Theme.Opacity.signInShadow), radius: Theme.Space.s, y: Theme.Space.xxs)
        }
    }
}
