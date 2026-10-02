import AppKit
import ServiceManagement

/// Open at login, through `SMAppService.mainApp` (macOS 13+). The system's
/// Login Items list is the only record of it; nothing is stored here.
///
/// It exists for the media keys: the system sends Play only to a running
/// app, and with none it starts Apple Music (experiments 1 to 3 in
/// docs/research/default-player.md).
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        EventLog.write("login item\t\(enabled ? "on" : "off"), status \(status.rawValue)")
    }

    /// Whether this launch came from the Login Items. Valid only inside
    /// `applicationDidFinishLaunching`, while the launch Apple event is still
    /// the current one; the check sindresorhus/LaunchAtLogin-Modern uses.
    static func launchedAtLogin() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
