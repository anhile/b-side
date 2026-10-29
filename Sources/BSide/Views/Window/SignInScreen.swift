import SwiftUI

/// Signed out, not a guest: one screen over the whole window. The record
/// stands where Welcome has it, so the hand-over moves nothing; behind it
/// three sleeves fan out in the Vibe colours, one for each thing signing in
/// brings (likes, playlists, mixes), on a wash of the first one's colour.
struct SignInScreen: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fanned = false

    /// Left to right; the middle one stands behind the record.
    private static let sleeves: [(swatch: Int, symbol: String, x: CGFloat, y: CGFloat, angle: Double)] = [
        (1, Page.playlists.symbol, -0.55, 0.06, -12),
        (2, Page.vibe.symbol, 0.55, 0.06, 12),
        (0, "heart.fill", 0, -0.2, 0),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.m)
            Record(size: Theme.Size.artworkLarge, spinning: false)
                .shadow(color: Theme.Colors.shadow.opacity(Theme.Opacity.signInShadow),
                        radius: Theme.Space.s, y: Theme.Space.xxs)
                .background { fan }
            Spacer(minLength: Theme.Space.l)
            Text("Your music")
                .font(Theme.Text.display)
                .foregroundStyle(Theme.Colors.text)
            Text("Sign in to YouTube Music for your playlists, your likes and your mixes.")
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Space.xxs)
            Button { player.showSignIn() } label: { Label("Sign In…", systemImage: "person.crop.circle") }
                .buttonStyle(FilledButtonStyle())
                .padding(.top, Theme.Space.m)
            Button("Continue as Guest") { player.continueAsGuest() }
                .buttonStyle(QuietButtonStyle())
                .padding(.top, Theme.Space.xxs)
                .help("A guest can search and play radios, without a library.")
            Spacer(minLength: Theme.Space.l)
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(colors: [VibePalette.swatches[0].light.opacity(Theme.Opacity.signInWash), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .onAppear {
            guard !fanned else { return }
            if reduceMotion { fanned = true; return }
            withAnimation(.spring(duration: Theme.Motion.signInFan, bounce: 0.25).delay(Theme.Motion.signInFanDelay)) {
                fanned = true
            }
        }
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
