import SwiftUI

/// Every "nothing to show" case (signed out, empty, failed) in the layout
/// of Welcome, signing in and "Nothing playing" (StageLayout): a picture on
/// the stage, a display title, two lines, a wide button and a quiet one.
/// The picture is the record with its sleeves, where an account would fill
/// the page, or a large symbol in a soft circle: the accent's, or a plain
/// one for a problem.
struct EmptyState: View {
    enum Picture {
        /// The symbol in a soft circle of the accent.
        case glyph
        /// The symbol in a plain circle: something went wrong.
        case problem
        /// The record with the account's sleeves fanned out.
        case sleeves
    }

    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    /// A quieter way out under the action, e.g. "Continue as Guest".
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var picture: Picture = .glyph
    /// The secondary action's tooltip: what choosing it means.
    var secondaryHelp: String?

    var body: some View {
        StageLayout(title: title, text: message) {
            switch picture {
            case .sleeves: RecordWithSleeves()
            case .glyph: StageGlyph(symbol: symbol, problem: false)
            case .problem: StageGlyph(symbol: symbol, problem: true)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(FilledButtonStyle(prominent: true))
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(QuietButtonStyle(font: Theme.Text.body))
                    .help(secondaryHelp ?? secondaryTitle)
            }
        }
    }
}

/// A large symbol in a soft circle, on the stage of an empty state.
struct StageGlyph: View {
    let symbol: String
    let problem: Bool

    var body: some View {
        let colour = problem ? Theme.Colors.textMuted : Theme.Colors.accent
        Image(systemName: symbol)
            .font(.system(size: Theme.Size.stageGlyph, weight: .regular))
            .foregroundStyle(problem ? Theme.Colors.textMuted : Theme.Colors.accentText)
            .frame(width: Theme.Size.stageCircle, height: Theme.Size.stageCircle)
            .background(LinearGradient(colors: [colour.opacity(Theme.Opacity.stageCircleTop),
                                                colour.opacity(Theme.Opacity.stageCircleBottom)],
                                       startPoint: .top, endPoint: .bottom),
                        in: Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// What a page shows when the account or the player is not usable yet, or
/// nil when the page can show its own content.
@MainActor
func blockingState(for player: PlayerController) -> EmptyState? {
    if case .failed(let reason) = player.phase {
        return EmptyState(symbol: "wifi.exclamationmark", title: "Not connected",
                          message: reason, actionTitle: "Try Again", action: { player.retry() }, picture: .problem)
    }
    switch player.account {
    case .unknown:
        return nil
    case .signedOut:
        if player.isGuest { return nil }
        return EmptyState(symbol: "person.crop.circle", title: "Your music",
                          message: "Sign in to YouTube Music for your playlists, your likes and your mixes.",
                          actionTitle: "Sign In…", action: { player.showSignIn() },
                          secondaryTitle: "Continue as Guest", secondaryAction: { player.continueAsGuest() },
                          picture: .sleeves, secondaryHelp: "A guest can search and play radios, without a library.")
    case .signedIn:
        return nil
    }
}
