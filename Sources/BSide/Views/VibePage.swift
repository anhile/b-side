import SwiftUI

/// CUSTOM: the one big button of the Vibe page. Filled with the text colour,
/// never with the accent.
struct HeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Theme.Size.heroGlyph))
            .foregroundStyle(Theme.Colors.bg)
            .frame(width: Theme.Size.heroButton, height: Theme.Size.heroButton)
            .background(Theme.Colors.text, in: Circle())
            .contentShape(Circle())
            .opacity(configuration.isPressed ? Theme.Opacity.pressed : 1)
    }
}

/// One job: start music with one click. Liked Music, shuffled.
struct VibePage: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        if let blocked = blockingState(for: player) {
            blocked
        } else if player.account == .unknown {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
        }
    }

    private var isVibePlaying: Bool {
        player.source == .vibe && player.state.isPlaying
    }

    private var content: some View {
        VStack(spacing: Theme.Space.m) {
            Spacer()
            Button {
                // While Vibe is the queue the button pauses and resumes it;
                // otherwise it starts a fresh shuffle.
                if player.source == .vibe, player.hasTrack {
                    player.togglePlayPause()
                } else {
                    player.playVibe()
                }
            } label: {
                Image(systemName: isVibePlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(HeroButtonStyle())
            .help(isVibePlaying ? "Pause" : "Play Liked Music, shuffled")
            .accessibilityLabel(isVibePlaying ? "Pause" : "Play Vibe")

            VStack(spacing: Theme.Space.xxs) {
                Text("Vibe")
                    .font(Theme.Text.display)
                    .foregroundStyle(Theme.Colors.text)
                Text("Liked Music, shuffled")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
