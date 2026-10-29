import SwiftUI

/// Signed out, not a guest: one screen over the whole window, laid out as
/// Welcome and "Nothing playing" (StageLayout). The stage shows the app's
/// parts in turn, as the website does: the account first (the record with
/// the sleeves fanned out), then Vibes, Now Playing, Lyrics, Explore and
/// the menu bar; the title and lines change with it, the buttons stay.
/// It moves on every few seconds, not while the pointer is on the stage;
/// the dots under the stage go to any one.
struct SignInScreen: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var slide = SignInSlide.music
    @State private var hovering = false

    var body: some View {
        StageLayout(title: slide.title, text: slide.text,
                    note: ("You sign in on Google\u{2019}s own page; B-Side never sees the password.", "lock.fill")) {
            ZStack {
                SignInSlideStage(slide: slide)
                    .id(slide)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: Theme.Size.slideShift).combined(with: .opacity),
                        removal: .offset(x: -Theme.Size.slideShift).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .overlay(alignment: .bottom) { dots.offset(y: Theme.Space.m) }
        } actions: {
            Button { player.showSignIn() } label: { Label("Sign In…", systemImage: "person.crop.circle") }
                .buttonStyle(FilledButtonStyle(prominent: true))
            Button("Continue as Guest") { player.continueAsGuest() }
                .buttonStyle(QuietButtonStyle(font: Theme.Text.body))
                .help("A guest can search and play radios, without a library.")
        }
        .animation(.easeInOut(duration: Theme.Motion.slideChange), value: slide)
        .task(id: slide) {
            // On to the next one, unless the pointer rests on the stage.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Theme.Motion.slideSeconds))
                guard !Task.isCancelled else { return }
                if !hovering {
                    slide = slide.next
                    return
                }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(SignInSlide.allCases) { item in
                Button { slide = item } label: {
                    Capsule()
                        .fill(item == slide ? Theme.Colors.text : Theme.Colors.textMuted.opacity(Theme.Opacity.slideDot))
                        .frame(width: item == slide ? Theme.Size.slideDotActive : Theme.Size.slideDot,
                               height: Theme.Size.slideDot)
                        .padding(.vertical, Theme.Space.xxs) // a taller target than the dot
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item == slide ? .isSelected : [])
            }
        }
    }

    /// The wash of Ember from the top of the window, title bar and all;
    /// the window draws it under the screen.
    static var wash: some View {
        LinearGradient(colors: [VibePalette.swatches[0].light.opacity(Theme.Opacity.signInWash), .clear],
                       startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
    }
}
