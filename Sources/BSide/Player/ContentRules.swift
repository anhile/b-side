import Foundation
import WebKit

/// What the player page is not allowed to load. Nothing is ever shown from
/// the page, so images, fonts and stylesheets are wasted work.
enum ContentRules {
    // ---- ADJUST HERE ---------------------------------------------------------
    // URL patterns are observed, not documented. WebKit's rule syntax is a
    // limited regex: no alternation, so one pattern per rule.
    private static let blockedResourceTypes = ["image", "font", "style-sheet"]

    /// Playback stats pings (`/api/stats/playback`, `/watchtime`) are NOT
    /// here: blocking them would stop plays from reaching the watch history.
    private static let telemetryPatterns = [
        "google-analytics\\.com",
        "googletagmanager\\.com",
        "play\\.google\\.com/log",
        "/youtubei/v1/log_event",
        "/api/stats/qoe",
        "/ptracking",
        "/generate_204",
        "/error_204",
    ]

    /// Never blocked.
    private static let mediaHostPattern = "googlevideo\\.com"
    // --------------------------------------------------------------------------

    /// Later rules win, so the media exceptions must stay last.
    private static var encoded: String {
        var rules: [[String: Any]] = blockedResourceTypes.map {
            ["trigger": ["url-filter": ".*", "resource-type": [$0]], "action": ["type": "block"]]
        }
        rules += telemetryPatterns.map {
            ["trigger": ["url-filter": $0], "action": ["type": "block"]]
        }
        rules.append(["trigger": ["url-filter": ".*", "resource-type": ["media"]],
                      "action": ["type": "ignore-previous-rules"]])
        rules.append(["trigger": ["url-filter": mediaHostPattern],
                      "action": ["type": "ignore-previous-rules"]])
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(data: data, encoding: .utf8)!
    }

    @MainActor
    static func compile() async throws -> WKContentRuleList {
        guard let list = try await WKContentRuleListStore.default()
            .compileContentRuleList(forIdentifier: "bside-rules", encodedContentRuleList: encoded) else {
            throw CocoaError(.coderInvalidValue)
        }
        return list
    }
}
