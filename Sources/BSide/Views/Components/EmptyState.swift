import SwiftUI

/// One shape for every "nothing to show" case: signed out, empty, failed.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    /// A quieter way out under the action, e.g. "Continue as Guest".
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

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
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(QuietButtonStyle())
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
                          message: reason, actionTitle: "Try Again", action: { player.retry() })
    }
    switch player.account {
    case .unknown:
        return nil
    case .signedOut:
        if player.isGuest { return nil }
        return EmptyState(symbol: "person.crop.circle", title: "Sign in to YouTube Music",
                          message: "B-Side plays the music from your account.",
                          actionTitle: "Sign In…", action: { player.showSignIn() },
                          secondaryTitle: "Continue as Guest", secondaryAction: { player.continueAsGuest() })
    case .signedIn:
        return nil
    }
}
