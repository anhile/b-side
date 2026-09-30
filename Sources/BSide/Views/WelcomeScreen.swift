import SwiftUI

/// While the player page loads, instead of empty pages. After a start in
/// the menu bar the page waits for the first Play or for the window, and
/// then takes a few seconds. The record turns; there is nothing to press.
/// Laid out like "Nothing playing", so the record stays put when it follows.
struct WelcomeScreen: View {
    private var returning: Bool { Settings.bool(Keys.wasSignedIn) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.m)
            Record(size: Theme.Size.artworkLarge, spinning: true)
            Spacer(minLength: Theme.Space.l)
            Text(returning ? "Welcome back" : "Hello")
                .font(Theme.Text.display)
                .foregroundStyle(Theme.Colors.text)
            Text("Getting the player ready")
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .padding(.top, Theme.Space.xxs)
            // The height of the buttons under "Nothing playing", kept empty.
            Button {} label: { Label("Play Vibe", systemImage: Page.vibe.symbol) }
                .buttonStyle(FilledButtonStyle())
                .padding(.top, Theme.Space.m)
                .hidden()
            Spacer(minLength: Theme.Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
