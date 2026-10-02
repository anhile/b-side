import ServiceManagement
import SwiftUI

/// Where a new vibe's words are read: on this Mac (the default), or on the
/// B-Side server, which knows more music. See VibeServer.
struct VibeSettings: View {
    @AppStorage(Keys.vibeServer) private var useServer = false
    @AppStorage(Keys.vibeServerAddress) private var address = VibeServer.defaultAddress
    @State private var status: Status = .checking

    private enum Status: Equatable {
        case checking, unreachable, closed
        case open(VibeServer.Health)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $useServer) {
                    SettingLabel(title: "Read vibes on the B-Side server", symbol: "text.bubble", colour: 1)
                }
            } footer: {
                Text("A larger model reads the words of a new vibe and knows far more music, from deep cuts to Russian rock. The words go to the B-Side server and its AI provider and are not stored. When it is off, this Mac reads them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Server", text: $address, prompt: Text(VibeServer.defaultAddress))
                LabeledContent("Status") {
                    statusText
                }
            } footer: {
                Text("Anyone can run their own server: see server/ in the B-Side repository.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .disabled(!useServer)
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
        .task(id: "\(useServer) \(address)") {
            guard useServer else { return }
            status = .checking
            try? await Task.sleep(for: .milliseconds(600)) // while the address is typed
            // Asked again while it is not available: a new server's name
            // may take a while to reach this Mac's DNS.
            while !Task.isCancelled {
                if let url = VibeServer.address, let health = await VibeServer.health(at: url) {
                    status = health.open ? .open(health) : .closed
                    if health.open { return }
                } else {
                    status = .unreachable
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    @ViewBuilder private var statusText: some View {
        if !useServer {
            Text("Off")
        } else {
            switch status {
            case .checking: Text("Checking…")
            case .unreachable: Text("Cannot be reached")
            case .closed: Text("Not open right now")
            case .open(let health): Text("Available, " + (health.leftText ?? "\(health.perMonth) vibes a month"))
            }
        }
    }
}
