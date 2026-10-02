import SwiftUI

/// While the player page loads, instead of empty pages. After a start in
/// the menu bar the page waits for the first Play or for the window, and
/// then takes a few seconds. The record turns; there is nothing to press,
/// until it takes long: then the line says so, and later Try Again shows
/// where "Nothing playing" has its buttons.
/// Laid out like "Nothing playing", so the record stays put when it follows.
struct WelcomeScreen: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var returning: Bool { Settings.bool(Keys.wasSignedIn) }

    private var line: String {
        switch player.startWait {
        case .short: "Getting the player ready"
        case .long: "Taking longer than usual\u{2026}"
        case .tooLong: "Still not ready. Check the connection."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.m)
            Record(size: Theme.Size.artworkLarge, spinning: true)
            Spacer(minLength: Theme.Space.l)
            Text(returning ? "Welcome back" : "Hello")
                .font(Theme.Text.display)
                .foregroundStyle(Theme.Colors.text)
            Text(line)
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .padding(.top, Theme.Space.xxs)
                .contentTransition(.opacity)
            // The height of the buttons under "Nothing playing": empty,
            // then Try Again. With Reduce Motion the record stands still,
            // so a spinner here shows that something is going on.
            Button { player.retry() } label: { Label("Try Again", systemImage: "arrow.clockwise") }
                .buttonStyle(OutlineButtonStyle())
                .opacity(player.startWait == .tooLong ? 1 : 0)
                .allowsHitTesting(player.startWait == .tooLong)
                .accessibilityHidden(player.startWait != .tooLong)
                .overlay {
                    if reduceMotion, player.startWait != .tooLong {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.top, Theme.Space.m)
            Spacer(minLength: Theme.Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: Theme.Motion.page), value: player.startWait)
    }
}
