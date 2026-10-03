# Architecture

How B-Side is put together, for someone about to change it. What it should
look like is in [DESIGN.md](../DESIGN.md); why it is built this way is in
[research/](research/).

## The idea

YouTube Music's web interface is a 4.8 MB script that costs about 300 MB of
memory once it runs. B-Side never loads it. It loads only Google's player,
on an empty page, and draws its own interface in SwiftUI.

```
 SwiftUI views ──read──▶ PlayerController ──call──▶ JSBridge ──▶ player.js ──▶ Google's player
      ▲                        │   ▲                              │                and
      └──── @Published ────────┘   └────── messages ──────────────┘         YouTube Music's API
```

1. A hidden `WKWebView` loads an empty document whose base URL is
   `https://music.youtube.com/`. It has that origin, so it has the user's
   cookies and may call YouTube Music's own endpoints.
2. [player.js](../Sources/BSide/Resources/player.js) fetches the real home
   page as text and reads the player configuration (`ytcfg`) out of it.
3. It loads the player script that configuration names and creates a player
   with `yt.player.Application.create`.
4. Tracks start with the player's `loadVideoById`. Google's player does
   everything about streams: signatures, tokens, sign-in, Premium, ads.

B-Side does not extract streams, decipher signatures or download anything.

**This is fragile by nature.** It depends on `ytcfg` key names, the `create`
call and the shapes of YouTube Music's responses. None of it is documented.
Every name that may change is at the top of player.js, in the block marked
`ADJUST HERE`, and every failure is written to the event log with the step
that failed (`boot:`, `load:`, `playlists:`, `queue refill:`).

## The page: player.js

One file, one closure, no dependencies. Because the interface is not there,
it does what the interface would:

| Part | What it does |
|---|---|
| Boot | Reads `ytcfg`, loads the player script, creates the player, reports `ready` |
| Requests | `api()` posts to `/youtubei/v1/…` with the `SAPISIDHASH` header computed from the user's cookie, as the web interface does. `cut()` parses only the parts of a response that are needed: a whole response costs about 20 MB of heap |
| Queue | Keeps the queue the interface would keep: a playlist's tracks or a track's radio from `/next`, about 50 at a time, the next page fetched three tracks before the end. Shuffle is the server's, by the same `params` the interface sends. Advances when a track ends; repeat off, all, one |
| Audio only | A track often exists as a song and as a music video. The song version is played; a video without one plays at the lowest quality |
| Library | Playlists, a playlist's tracks, creating playlists, adding and removing tracks, which playlists hold a track, likes |
| Explore | Search by kind, artist pages, album and playlist pages |
| Lyrics | The plain text and the ID of the lyrics page; the app asks for timings itself |
| Reports | `state` after every media event and every few seconds; `upNext` when the queue moves; `event` lines for the log |

The app calls it through `window.__bside`; it answers with
`webkit.messageHandlers` messages.

[ContentRules.swift](../Sources/BSide/Player/ContentRules.swift) keeps the
page from loading images, fonts, stylesheets and telemetry: nothing of the
page is ever shown.

## The app

| Folder | What is in it |
|---|---|
| `App/` | The app and its scenes, the window's life (`MainWindow`), navigation between pages, settings keys, tuning constants, Open at login |
| `Player/` | `PlayerController`, the bridge to the page, the playback clock, Now Playing and media keys, track notifications, timed lyrics, the last session |
| `Models/` | What the page sends, as values: `PlayerState`, `Track`, `MusicItem`, `Playlist`, pages of Explore, `Lyrics`; a Vibe tile (`Mood`) and a vibe being made (`VibeSpec`) |
| `Vibes/` | Vibes from words: `VibeMaker` reads the words and finds the songs, `VibeServer` talks to the optional server |
| `Views/` | One folder per page (`NowPlaying`, `Vibe`, `Playlists`, `Explore`), the window around them (`Window`), `Settings`, `MenuBar`, and the shared `Components` |
| `Design/` | Tokens (`Theme`), glass, the record, artwork loading and tint, the vibe palette, and `Snapshots` |
| `Diagnostics/` | The event log, the process list, and the debug tools: window captures, the proxy |
| `Resources/` | player.js |

Beside `Sources/BSide`: `Sources/Shared` is compiled into the app and the
widget extension both (what the widget shows, its buttons' intents, the
message port), and `Sources/BSideWidget` is the extension itself.

### PlayerController

The one object the views read. It owns the web view and holds everything
they show as `@Published private(set)` state: what plays, the queue, the
library, Explore's results, lyrics. Views call its methods; only it writes
its state. That is why it is one long file: Swift's `private(set)` ends at
the file, and splitting the class would open its state to the views.

- **Commands** go to the page with `bridge.call` (no answer) or
  `bridge.value` (awaits what the page returns).
- **Messages** from the page arrive in `JSBridge`, are decoded into models,
  and reach the controller through its `on…` callbacks.
- **Optimism.** Play, Pause, Like and Seek show at once; the page's next
  report confirms. `expected` keeps a late report from flipping the button
  back.
- **The clock.** The page reports the position every few seconds;
  `PlaybackClock` runs it forward in between, so the progress bar and lyrics
  need no timer in the page.
- **Phases.** `asleep` (started in the menu bar, page not loaded: about
  40 MB), `starting`, `ready`, `failed`. The first Play, the window or the
  menu wakes it.
- **Resuming.** `unloaded` holds a track that is shown but not loaded: after
  "unload when paused", and at launch from `LastSession`. Play loads it at
  its position, inside the list it came from.

### The system around playback

- [NowPlaying.swift](../Sources/BSide/Player/NowPlaying.swift): Control
  Center, media keys and AirPods through `MPNowPlayingInfoCenter` and
  `MPRemoteCommandCenter`. WebKit also registers the playing element, so the
  page forwards its own Media Session actions to the app, and the
  controller drops the second copy of a key press. See
  [research/default-player.md](research/default-player.md).
- [TimedLyrics.swift](../Sources/BSide/Player/TimedLyrics.swift): timings
  from YouTube Music, then LRCLIB. See
  [research/live-lyrics.md](research/live-lyrics.md).
- [LoginItem.swift](../Sources/BSide/App/LoginItem.swift): Open at login
  through `SMAppService`.

### Views and design

Every screen reads tokens from
[Theme.swift](../Sources/BSide/Design/Theme.swift) and colours from the asset
catalog; `scripts/check-design.sh` fails on raw values. Settings keeps the
system look and is exempt. Parts drawn by hand instead of system controls
are marked `CUSTOM:` in their comment, with the reason.

The window is three pages side by side in a paging scroll view, a glass bar
on top and the strip with the current track at the bottom.
[design/SCREENS.md](../design/SCREENS.md) has one spec per screen.

Every size in Theme is multiplied by `Theme.scale`, 1 to 1.3: the window
drags between the Compact and Large sizes, keeping its shape. A layout
exists for one scale only, so while the corner is dragged the content is
scaled as a picture, and when the drag ends `WindowSize` stores the new
scale and the window's content is built again at it (`.id` in BSideApp).
Settings' Compact and Large take the window to either end the same way.

`Snapshots.swift` renders every page in every state with fixture data,
without the player. That is how a change is checked without clicking through
the app; see [DEVELOPMENT.md](DEVELOPMENT.md).

### Vibes from words

1. **Read.** The words become a name, genres, artists and "vocals or not":
   by the B-Side server when the user turned it on, else by Apple's
   on-device model, else by matching YouTube Music's own moods.
2. **Check.** Every artist is searched on YouTube Music and kept only when a
   result credits exactly that name. Models invent artists; search does not.
3. **Seed.** The found songs become the tile's anchors. The tile plays the
   radio of one of them, a different one each time.

The server ([server/](../server/)) only reads words. It never sees the
user's account, and the app works without it. Its plan and limits:
[plans/vibe-server.md](plans/vibe-server.md).

## The desktop widget

`BSideWidget.appex`, embedded in the app, shows what plays (small: the
artwork with the names and Play on it; medium: artwork, source, names and
the transport). It is sandboxed, as extensions are, and reads nothing from
disk: when WidgetKit asks for a timeline, the extension asks the running app
over a `CFMessagePort` (`WidgetPort`, name `com.anhile.bside.widget`) and
gets the state with a small JPEG of the artwork. Its buttons are App
Intents that send a command back over the same port, or open the app by
`bside://<command>` when it is not running. The app (`WidgetFeed`) answers
the port and asks WidgetKit to redraw a second after what plays changes.

No shared group container: on recent macOS, access to one needs the group
ID to start with a Team ID, and B-Side is signed without one. The widget's
entitlements (the sandbox, and a mach-lookup exception for the port's name)
cannot be signed in by Xcode without a provisioning profile, so
`scripts/build.sh` and `scripts/release.sh` sign the extension again with
`Support/BSideWidget.entitlements`.

## Where to adjust things

| What | File |
|---|---|
| Config keys, endpoints, player method names, auth cookies | [player.js](../Sources/BSide/Resources/player.js), block marked `ADJUST HERE` |
| Blocked resource types and URL patterns | [ContentRules.swift](../Sources/BSide/Player/ContentRules.swift), block marked `ADJUST HERE` |
| User agent, sign-in URL, timeouts, cache sizes | [Tuning.swift](../Sources/BSide/App/Tuning.swift) |
| Settings keys and launch arguments | [Settings.swift](../Sources/BSide/App/Settings.swift) |
| Window size, spacing, radii, control sizes, motion | [Theme.swift](../Sources/BSide/Design/Theme.swift) |
| Colours | `Sources/BSide/Assets.xcassets/Colors` |
