// Experiment 2 of docs/research/default-player.md: after another player has
// taken the Play key, does it come back to the app that had it before?
//
// Two roles, from the bundle's Info.plist (`SpikeRole`):
//   home      stands in for B-Side: claims the Play key at launch the way
//             B-Side does (.playing, then .paused after 0.5 s)
//   intruder  stands in for another player: reports .playing, and after
//             two seconds does what `-then` says:
//               paused    .paused, keeps its info
//               playing   stays .playing
//               cleared   removes its info, .stopped, handlers disabled
// Every round uses its own pair of bundle IDs. No audio is played. Both
// roles log every remote command they receive to the file given with -log.

import AppKit
import MediaPlayer

final class Spike: NSObject, NSApplicationDelegate {
    let role = Bundle.main.object(forInfoDictionaryKey: "SpikeRole") as? String ?? "home"
    let round = Bundle.main.object(forInfoDictionaryKey: "SpikeRound") as? String ?? "?"
    let then = UserDefaults.standard.string(forKey: "then") ?? "paused"
    let logPath = UserDefaults.standard.string(forKey: "log") ?? NSTemporaryDirectory() + "stack.log"
    var item: NSStatusItem!
    var commands: [MPRemoteCommand] = []

    func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        let line = "\(formatter.string(from: Date()))\t\(round)\t\(role)\t\(message)\n"
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
        item.button?.title = "Spike: \(role)"
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        let center = MPRemoteCommandCenter.shared()
        let named: [(MPRemoteCommand, String)] = [
            (center.playCommand, "play"), (center.pauseCommand, "pause"),
            (center.togglePlayPauseCommand, "toggle"),
            (center.nextTrackCommand, "next"), (center.previousTrackCommand, "previous"),
        ]
        for (command, name) in named {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                self?.log("command \(name)")
                return .success
            }
            commands.append(command)
        }

        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Spike \(role) \(round)",
            MPMediaItemPropertyArtist: "B-Side experiment",
            MPMediaItemPropertyPlaybackDuration: 180.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        info.playbackState = .playing
        log("state playing")

        if role == "home" {
            after(0.5) { info.playbackState = .paused; self.log("state paused") }
        } else {
            after(2) {
                switch self.then {
                case "playing":
                    break
                case "cleared":
                    info.nowPlayingInfo = nil
                    info.playbackState = .stopped
                    self.commands.forEach { $0.isEnabled = false }
                    self.log("state cleared")
                default:
                    info.playbackState = .paused
                    self.log("state paused")
                }
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.Music", self?.role == "home" { self?.log("Music launched") }
        }
    }

    func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

let app = NSApplication.shared
let delegate = Spike()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
