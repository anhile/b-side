import AppKit
import Combine
import SwiftUI

/// The record in the menu bar and its menu, in AppKit so the first item can
/// be a real view: artwork, the title scrolling when long, and the transport
/// buttons. The rest are ordinary items, rebuilt each time the menu opens.
/// While the menu is closed nothing runs but the watch for a new track,
/// whose name can stand next to the record (Settings, General).
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    static let shared = StatusMenu()

    private var item: NSStatusItem?
    private let menu = NSMenu()
    private weak var player: PlayerController?
    private var openMain: (() -> Void)?
    private var watches: Set<AnyCancellable> = []

    func install(player: PlayerController, openMain: @escaping () -> Void) {
        self.player = player
        self.openMain = openMain
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Where the user drags the icon (Command-drag, or with a menu bar
        // manager such as Hidden Bar) is saved under this name as "NSStatusItem
        // Preferred Position B-Side" and restored at launch. Without a saved
        // position a new icon lands at the left end of the app icons, which
        // is inside a menu bar manager's hidden section.
        item.autosaveName = "B-Side"
        item.button?.image = MenuBarIcon.image
        item.button?.toolTip = "B-Side"
        item.button?.imagePosition = .imageLeading
        item.menu = menu
        menu.delegate = self
        self.item = item
        // The track's name next to the record: again when the track changes
        // (the state is published before it is set, hence from the value),
        // and when the setting does.
        player.$state
            .map(Self.trackLine)
            .removeDuplicates()
            .sink { [weak self] in self?.show(track: $0) }
            .store(in: &watches)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let player = self.player else { return }
                    self.show(track: Self.trackLine(player.state))
                }
            }
            .store(in: &watches)
        // Where the icon ended up, for when it cannot be seen: a place
        // left of the screen is a menu bar manager's hidden section.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak item] in
            guard let item else { return }
            let frame = item.button?.window?.frame ?? .zero
            let screen = item.button?.window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
            EventLog.write("status\ticon at x \(Int(frame.minX)) of \(Int(screen.width)), "
                + (item.isVisible ? "allowed" : "not allowed") + " in the menu bar"
                + (item.button?.window?.screen == nil ? ", off every screen" : ""))
        }
    }

    /// "Title — Artist", cut to fit the menu bar; empty with nothing loaded.
    private static func trackLine(_ state: PlayerState) -> String {
        guard !state.videoID.isEmpty else { return "" }
        if state.isAd { return "Advertisement" }
        let line = state.artist.isEmpty ? state.title : "\(state.title) — \(state.artist)"
        guard line.count > Tuning.menuBarTrackLength else { return line }
        return line.prefix(Tuning.menuBarTrackLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The record alone, or with the track's name after it when the user
    /// asked for it and something is loaded.
    private func show(track line: String) {
        guard let item else { return }
        let title = Settings.bool(Keys.menuBarTrack) ? line : ""
        guard item.button?.title != title else { return }
        item.button?.title = title
        item.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let player else { return }
        player.wake() // the menu lists playlists and tiles: load them
        menu.removeAllItems()

        let head = NSMenuItem()
        let view = NSHostingView(rootView: StatusMenuHead().environmentObject(player))
        view.frame.size = view.fittingSize
        head.view = view
        menu.addItem(head)
        menu.addItem(.separator())

        let vibe = NSMenuItem(title: Page.vibe.title, action: nil, keyEquivalent: "")
        vibe.submenu = NSMenu(title: Page.vibe.title)
        vibe.submenu?.autoenablesItems = false
        for mood in player.moods {
            let item = Self.item(mood.name) { [weak player] in player?.play(mood) }
            item.isEnabled = player.account.isSignedIn || !mood.needsAccount
            vibe.submenu?.addItem(item)
        }
        vibe.isEnabled = player.account.isSignedIn || player.isGuest
        menu.addItem(vibe)

        let playlists = NSMenuItem(title: "Playlists", action: nil, keyEquivalent: "")
        playlists.submenu = NSMenu(title: "Playlists")
        let liked = Playlist(id: Tuning.likedMusicID, title: "Liked Music")
        playlists.submenu?.addItem(Self.item(liked.title) { [weak player] in player?.play(liked) })
        for playlist in player.playlists where playlist.id != Tuning.likedMusicID {
            playlists.submenu?.addItem(Self.item(playlist.title) { [weak player] in player?.play(playlist) })
        }
        playlists.isEnabled = player.account.isSignedIn
        menu.addItem(playlists)
        menu.addItem(.separator())

        menu.addItem(Self.item("Show B-Side") { [weak self] in
            self?.openMain?()
            NSApp.activate(ignoringOtherApps: true)
        })
        menu.addItem(Self.item("Settings…", key: ",") { [weak player] in
            if let player { SettingsWindow.show(player: player) }
        })
        menu.addItem(.separator())
        menu.addItem(Self.item("Quit B-Side", key: "q") { NSApp.terminate(nil) })
    }

    private static func item(_ title: String, key: String = "", action: @escaping () -> Void) -> NSMenuItem {
        let item = ActionItem(title: title, action: #selector(ActionItem.run), keyEquivalent: key)
        item.target = item
        item.perform = action
        return item
    }

    /// A menu item that runs a closure.
    private final class ActionItem: NSMenuItem {
        var perform: (() -> Void)?
        @objc func run() { perform?() }
    }
}

/// The menu's first item: what plays and the transport. System label
/// colours, because a menu is system UI.
private struct StatusMenuHead: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            VStack(spacing: 0) {
                MarqueeText(text: title, font: Theme.Text.body, color: .primary, centered: true) // tokens-ok: system menu
                if !artist.isEmpty {
                    MarqueeText(text: artist, font: Theme.Text.caption, color: .secondary, centered: true) // tokens-ok: system menu
                }
            }
            HStack(spacing: Theme.Space.l) {
                TransportButton(symbol: "backward.fill", label: "Previous") { player.previous() }
                    .disabled(!player.hasTrack)
                TransportButton(symbol: player.state.isPlaying ? "pause.fill" : "play.fill",
                                label: player.state.isPlaying ? "Pause" : "Play",
                                glyph: Theme.Size.playGlyph) { player.togglePlayPause() }
                TransportButton(symbol: "forward.fill", label: "Next") { player.next() }
                    .disabled(!player.state.hasNext)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xs)
        .frame(width: Theme.Size.menuWidth)
    }

    private var title: String {
        guard player.hasTrack else { return "Nothing playing" }
        if player.state.isAd { return "Advertisement" }
        return player.state.title.isEmpty ? "Loading…" : player.state.title
    }

    private var artist: String {
        player.hasTrack && !player.state.isAd ? player.state.artist : ""
    }
}

/// The status item's icon: a record, drawn as a template so it follows the
/// menu bar's colour.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let disc = rect.insetBy(dx: 1, dy: 1)
            NSColor.black.setFill() // tokens-ok: a template image, colour comes from the menu bar
            NSBezierPath(ovalIn: disc).fill()
            NSColor.black.setStroke() // tokens-ok
            // Two grooves, cut out of the disc.
            for inset: CGFloat in [4, 6] {
                let groove = NSBezierPath(ovalIn: disc.insetBy(dx: inset, dy: inset))
                groove.lineWidth = 0.6
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                groove.stroke()
            }
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: disc.insetBy(dx: 7, dy: 7)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
