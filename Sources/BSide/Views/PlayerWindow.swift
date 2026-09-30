import SwiftUI

/// The main window: page dots, three pages side by side, and the strip with
/// what is playing under the first two.
struct PlayerWindow: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    /// The hidden title bar still counts as a safe area at the top. The
    /// content goes under it, and the window must not grow by its height.
    @State private var topInset = Theme.Size.titleBar

    var body: some View {
        VStack(spacing: 0) {
            PageDots(page: $navigation.page)
                .frame(height: Theme.Size.titleBar)
            pages
            footer
        }
        .background(Theme.Colors.bg)
        .ignoresSafeArea(edges: .top)
        .frame(width: Theme.Size.window.width, height: Theme.Size.window.height - topInset)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .background(WindowSetup())
        .task { player.start() }
    }

    /// A paging scroll view gives the two-finger swipe, and the page follows
    /// the finger, with no custom gesture code.
    private var pages: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Page.allCases) { page in
                    Group {
                        switch page {
                        case .vibe: VibePage()
                        case .playlists: PlaylistsPage()
                        case .nowPlaying: NowPlayingPage()
                        }
                    }
                    .frame(width: Theme.Size.window.width)
                    .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $navigation.page)
        .scrollIndicators(.never)
        .animation(.spring(duration: Theme.Motion.page, bounce: 0), value: navigation.page)
    }

    /// The strip shows on Vibe and Playlists while something plays; Now
    /// Playing is that content already. The gear is on every page.
    private var footer: some View {
        HStack(alignment: .center, spacing: Theme.Space.xs) {
            if let problem = player.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .lineLimit(2)
                    .help(problem)
            } else if player.hasTrack, navigation.page != .nowPlaying {
                NowPlayingStrip { navigation.page = .nowPlaying }
            }
            Spacer(minLength: 0)
            SettingsLink {
                IconButton.Label(symbol: "gearshape")
            }
            .buttonStyle(PressableStyle())
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .frame(height: Theme.Size.stripHeight)
        .padding(.horizontal, Theme.Space.m)
        .padding(.bottom, Theme.Space.xs)
    }
}

/// CUSTOM: macOS has no page control. Each dot is a real button with its own
/// click area, label and keyboard focus.
struct PageDots: View {
    @Binding var page: Page?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Page.allCases) { item in
                Button {
                    page = item
                } label: {
                    Circle()
                        .fill(isCurrent(item) ? Theme.Colors.accent : Theme.Colors.controlBorder)
                        .frame(width: Theme.Size.pageDot, height: Theme.Size.pageDot)
                        .frame(width: Theme.Size.pageDotTarget, height: Theme.Size.pageDotTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isCurrent(item) ? .isSelected : [])
            }
        }
    }

    private func isCurrent(_ item: Page) -> Bool {
        (page ?? .vibe) == item
    }
}

/// Window details SwiftUI does not expose: dragging by the background, since
/// there is no title bar, and the window's own colour behind the content.
private struct WindowSetup: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isMovableByWindowBackground = true
            window?.backgroundColor = NSColor(named: "bg") // tokens-ok
        }
    }

    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ nsView: View, context: Context) {}
}

/// One shape for every "nothing to show" case: signed out, empty, failed.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Image(systemName: symbol)
                .font(.system(size: Theme.Size.emptyGlyph))
                .foregroundStyle(Theme.Colors.textMuted)
            Text(title)
                .font(Theme.Text.title)
                .foregroundStyle(Theme.Colors.text)
            Text(message)
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(OutlineButtonStyle())
                    .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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
            .background(Capsule().strokeBorder(Theme.Colors.controlBorder))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? Theme.Opacity.pressed : isEnabled ? 1 : Theme.Opacity.disabled)
    }
}

struct FilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Text.label)
            .foregroundStyle(Theme.Colors.bg)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.xs)
            .background(Theme.Colors.text, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? Theme.Opacity.pressed : isEnabled ? 1 : Theme.Opacity.disabled)
    }
}

/// What a page shows when the account or the player is not usable yet, or
/// nil when the page can show its own content.
@MainActor
func blockingState(for player: PlayerController) -> EmptyState? {
    if case .failed(let reason) = player.phase {
        return EmptyState(symbol: "exclamationmark.triangle", title: "The player did not start",
                          message: reason, actionTitle: "Try Again") { player.retry() }
    }
    switch player.account {
    case .unknown:
        return nil
    case .signedOut:
        return EmptyState(symbol: "person.crop.circle", title: "Sign in to YouTube Music",
                          message: "B-Side plays the music from your account.",
                          actionTitle: "Sign In…") { player.showSignIn() }
    case .signedIn:
        return nil
    }
}
