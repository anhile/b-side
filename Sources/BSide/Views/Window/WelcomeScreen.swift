import SwiftUI

/// While the player page loads, instead of empty pages. After a start in
/// the menu bar the page waits for the first Play or for the window, and
/// then takes a few seconds. The record turns; there is nothing to press,
/// until it takes long: then the line says so, and later Try Again shows
/// where "Nothing playing" has its buttons.
/// Laid out as signing in and "Nothing playing" (StageLayout), so the
/// record stays put when either follows.
struct WelcomeScreen: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var returning: Bool { Settings.bool(Keys.wasSignedIn) }

    private var failed: Bool {
        if case .failed = player.phase { return true }
        return false
    }

    private var line: String {
        if case .failed(let reason) = player.phase { return reason }
        return switch player.startWait {
        case .short: "Getting the player ready"
        case .long: "Taking longer than usual\u{2026}"
        case .tooLong: "Still not ready. Check the connection."
        }
    }

    var body: some View {
        StageLayout(title: failed ? "Not connected" : returning ? "Welcome back" : "Hello", text: line) {
            // The sleeves folded behind the record: they fan out on the
            // screen that follows.
            RecordWithSleeves(fanned: false, spinning: !failed)
        } actions: {
            // Empty, then Try Again. With Reduce Motion the record stands
            // still, so a spinner here shows that something is going on.
            Button { player.retry() } label: { Label("Try Again", systemImage: "arrow.clockwise") }
                .buttonStyle(FilledButtonStyle(prominent: true))
                .opacity(showsRetry ? 1 : 0)
                .allowsHitTesting(showsRetry)
                .accessibilityHidden(!showsRetry)
                .overlay {
                    if reduceMotion, !showsRetry {
                        ProgressView().controlSize(.small)
                    }
                }
        }
        .animation(.easeInOut(duration: Theme.Motion.page), value: player.startWait)
        .animation(.easeInOut(duration: Theme.Motion.page), value: failed)
    }

    /// Try Again once the start has taken too long, or has failed.
    private var showsRetry: Bool { failed || player.startWait == .tooLong }
}
