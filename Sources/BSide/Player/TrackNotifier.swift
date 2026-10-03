import AppKit
import UserNotifications

/// A notification when the next track starts, if it is turned on in
/// Settings (off by default): the title, the artist and the artwork.
///
/// None while B-Side is in front, since its window shows the track already,
/// and none for ads. Each one replaces the last, so Notification Center keeps
/// one entry. Clicking it opens Now Playing.
@MainActor
final class TrackNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TrackNotifier()

    /// Shows the main window on Now Playing; set by the window.
    var onOpen: (() -> Void)?

    private static let identifier = "now-playing"
    private var lastVideoID = ""
    private var delivery: Task<Void, Never>?

    private var center: UNUserNotificationCenter { .current() }

    /// Before launch finishes, so a click that launched B-Side is not lost.
    func install() {
        center.delegate = self
    }

    /// Asks macOS for permission. False when the user said no, now or before.
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    /// Whether macOS lets B-Side show notifications at all.
    func isAllowed() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Called once per track, when its title is known.
    func trackStarted(_ state: PlayerState) {
        guard state.videoID != lastVideoID else { return } // the same track, reloaded
        lastVideoID = state.videoID
        delivery?.cancel()
        guard Settings.bool(Keys.notifyTrack), !state.isAd, !NSApp.isActive else { return }

        delivery = Task {
            let content = UNMutableNotificationContent()
            content.title = state.title
            content.body = state.artist
            content.threadIdentifier = Self.identifier
            if let attachment = await Self.artwork(state.artworkURL) {
                content.attachments = [attachment]
            }
            guard !Task.isCancelled else { return } // the next track came first
            let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    /// The artwork as a file, which is what a notification can attach. Up to
    /// Tuning.notificationArtworkWait; without it the notification goes
    /// without a picture.
    private static func artwork(_ url: URL?) async -> UNNotificationAttachment? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = Tuning.notificationArtworkWait
        guard let (data, _) = try? await Net.session.data(for: request) else { return nil }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("bside-artwork-\(UUID().uuidString).jpg")
        guard (try? data.write(to: file)) != nil else { return nil }
        // The system moves the file into its own store.
        return try? UNNotificationAttachment(identifier: "artwork", url: file)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { onOpen?() }
    }

    /// B-Side does not post while in front, but one can arrive just as it
    /// comes forward.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}
