import AppKit
import SwiftUI

/// The record in the menu bar and its menu, in AppKit so the first item can
/// be a real view: artwork, the title scrolling when long, and the transport
/// buttons. The rest are ordinary items, rebuilt each time the menu opens.
/// Nothing runs while the menu is closed.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    static let shared = StatusMenu()

    private var item: NSStatusItem?
    private let menu = NSMenu()
    private weak var player: PlayerController?
    private var openMain: (() -> Void)?

    func install(player: PlayerController, openMain: @escaping () -> Void) {
        self.player = player
        self.openMain = openMain
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.image
        item.button?.toolTip = "B-Side"
        item.menu = menu
        menu.delegate = self
        self.item = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let player else { return }
        menu.removeAllItems()

        let head = NSMenuItem()
        let view = NSHostingView(rootView: StatusMenuHead().environmentObject(player))
        view.frame.size = view.fittingSize
        head.view = view
        menu.addItem(head)
        menu.addItem(.separator())

        let vibe = NSMenuItem(title: "Vibe", action: nil, keyEquivalent: "")
        vibe.submenu = NSMenu(title: "Vibe")
        for mood in player.moods {
            vibe.submenu?.addItem(Self.item(mood.name) { [weak player] in player?.play(mood) })
        }
        vibe.isEnabled = player.account.isSignedIn
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
        menu.addItem(Self.item("Settings…", key: ",") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
            HStack(spacing: Theme.Space.xs) {
                Artwork(url: player.state.artworkURL, size: Theme.Size.artworkSmall)
                VStack(alignment: .leading, spacing: 0) {
                    MarqueeText(text: title, font: Theme.Text.body, color: .primary) // tokens-ok: system menu
                    if !artist.isEmpty {
                        MarqueeText(text: artist, font: Theme.Text.caption, color: .secondary) // tokens-ok: system menu
                    }
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
