// Experiment 1 of docs/research/default-player.md: which registration makes a
// freshly launched app receive the Play key without having played anything.
//
// One binary, four bundles; the variant comes from the bundle's Info.plist
// (`SpikeVariant`), so each variant has its own bundle ID and no system state
// carries over between them:
//   none         command handlers only
//   paused       handlers + Now Playing info + playbackState .paused
//   playpaused   handlers + info + .playing, then .paused half a second later
//   playstopped  AntiMusic's trick: .playing then .stopped at once, then info
//
// No audio is played. Everything goes to the log given with `-log <path>`.

import AppKit
import MediaPlayer

final class Spike: NSObject, NSApplicationDelegate {
    let variant = Bundle.main.object(forInfoDictionaryKey: "SpikeVariant") as? String ?? "none"
    let logPath = UserDefaults.standard.string(forKey: "log") ?? NSTemporaryDirectory() + "eligibility.log"
    var item: NSStatusItem!

    func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        let line = "\(formatter.string(from: Date()))\t\(variant)\t\(message)\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("launch pid \(getpid())")
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Spike: \(variant)"
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        let center = MPRemoteCommandCenter.shared()
        let commands: [(MPRemoteCommand, String)] = [
            (center.playCommand, "play"), (center.pauseCommand, "pause"),
            (center.togglePlayPauseCommand, "toggle"),
            (center.nextTrackCommand, "next"), (center.previousTrackCommand, "previous"),
        ]
        for (command, name) in commands {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                self?.log("command \(name)")
                return .success
            }
        }

        let info = MPNowPlayingInfoCenter.default()
        let metadata: [String: Any] = [
            MPMediaItemPropertyTitle: "Spike \(variant)",
            MPMediaItemPropertyArtist: "B-Side experiment",
            MPMediaItemPropertyPlaybackDuration: 180.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0,
        ]
        switch variant {
        case "paused":
            info.nowPlayingInfo = metadata
            info.playbackState = .paused
        case "playpaused":
            info.nowPlayingInfo = metadata
            info.playbackState = .playing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                info.playbackState = .paused
                self.log("state paused")
            }
        case "playstopped":
            info.playbackState = .playing
            info.playbackState = .stopped
            info.nowPlayingInfo = metadata
        default:
            break
        }
        log("registered")

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.Music" { self?.log("Music launched") }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { log("quit") }
}

let app = NSApplication.shared
let delegate = Spike()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
