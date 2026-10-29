import AppKit
import SwiftUI

/// What the sign-in panel's bar shows: the host of the page under it, so it
/// is plain that the password goes to Google.
final class SignInPage: ObservableObject {
    @Published var host = ""
    @Published var isSecure = true
    @Published var isLoading = false
}

/// The bar over Google's sign-in page: the record, what this is, where the
/// page comes from, and Cancel. It stands in for the window's title bar.
struct SignInBar: View {
    @ObservedObject var page: SignInPage
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Record(size: Theme.Size.artworkSmall, spinning: page.isLoading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to YouTube Music")
                        .font(Theme.Text.title)
                        .foregroundStyle(Theme.Colors.text)
                    HStack(spacing: Theme.Space.xxs) {
                        Image(systemName: page.isSecure ? "lock.fill" : "lock.open")
                            .imageScale(.small)
                        Text(page.host.isEmpty ? "Loading…" : page.host)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .help("The page is Google's own; B-Side does not see the password.")
                }
                Spacer(minLength: Theme.Space.s)
                Button("Cancel", action: cancel)
                    .buttonStyle(OutlineButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(height: Theme.Size.signInBar)
            Rectangle()
                .fill(Theme.Colors.border)
                .frame(height: Theme.Size.hairline)
        }
        .background(Theme.Colors.bg)
    }
}

/// The bar above the web view, for the length of a sign-in.
final class SignInContainer: NSView {
    init(webView: NSView, page: SignInPage, cancel: @escaping () -> Void) {
        super.init(frame: webView.frame)
        let bar = NSHostingView(rootView: SignInBar(page: page, cancel: cancel))
        bar.safeAreaRegions = [] // the bar is the title bar: no room kept for one
        for view in [bar, webView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }
}
