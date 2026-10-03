import AppIntents
import AppKit

/// The widget's buttons. Each sends its command to the running app over
/// the message port; when the app is not running, the command goes in a
/// URL that starts it.
enum WidgetMessenger {
    static func send(_ command: WidgetCommand) {
        if !WidgetPort.send(command) {
            NSWorkspace.shared.open(command.url)
        }
    }
}

struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses B-Side.")

    func perform() async throws -> some IntentResult {
        WidgetMessenger.send(.toggle)
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next track in B-Side.")

    func perform() async throws -> some IntentResult {
        WidgetMessenger.send(.next)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Goes back a track in B-Side.")

    func perform() async throws -> some IntentResult {
        WidgetMessenger.send(.previous)
        return .result()
    }
}

struct PlayVibeIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Vibe"
    static let description = IntentDescription("Starts B-Side's first vibe.")

    func perform() async throws -> some IntentResult {
        WidgetMessenger.send(.vibe)
        return .result()
    }
}
