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
                    LabeledContent("YouTube Music", value: "Checking…")
                case .signedOut:
                    LabeledContent("YouTube Music", value: "Not signed in")
                    Button("Sign In…") { player.showSignIn() }
                case .signedIn(let name, let handle, let photoURL):
                    HStack(spacing: Theme.Space.s) {
                        AsyncImage(url: photoURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: Theme.Size.avatar, height: Theme.Size.avatar)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(name.isEmpty ? "YouTube Music" : name)
                            Text(handle.isEmpty ? "Signed in" : handle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .textSelection(.enabled)
                        Spacer()
                        Button("Sign Out…") { confirmingSignOut = true }
                    }
                    .padding(.vertical, Theme.Space.xxs)
                }
            } footer: {
                Text("You sign in on Google's own page. B-Side never sees your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
        .confirmationDialog("Sign out of YouTube Music?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) { player.signOut() }
        } message: {
            Text("Playback stops, and the cookies and caches B-Side keeps for YouTube Music are removed.")
        }
    }
}
