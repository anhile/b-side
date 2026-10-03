import SwiftUI

/// The main window: page dots, three pages side by side, and the strip with
/// what is playing under the first two.
struct PlayerWindow: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    /// The hidden title bar still counts as a safe area at the top. The
    /// content goes under it, and the window must not grow by its height.
    @State private var topInset = Theme.Size.titleBar
    /// The artwork's colour, over the top of the window while Now Playing
    /// shows: from the title bar down to just above the track's name.
    @State private var tint: Color?
    @State private var tintBottom: CGFloat = 0
    /// The page the pager shows; follows `navigation.page` by a jump, and
    /// leads it on a swipe.
    @State private var shownPage: Page? = .nowPlaying
    @State private var pageDipped = false
    /// Not hidden, minimised or covered by other windows.
    @State private var windowVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // A glass bar the height of the title bar: traffic lights on the
            // left, the page icons on the right, the window dragged by the rest.
            DragHandle()
                // The page's name after the traffic lights, where a window
                // has its title; the icons at the other end are the buttons.
                .overlay(alignment: .leading) {
                    Text((navigation.page ?? .nowPlaying).title)
                        .font(Theme.Text.label)
                        .foregroundStyle(Theme.Colors.text)
                        .id(navigation.page)
                        .transition(.opacity)
                        .padding(.leading, Theme.Size.trafficLights)
                        .opacity(player.showsWelcome ? 0 : 1)
                        .allowsHitTesting(false) // the bar under it moves the window
                        .animation(.easeOut(duration: Theme.Motion.page), value: navigation.page)
                }
                .overlay(alignment: .trailing) {
                    PageTabs(page: $navigation.page)
                        .padding(.trailing, Theme.Space.xs)
                        .opacity(player.showsWelcome ? 0 : 1)
                        .allowsHitTesting(!player.showsWelcome)
                }
                .frame(height: barHeight)
                // Playlists and Explore put their own bar right under it.
                .barGlass(joined: Page.withBar.contains(navigation.page) ? .bottom : [])
            ZStack {
                if player.showsWelcome {
                    WelcomeScreen()
                        .transition(.opacity)
                } else {
                    pages
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: Theme.Motion.page), value: player.showsWelcome)
                .overlay(alignment: .bottom) {
                    VStack(spacing: Theme.Space.xs) {
                        if let notice = player.notice {
                            NoticeView(text: notice)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        footer
                    }
                    .padding(.bottom, Theme.Space.xs)
                    .animation(.easeInOut(duration: Theme.Motion.feedback), value: showsFooter)
                    .animation(.snappy(duration: Theme.Motion.page), value: player.notice)
                }
                .sheet(item: $navigation.newPlaylist) { request in
                    NewPlaylistSheet(request: request)
                        .environmentObject(player)
                }
        }
        .background(Theme.Colors.bg)
        .coordinateSpace(name: "window")
        .onPreferenceChange(TintBottomKey.self) { tintBottom = $0 }
        .ignoresSafeArea(edges: .top)
        .frame(width: Theme.Size.window.width, height: Theme.Size.window.height - topInset)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .background(WindowSetup())
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? NSWindow, window === MainWindow.window else { return }
            windowVisible = window.occlusionState.contains(.visible)
        }
        .task {
            guard !Settings.isSnapshot else { return }
            player.start()
            StatusMenu.shared.install(player: player) {
                if !MainWindow.show() { openWindow(id: "main") }
            }
            SpaceKey.install { player.togglePlayPause() }
            Capture.schedule(navigation: navigation)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.urlCommand)) { note in
            guard let name = note.object as? String, let command = WidgetCommand(rawValue: name) else { return }
            if command == .show { navigation.page = .nowPlaying }
            player.perform(command)
            TrackNotifier.shared.onOpen = {
                if !MainWindow.show() { openWindow(id: "main") }
                navigation.page = .nowPlaying
            }
        }
        .task(id: player.state.artworkURL) {
            tint = player.hasTrack ? await ArtworkTint.color(for: player.state.artworkURL) : nil
        }
    }

    /// The glass bar with the page tabs: the system's title bar, or taller at
    /// the Large size, where the tabs grow and the traffic lights do not.
    private var barHeight: CGFloat { max(topInset, Theme.Size.tabBar) }

    /// Part of the Now Playing page, so it leaves with the page instead of
    /// fading out over the next one. The page starts under the title bar,
    /// whose glass keeps the plain background.
    private var tintLayer: some View {
        (tint ?? Theme.Colors.bg)
            .opacity(tint != nil ? Theme.Tint.opacity : 0)
            .frame(height: max(tintBottom - barHeight, 0))
            .animation(.easeInOut(duration: Theme.Motion.tintChange), value: tint)
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
    /// the finger, with no custom gesture code. A tab, a shortcut or a link
    /// does not scroll through the pages between: the page dips out, the
    /// pager jumps, and the new page comes in.
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
        .scrollPosition(id: $shownPage)
        .scrollIndicators(.never)
        .opacity(pageDipped ? 0 : 1)
        .onAppear { shownPage = navigation.page }
        // A swipe: the pager moved, the tabs follow.
        .onChange(of: shownPage) { _, shown in
            if let shown, shown != navigation.page { navigation.page = shown }
        }
        // Anything else: jump there.
        .onChange(of: navigation.page) { _, target in
            guard target != shownPage else { return }
            jump(to: target)
        }
    }

    /// At once, unseen, then the page fades in: no waiting on a fade out,
    /// nothing in between slides past.
    private func jump(to target: Page?) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            pageDipped = true
            shownPage = target
        }
        // On the next turn, so the hidden frame is drawn first.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: Theme.Motion.pageFadeIn)) { pageDipped = false }
        }
    }

    private func page(_ page: Page) -> some View {
        Group {
            switch page {
            case .vibe: VibePage()
            case .explore: ExplorePage()
            case .playlists: PlaylistsPage()
            case .nowPlaying: NowPlayingPage()
            }
        }
        // Vibe and Playlists let their lists run under the glass strip and
        // keep the room as scroll margin; Now Playing is pushed up instead.
        .environment(\.footerRoom, footerRoom(on: page))
        .environment(\.pageShown, windowVisible && navigation.page == page)
        .padding(.bottom, page == .nowPlaying ? footerRoom(on: page) : 0)
        .background(alignment: .top) {
            if page == .nowPlaying { tintLayer }
        }
        .animation(.easeInOut(duration: Theme.Motion.feedback), value: player.problem)
    }

    /// Vibe and Playlists always keep the strip's place, so their lists do
    /// not jump when music starts. Now Playing is that content already and
    /// takes the whole height, unless there is a problem to show.
    private func footerRoom(on page: Page) -> CGFloat {
        // The strip, the gap under it, and as much again above it.
        page != .nowPlaying || player.problem != nil ? Theme.Size.stripHeight + Theme.Space.xs * 2 : 0
    }

    private var showsFooter: Bool {
        player.problem != nil || ((player.hasTrack || player.isLoading) && navigation.page != .nowPlaying)
    }

    /// The strip shows on Vibe and Playlists while something plays; Now
    /// Playing is that content already. A glass panel of its own, 8 inside
    /// the window edges, over the bottom of the pages. Settings live in the
    /// menu bar and under Command-comma.
    @ViewBuilder
    private var footer: some View {
        if showsFooter {
            footerContent
                .frame(height: Theme.Size.stripHeight)
                .glass(in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
                .padding(.horizontal, Theme.Space.xs)
                .transition(.opacity)
        }
    }

    private var footerContent: some View {
        HStack(alignment: .center, spacing: Theme.Space.xs) {
            if let problem = player.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .lineLimit(2)
                    .help(problem)
                    .padding(.leading, Theme.Space.xs)
                Spacer(minLength: 0)
            } else if player.hasTrack || player.isLoading, navigation.page != .nowPlaying {
                NowPlayingStrip { navigation.page = .nowPlaying }
                    .padding(.horizontal, Theme.Space.xxs) // artwork and buttons fill the panel's height
            }
        }
    }
}

/// The window's own colour behind the content, which SwiftUI does not expose.
private struct WindowSetup: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.backgroundColor = NSColor(named: "bg") // tokens-ok
            MainWindow.attach(window)
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

/// How much of a page's bottom the glass strip covers. Pages with a list
/// use it as scroll margin, so the list runs under the glass and its last
/// row can still scroll clear of it; other states keep out of it.
/// Whether a page is the one on screen in a visible window. Endless
/// animations (the record, a playing tile's speaker) run only then.
private struct PageShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var pageShown: Bool {
        get { self[PageShownKey.self] }
        set { self[PageShownKey.self] = newValue }
    }
}

private struct FooterRoomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var footerRoom: CGFloat {
        get { self[FooterRoomKey.self] }
        set { self[FooterRoomKey.self] = newValue }
    }
}
