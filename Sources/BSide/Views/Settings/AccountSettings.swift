import ServiceManagement
import SwiftUI

struct AccountSettings: View {
    @EnvironmentObject private var player: PlayerController
    @State private var confirmingSignOut = false

    var body: some View {
        Form {
            Section {
                switch player.account {
                case .unknown:
                    // No answer comes from a page that did not start.
                    if case .failed = player.phase {
                        row(title: "Not connected", detail: "YouTube Music could not be loaded.") {
                            avatarSymbol("exclamationmark.triangle.fill")
                        } action: {
                            Button("Try Again") { player.retry() }
                        }
                    } else {
                        row(title: "Checking\u{2026}", detail: "Asking YouTube Music who is signed in.") {
                            Record(size: Theme.Size.avatar, spinning: true)
                        } action: {
                            ProgressView().controlSize(.small)
                        }
                    }
                case .signedOut:
                    row(title: "Not signed in",
                        detail: player.isGuest ? "As a guest: search and radios, no library."
                                               : "Sign in for your playlists, likes and mixes.") {
                        Record(size: Theme.Size.avatar, spinning: false)
                    } action: {
                        Button("Sign In\u{2026}") { player.showSignIn() }
                            .buttonStyle(.borderedProminent)
                    }
                case .signedIn(let name, let handle, let photoURL):
                    row(title: name.isEmpty ? "YouTube Music" : name, detail: handle.isEmpty ? "Signed in" : handle) {
                        AsyncImage(url: photoURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            avatarSymbol("person.crop.circle.fill")
                        }
                        .frame(width: Theme.Size.avatar, height: Theme.Size.avatar)
                        .clipShape(Circle())
                    } action: {
                        Button("Sign Out\u{2026}") { confirmingSignOut = true }
                    }
                    .textSelection(.enabled)
                }
            } footer: {
                Label("You sign in on Google\u{2019}s own page. B-Side never sees your password.", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if case .signedOut = player.account {
                // What signing in brings, as the sign-in screen's sleeves say it.
                Section("With an account") {
                    gain("Your playlists, private ones too", symbol: Page.playlists.symbol)
                    gain("Your likes, in Liked Music", symbol: "heart.fill")
                    gain("Vibes from your own mixes", symbol: Page.vibe.symbol)
                }
            }
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
        .confirmationDialog("Sign out of YouTube Music?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) { player.signOut() }
        } message: {
            Text("Playback stops. B-Side signs out on Google\u{2019}s page and removes the session\u{2019}s cookies and its caches.")
        }
    }

    /// One shape for every state: a picture, what it is, and what to do.
    private func row<Avatar: View, Action: View>(title: String, detail: String,
                                                 @ViewBuilder avatar: () -> Avatar,
                                                 @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: Theme.Space.s) {
            avatar()
                .frame(width: Theme.Size.avatar, height: Theme.Size.avatar)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            action()
        }
        .padding(.vertical, Theme.Space.xxs)
    }

    private func avatarSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.secondary)
    }

    private func gain(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Colors.accent)
        }
    }
}
