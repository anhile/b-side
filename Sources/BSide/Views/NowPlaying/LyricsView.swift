import AppKit
import SwiftUI

/// The current track's lyrics, in a popover from the Lyrics button. Plain
/// text as YouTube Music's web client has it, with its source; fetched when
/// opened, and again when the track changes while it is open.
/// The lyrics in the artwork's place. Timed lines follow the playback: the
/// current one in `text`, the others muted, the view keeping it in the
/// middle; a click on a line plays from there. Plain text otherwise.
///
/// Nothing runs between lines: one wait until the next line starts, begun
/// again whenever the player reports (play, pause, seek, every 5 s).
struct LyricsView: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current: Int?
    @State private var height: CGFloat = 0

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The text first (usually here already), then the timings once
            // the text is in.
            .task(id: "\(player.state.videoID) \(player.lyrics?.videoID ?? "")") {
                player.loadLyrics()
                player.loadTimedLyrics()
            }
    }

    @ViewBuilder
    private var content: some View {
        if player.state.isAd {
            note("No lyrics during an ad.")
        } else if let lyrics = player.lyrics, lyrics.videoID == player.state.videoID, player.lyricsState == .loaded,
                  lyrics.isTimed || lyrics.timedTried {
            if lyrics.isTimed {
                timed(lyrics)
            } else if !lyrics.text.isEmpty {
                plain(lyrics)
            } else {
                note("No lyrics for this track.")
            }
        } else if case .failed(let reason) = player.lyricsState {
            note(reason)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func timed(_ lyrics: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(lyrics.lines.indices, id: \.self) { index in
                        Button { player.seek(to: lyrics.lines[index].start) } label: {
                            Text(lyrics.lines[index].text.isEmpty ? "♪" : lyrics.lines[index].text)
                                .font(Theme.Text.title)
                                .foregroundStyle(index == current ? Theme.Colors.text : Theme.Colors.textMuted)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .id(index)
                    }
                    source(lyrics)
                }
                // Half the height above and below, so the first and the last
                // line can come to the middle too.
                .padding(.top, max(Self.topRoom, height / 2))
                .padding(.bottom, height / 2)
            }
            .scrollIndicators(.never)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onChange(of: current) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: Theme.Motion.page)) {
                    proxy.scrollTo(current ?? 0, anchor: Self.readingLine)
                }
            }
            .onAppear {
                current = lyrics.lines.index(at: player.position(at: Date()))
                proxy.scrollTo(current ?? 0, anchor: Self.readingLine)
            }
        }
        .task(id: Follow(state: player.state, lines: lyrics.lines.count)) { await follow(lyrics.lines) }
    }

    /// The current line sits in the middle.
    private static let readingLine = UnitPoint(x: 0, y: 0.5)

    private struct Follow: Equatable {
        let state: PlayerState
        let lines: Int
    }

    private func follow(_ lines: [LyricLine]) async {
        while !Task.isCancelled {
            let position = player.position(at: Date())
            let index = lines.index(at: position)
            if index != current { current = index }
            guard player.state.isPlaying else { return }
            let next = (index ?? -1) + 1
            guard next < lines.count else { return }
            try? await Task.sleep(for: .seconds(max(lines[next].start - position, Theme.Motion.feedback)))
        }
    }

    private func plain(_ lyrics: Lyrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(lyrics.text)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.text)
                    .lineSpacing(Theme.Space.xxs)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                source(lyrics)
            }
            .padding(.top, Self.topRoom)
            .padding(.bottom, Theme.Space.m)
        }
        .scrollIndicators(.never)
    }

    /// Clear of the Hide Lyrics button at the top, while scrolled to the start.
    private static var topRoom: CGFloat { Theme.Space.xs + Theme.Size.transportTarget + Theme.Space.xs }

    @ViewBuilder
    private func source(_ lyrics: Lyrics) -> some View {
        if !lyrics.source.isEmpty {
            Text(lyrics.source)
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Space.s)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Text.caption)
            .foregroundStyle(Theme.Colors.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
