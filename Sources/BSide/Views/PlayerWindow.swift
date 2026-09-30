import SwiftUI

/// The main window: page dots, three pages side by side, and the strip with
/// what is playing under the first two.
struct PlayerWindow: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    /// The hidden title bar still counts as a safe area at the top. The
    /// content goes under it, and the window must not grow by its height.
    @State private var topInset = Theme.Size.titleBar
    /// The artwork's colour, over the whole window while Now Playing shows.
    @State private var tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // A glass bar the height of the title bar: traffic lights on the
            // left, the page icons on the right, the window dragged by the rest.
            DragHandle()
                .overlay(alignment: .trailing) {
                    PageTabs(page: $navigation.page)
                        .padding(.trailing, Theme.Space.xs)
                }
                .frame(height: topInset)
                .glass(in: Rectangle())
            pages
            footer
                .padding(.bottom, Theme.Space.xs)
        }
        .background(tintLayer)
        .background(Theme.Colors.bg)
        .ignoresSafeArea(edges: .top)
        .frame(width: Theme.Size.window.width, height: Theme.Size.window.height - topInset)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .background(WindowSetup())
        .task {
            player.start()
            StatusMenu.shared.install(player: player) { openWindow(id: "main") }
        }
        .task(id: player.state.artworkURL) {
            tint = player.hasTrack ? await ArtworkTint.color(for: player.state.artworkURL) : nil
        }
    }

    private var tintLayer: some View {
        let showing = tint != nil && (navigation.page ?? .nowPlaying) == .nowPlaying
        return (tint ?? Theme.Colors.bg)
            .opacity(showing ? Theme.Tint.opacity : 0)
            .animation(.easeInOut(duration: Theme.Motion.tintChange), value: tint)
            .animation(.easeInOut(duration: Theme.Motion.tintChange), value: navigation.page)
    }

    @ViewBuilder
    private var pages: some View {
        if reduceMotion {
            // Nothing slides: the current page fades in over the previous
            // one. Dots and Command-1, 2, 3 change pages; the swipe does not.
            ZStack {
                page(navigation.page ?? .nowPlaying)
                    .id(navigation.page ?? .nowPlaying)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: Theme.Motion.page), value: navigation.page)
        } else {
            pager
        }
    }

    /// A paging scroll view gives the two-finger swipe, and the page follows
    /// the finger, with no custom gesture code.
    private var pager: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Page.allCases) { item in
                    page(item)
                        .frame(width: Theme.Size.window.width)
                        .id(item)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $navigation.page)
        .scrollIndicators(.never)
        .animation(.spring(duration: Theme.Motion.page, bounce: 0), value: navigation.page)
    }

    @ViewBuilder
    private func page(_ page: Page) -> some View {
        switch page {
        case .vibe: VibePage()
        case .playlists: PlaylistsPage()
        case .nowPlaying: NowPlayingPage()
        }
    }

    /// The strip shows on Vibe and Playlists while something plays; Now
    /// Playing is that content already. Its place is kept on every page so
    /// nothing moves between them. Settings live in the menu bar and under
    /// Command-comma.
    private var footer: some View {
        HStack(alignment: .center, spacing: Theme.Space.xs) {
            if let problem = player.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .lineLimit(2)
                    .help(problem)
                Spacer(minLength: 0)
            } else if player.hasTrack, navigation.page != .nowPlaying {
                NowPlayingStrip { navigation.page = .nowPlaying }
            }
        }
        .frame(height: Theme.Size.stripHeight)
        .padding(.horizontal, Theme.Space.m)
    }
}

/// CUSTOM: macOS has no page control. Three icons in fixed slots that never
/// move; a `surface` pill slides under the current one, which carries the
/// accent, and the current page's name stands to the left and cross-fades.
/// The pointer brightens the others, and their name appears after a moment.
struct PageTabs: View {
    @Binding var page: Page?

    @Namespace private var pill

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Text(current.title)
                .font(Theme.Text.label)
                .foregroundStyle(Theme.Colors.accentText)
                .fixedSize()
                .id(current)
                .transition(.opacity)
            HStack(spacing: 0) {
                ForEach(Page.allCases) { item in
                    PageTab(item: item, isCurrent: item == current, pill: pill) { page = item }
                }
            }
        }
        .animation(.easeOut(duration: Theme.Motion.page), value: current)
    }

    private var current: Page { page ?? .nowPlaying }
}

private struct PageTab: View {
    let item: Page
    let isCurrent: Bool
    let pill: Namespace.ID
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            Image(systemName: item.symbol)
                .font(Theme.Text.body)
                .foregroundStyle(isCurrent ? Theme.Colors.accentText : hovering ? Theme.Colors.text : Theme.Colors.textMuted)
                .frame(width: Theme.Size.pageTabTarget, height: Theme.Size.pageDotTarget)
                .background {
                    if isCurrent {
                        Capsule()
                            .fill(Theme.Colors.surface)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
        .tooltip(item.title, shown: hovering && !isCurrent)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// CUSTOM: a name under a control, after the pointer has rested on it for a
/// moment. The system tooltip cannot be told when to appear.
private struct Tooltip: ViewModifier {
    let text: String
    let shown: Bool

    @State private var visible = false
    @State private var wait: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if visible {
                    Text(text)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.text)
                        .padding(.horizontal, Theme.Space.xs)
                        .padding(.vertical, Theme.Space.xxs)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Colors.border))
                        .fixedSize()
                        .offset(y: Theme.Size.pageDotTarget + Theme.Space.xxs)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: visible)
            .onChange(of: shown) { _, isShown in
                wait?.cancel()
                if isShown {
                    wait = Task {
                        try? await Task.sleep(for: .seconds(Theme.Motion.tooltipDelay))
                        if !Task.isCancelled { visible = true }
                    }
                } else {
                    visible = false
                }
            }
    }
}

extension View {
    func tooltip(_ text: String, shown: Bool) -> some View {
        modifier(Tooltip(text: text, shown: shown))
    }
}

/// The window's own colour behind the content, which SwiftUI does not expose.
private struct WindowSetup: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.backgroundColor = NSColor(named: "bg") // tokens-ok
        }
    }

    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ nsView: View, context: Context) {}
}

/// The strip with the dots moves the window, since there is no title bar.
/// Only that strip: with the whole background movable, a click that moves
/// by a pixel becomes a window drag, and buttons and sliders miss it.
private struct DragHandle: NSViewRepresentable {
    final class View: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
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
