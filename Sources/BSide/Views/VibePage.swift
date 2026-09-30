import SwiftUI

/// CUSTOM: the one big button of the Vibe page. Filled with the text colour,
/// never with the accent.
struct HeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Theme.Size.heroGlyph))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .frame(width: Theme.Size.heroButton, height: Theme.Size.heroButton)
            .background(.primary, in: Circle())
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
                    .font(.largeTitle.bold())
                Text("Liked Music, shuffled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
