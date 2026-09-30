import SwiftUI

/// The main window: page dots, two pages side by side, and what is playing.
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
            Divider()
            footer
        }
        .ignoresSafeArea(edges: .top)
        .frame(width: Theme.Size.window.width, height: Theme.Size.window.height - topInset)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .background(WindowDragging())
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
        .scrollIndicators(.hidden)
        .animation(.spring(duration: Theme.Motion.page, bounce: 0), value: navigation.page)
    }

    private var footer: some View {
        VStack(spacing: Theme.Space.xs) {
            if let problem = player.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(problem)
            }
            HStack(alignment: .bottom, spacing: Theme.Space.xs) {
                if player.hasTrack {
                    NowPlayingView()
                } else {
                    Spacer()
                }
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
        }
        .padding(Theme.Space.m)
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
                        .fill(isCurrent(item) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
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

/// Lets the window be dragged by any empty area, since it has no title bar.
private struct WindowDragging: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isMovableByWindowBackground = true
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
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
