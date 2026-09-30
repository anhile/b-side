import SwiftUI

/// The compact area both pages share: artwork, title, artist, progress, and
/// the transport controls.
struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerController

    /// Set while the user drags the slider, so reports do not fight the drag.
    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                Artwork(url: player.state.artworkURL, size: Theme.Size.artworkNowPlaying)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.state.title.isEmpty ? "Loading…" : player.state.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .help(player.state.title)
                    Text(player.state.isAd ? "Advertisement" : player.state.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            progress
            transport
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = max(player.state.duration, 1)
            let position = scrub ?? min(player.position(at: context.date), duration)
            VStack(spacing: 0) {
                Slider(
                    value: Binding(get: { position }, set: { scrub = $0 }),
                    in: 0...duration
                ) { editing in
                    if !editing, let target = scrub {
                        player.seek(to: target)
                        scrub = nil
                    }
                }
                .controlSize(.small)
                .disabled(player.state.duration <= 0 || player.state.isAd)
                .accessibilityLabel("Position")
                HStack {
                    Text(time(position))
                    Spacer()
                    Text(time(player.state.duration))
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: Theme.Space.l) {
            Spacer(minLength: Theme.Size.volumeWidth) // keeps the buttons centred with the volume on the left

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .help("Previous")
            .accessibilityLabel("Previous")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .help(player.state.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(player.state.isPlaying ? "Pause" : "Play")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!player.state.hasNext)
            .help("Next")
            .accessibilityLabel("Next")
            Spacer(minLength: Theme.Size.volumeWidth)
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) { volumeControl }
    }

    private var volumeControl: some View {
        HStack(spacing: Theme.Space.xxs) {
            Button {
                player.toggleMute()
            } label: {
                Image(systemName: volumeSymbol)
                    .frame(width: Theme.Size.volumeGlyph)
            }
            .buttonStyle(.borderless)
            .help(player.volume > 0 ? "Mute" : "Unmute")
            .accessibilityLabel(player.volume > 0 ? "Mute" : "Unmute")
            Slider(value: $player.volume, in: 0...100)
                .controlSize(.mini)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(player.volume)) percent")
        }
        .frame(width: Theme.Size.volumeWidth)
    }

    private var volumeSymbol: String {
        switch player.volume {
        case ..<1: return "speaker.slash.fill"
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
