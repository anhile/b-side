import SwiftUI

/// Signed out, not a guest: one screen over the whole window. Behind the
/// record three sleeves fan out in the Vibe colours, one for each thing signing in
/// brings (likes, playlists, mixes), on a wash of the first one's colour.
/// The picture and the words are one block in the middle; where the
/// password goes stands at the bottom.
struct SignInScreen: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fanned = false

    /// Left to right; the middle one stands behind the record.
    private static let sleeves: [(swatch: Int, symbol: String, x: CGFloat, y: CGFloat, angle: Double)] = [
        (1, Page.playlists.symbol, -0.55, 0.06, -12),
        (2, Page.vibe.symbol, 0.55, 0.06, 12),
        (0, "heart.fill", 0, -backRise, 0),
    ]
    /// How far the middle sleeve stands above the record, against its size.
    private static let backRise: CGFloat = 0.2

    var body: some View {
        // Where the password goes, at the bottom, when the window has the
        // height for it; the least window has not.
        ViewThatFits(in: .vertical) {
            content(withNote: true)
            content(withNote: false)
        }
        .onAppear {
            guard !fanned else { return }
            if reduceMotion { fanned = true; return }
            withAnimation(.spring(duration: Theme.Motion.signInFan, bounce: 0.25).delay(Theme.Motion.signInFanDelay)) {
                fanned = true
            }
        }
    }

    private func content(withNote: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.m)
            Record(size: Theme.Size.artworkLarge, spinning: false)
                .shadow(color: Theme.Colors.shadow.opacity(Theme.Opacity.signInShadow),
                        radius: Theme.Space.s, y: Theme.Space.xxs)
                .background { fan }
                .padding(.top, Theme.Size.signInSleeve * Self.backRise) // room for the sleeve behind
            Text("Your music")
                .font(Theme.Text.display)
                .foregroundStyle(Theme.Colors.text)
                .padding(.top, Theme.Space.xl)
            Text("Your playlists, likes and mixes\nfrom YouTube\u{00A0}Music, in one small player.")
                .font(Theme.Text.body)
                .foregroundStyle(Theme.Colors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(Theme.Space.xxs / 2)
                .frame(maxWidth: Theme.Size.signInText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.xs)
            Button { player.showSignIn() } label: { Label("Sign In…", systemImage: "person.crop.circle") }
                .buttonStyle(FilledButtonStyle(prominent: true))
                .padding(.top, Theme.Space.l)
            Button("Continue as Guest") { player.continueAsGuest() }
                .buttonStyle(QuietButtonStyle(font: Theme.Text.body))
                .padding(.top, Theme.Space.s)
                .help("A guest can search and play radios, without a library.")
            Spacer(minLength: Theme.Space.l)
            if withNote {
                Label("You sign in on Google\u{2019}s own page; B-Side never sees the password.",
                      systemImage: "lock.fill")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, Theme.Space.m)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The wash of Ember from the top of the window, title bar and all;
    /// the window draws it under the screen.
    static var wash: some View {
        LinearGradient(colors: [VibePalette.swatches[0].light.opacity(Theme.Opacity.signInWash), .clear],
                       startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
    }

    /// The sleeves come out from behind the record and settle, turned a
    /// little, as records leaned in a crate.
    private var fan: some View {
        let size = Theme.Size.signInSleeve
        return ZStack {
            ForEach(Self.sleeves.indices, id: \.self) { index in
                let sleeve = Self.sleeves[index]
                let swatch = VibePalette.swatches[sleeve.swatch]
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(LinearGradient(colors: [swatch.light, swatch.deep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: sleeve.x < 0 ? .topLeading : .topTrailing) {
                        Image(systemName: sleeve.symbol)
                            .font(.system(size: Theme.Size.signInSleeveGlyph, weight: .semibold))
                            .foregroundStyle(Theme.Colors.onVibe)
                            .padding(Theme.Space.s)
                    }
                    .frame(width: size, height: size)
                    .shadow(color: swatch.deep.opacity(Theme.Opacity.vibeShadow), radius: Theme.Space.s, y: Theme.Space.xxs)
                    .rotationEffect(.degrees(fanned ? sleeve.angle : 0))
                    .offset(x: fanned ? sleeve.x * size : 0, y: fanned ? sleeve.y * size : 0)
                    .opacity(fanned ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }
}
