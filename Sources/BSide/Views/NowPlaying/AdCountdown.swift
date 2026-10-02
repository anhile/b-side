import AppKit
import SwiftUI

/// Under "Advertisement": when the music comes back, counted down each
/// second. In a run of ads only the last one's end is the music's return,
/// so the others say which ad it is and how long it still runs.
struct AdCountdown: View {
    let font: Font
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.text(for: player.state, at: context.date))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textMuted)
                .lineLimit(1)
        }
    }

    static func text(for state: PlayerState, at date: Date) -> String {
        guard let left = state.adRemaining(at: date) else { return "" }
        let seconds = Int(left.rounded(.up))
        let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return state.moreAdsFollow ? "Ad \(state.adIndex) of \(state.adCount) · \(time)" : "Music back in \(time)"
    }
}
