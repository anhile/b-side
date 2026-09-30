# B-Side

B-Side is a lightweight YouTube Music client for macOS. It plays through
Google's own player in a hidden `WKWebView` and uses about 175 MB in total,
against roughly 500 MB for the full YouTube Music page.

- How it should look and behave: [DESIGN.md](DESIGN.md)
- How the playback approach was chosen, with measurements: [RESULTS.md](RESULTS.md)

## How playback works

The YouTube Music UI is a 4.8 MB script that costs about 300 MB once running.
B-Side never loads it:

1. The web view loads an empty local document whose base URL is
   `https://music.youtube.com/`, so it has that origin and your cookies.
2. [player.js](Sources/BSide/Resources/player.js) fetches the real home page as
   text and reads the player configuration (`ytcfg`) out of it.
3. It loads the player script that configuration names and creates a player
   with `yt.player.Application.create`.
4. Tracks are started with the player's `loadVideoById`. Google's player does
   everything about streams: signatures, tokens, sign-in, Premium.

With no UI there is no queue, so player.js keeps one. It asks
`/youtubei/v1/next` for a playlist's tracks, or for a single track's radio, and
advances when a track ends.

- **Audio only** (on by default). Many tracks exist both as a song and as a
  music video. player.js plays the song version. A video that has no song
  version is played at 144p. The event log says which happened, per track.
- **Private playlists.** Requests carry the `SAPISIDHASH` header computed from
  your cookie, as the YouTube Music UI does.
- **Long playlists** arrive about 50 tracks at a time. The next page is fetched
  three tracks before the end of what is loaded.
- **Shuffle** is done by the server: the queue request carries the same
  `params` value the YouTube Music UI sends for "Shuffle play".

**This is fragile by nature.** It depends on `ytcfg` key names, the `create`
call and the shape of the queue response. None of it is documented, and a
YouTube Music release can break any of it. The event log shows which step
failed (`boot:`, `load:`, `playlists:`, `queue refill:`).

## The app

A 320 by 440 window with three pages, designed as in [DESIGN.md](DESIGN.md).

| Where | What it does |
|---|---|
| **Vibe** page | Your mood tiles in two columns. A tile plays a playlist (in order or shuffled), Liked Music shuffled, or the radio of a track. The plus tile adds one; right-click edits or removes |
| **Playlists** page | Your playlists, private ones included. Click one to play it |
| **Now Playing** page | Artwork with the record behind it, title, artist, position, volume, Previous, Play or Pause, Next |
| Strip under Vibe and Playlists | The current track (scrolls when long), Pause and Next; click it to open Now Playing |
| Icons at the top right | Now Playing, Vibe, Playlists |
| Menu bar record or Command-comma | Settings: Account, Playback, Diagnostics |

Move between the pages with a two-finger swipe, the icons at the top right,
or Command-1 (Now Playing), Command-2 (Vibe) and Command-3 (Playlists). With Reduce Motion on, pages cross-fade
and the swipe is off.

| Shortcut | Action |
|---|---|
| Space | Play or pause. With nothing loaded it starts Vibe |
| Command-Right, Command-Left | Next, previous |
| Command-L | Like the track, or take the like back |
| Shift-Command-V | Play Vibe |
| Command-Up, Command-Down | Volume up, down |
| Option-Command-Down | Mute, unmute |
| Command-comma | Settings |

Closing the window does not stop the music. The record in the menu bar shows
the track (scrolling when long) with Previous, Play or Pause and Next, lists
every Vibe tile and playlist, and brings the window back.
The window is dragged by the empty strip at the top.

**Open at login** (Settings, Playback; off by default) starts B-Side in the
menu bar, without its window or Dock icon. The Play key and AirPods then
start B-Side instead of Apple Music: the system sends Play only to a running
app, and with none it opens Music. Show B-Side in the menu, or opening the app
again, brings the window back. Until then the player page is not loaded
(about 40 MB instead of 130): the first Play, the window or the menu loads it,
which takes a few seconds behind a welcome screen. Why and how this was measured:
[docs/research/default-player.md](docs/research/default-player.md).

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). No other dependencies.

```bash
./scripts/build.sh
```

The app lands in `build/Build/Products/Release/B-Side.app`. The script uses
`/Applications/Xcode.app` directly if `xcode-select` still points at the
Command Line Tools.

## Run

```bash
open build/Build/Products/Release/B-Side.app
```

Sign in once: click **Sign In…**, then log in to Google in the window that
appears. The window closes by itself when Google sends you back to YouTube
Music.

Launch arguments, for scripted runs:

| Argument | Effect |
|---|---|
| `-vibe YES` | Starts Vibe at launch: Liked Music, shuffled |
| `-startHidden YES` | Starts in the menu bar without the window, as a login launch does |
| `-play <id or URL>` | Starts playing a video ID, playlist ID, or URL at launch. `LM` is Liked Music |
| `-volume 30` | Volume at launch, 0 to 100 |
| `-muted YES` | Mutes the player; decoding still runs, so memory is comparable |
| `-startIndex 48` | Starts a playlist at this track, counting from 0 |
| `-forceAudioOnly NO` | Plays videos at normal quality, for comparison |
| `-url <url>` | Debug: loads this URL instead of the player page (`about:blank` measures the floor) |
| `-snapshot <folder>` | Renders every page in its states, light and dark, as PNG into the folder and quits. For design review |
| `-ApplePersistenceIgnoreState YES` | macOS: skips the "restore windows?" prompt after a killed test run |

## Measuring memory

```bash
open build/Build/Products/Release/B-Side.app --args -play <playlist-id>
```

```bash
./scripts/measure.sh 30
```

```bash
./scripts/summarize.sh measurements/*.csv
```

Then read the event log for stops and crashes:

```bash
grep -e STALLED -e crash -e error "$HOME/Library/Application Support/B-Side/events.log"
```

Do not open the player page (Settings, Diagnostics) or attach Web Inspector
during a run.

## What gets measured

`scripts/measure.sh` writes one row per process every 10 seconds:

```
timestamp,variant,process,MB,total_MB,pid
```

The `variant` column is always `D`: the spike compared four approaches, A to
D, and D is the one in this repository.

- **MB** is `phys_footprint` from `footprint`, the number in Activity Monitor's
  Memory column. If `footprint` fails, the script falls back to `ps -o rss` and
  prints a warning, because RSS is not comparable.
- **total_MB** is the sum over all processes in that sample.
- **Which processes count.** WebKit's helpers are started by launchd, so they
  are not children of the app. The app asks the kernel which processes it is
  responsible for and writes the list to
  `~/Library/Application Support/B-Side/processes.tsv`; the script reads it.
  This finds more than WebContent, Networking and GPU: it also includes
  helpers such as `com.apple.audio.SandboxHelper`.
  They are real cost, so they are in the total.

Settings, Diagnostics shows the same numbers live.

## Files the app writes

| Path | Content |
|---|---|
| `~/Library/Application Support/B-Side/processes.tsv` | Current variant and process list, refreshed every 5 s |
| `~/Library/Application Support/B-Side/events.log` | Track changes, play/pause, ads, errors, crashes, and a heartbeat per minute |

A `STALLED` line in the event log means the player claimed to be playing but
its position did not advance for a minute.

## Where to adjust things

| What | File |
|---|---|
| Config keys, endpoints, player method names, auth cookies | [player.js](Sources/BSide/Resources/player.js), block marked `ADJUST HERE` |
| Blocked resource types and URL patterns, media exception | [ContentRules.swift](Sources/BSide/ContentRules.swift), block marked `ADJUST HERE` |
| User agent, sign-in URL, hidden-view scheduling, Web Inspector | [Tuning.swift](Sources/BSide/Tuning.swift) |
| Window size, spacing, radii, control sizes | [Theme.swift](Sources/BSide/Design/Theme.swift) |

## Scope

Playback goes through Google's own player in the web view. This project does
not extract streams, decipher signatures, or reimplement any of that.
