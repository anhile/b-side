# Development

Building, running and checking B-Side. How the code is laid out is in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Build

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). There are no other dependencies. The Xcode project
is generated from [project.yml](../project.yml) and is not in the repository.

```bash
./scripts/build.sh
```

The app lands in `build/Build/Products/Release/B-Side.app`. The script uses
`/Applications/Xcode.app` directly if `xcode-select` still points at the
Command Line Tools.

```bash
open build/Build/Products/Release/B-Side.app
```

To work in Xcode, run `xcodegen generate` and open `BSide.xcodeproj`. New
files under `Sources/BSide` are picked up when the project is generated
again.

## Checks before a change is done

There is no unit test target. A change is checked in three ways.

**1. The design check.** Fails on raw colours, fonts, spacing and sizes in
the views; see [DESIGN.md](../DESIGN.md), Enforcement.

```bash
./scripts/check-design.sh
```

**2. Snapshots.** The app renders every page in every state, light and dark,
with fixture data, into a folder and quits. It runs next to your own copy of
B-Side and touches neither the player nor your settings.

```bash
build/Build/Products/Release/B-Side.app/Contents/MacOS/B-Side -snapshot /tmp/b-side-shots
```

- Render before and after a change and compare the files. A change that
  should not alter a screen leaves its file the same byte for byte. Only the
  animated states differ between runs (`explore-empty-*`, `explore-loading`,
  the loading skeletons, `settings-diagnostics-*`, `settings-vibes-*`).
- A new state of a screen gets a fixture in
  [Snapshots.swift](../Sources/BSide/Design/Snapshots.swift).
- The reviewed set is kept in `design/audit/`; update the files a change
  alters.
- Snapshots do not show glass, edge fades or animation: check those in the
  running app.

**3. A muted run and the event log.** Playback is checked without the screen:
start the app muted with launch arguments, then read what it did.

```bash
build/Build/Products/Release/B-Side.app/Contents/MacOS/B-Side -muted YES -listTracks LM -playTrack 0
```

```bash
tail -30 "$HOME/Library/Application Support/B-Side/events.log"
```

Quit your own copy of B-Side first: two copies would both claim the media
keys. For a change to player.js, also run `node --check` on it; a syntax
error there stops the whole player.

## Launch arguments

Every setting can be given as a launch argument (`-name value`), and some
exist only as arguments:

| Argument | Effect |
|---|---|
| `-vibe YES` | Starts the first vibe at launch |
| `-play <id or URL>` | Starts a video ID, playlist ID, or URL at launch. `LM` is Liked Music |
| `-startIndex 48` | Starts a playlist at this track, counting from 0 |
| `-resume YES` | Presses Play on the track restored from the last session |
| `-startHidden YES` | Starts in the menu bar without the window, as a login launch does |
| `-muted YES` | Mutes the player; decoding still runs, so memory is comparable |
| `-volume 30` | Volume at launch, 0 to 100 |
| `-forceAudioOnly NO` | Plays videos at normal quality, for comparison |
| `-page explore` | Opens the window on this page: `nowPlaying`, `vibe`, `playlists`, `explore` |
| `-listTracks LM` | Opens this playlist's track list at launch |
| `-playTrack 3` | With `-listTracks`, plays the list from this track, counting from 0 |
| `-makeVibe "<words>"` | Makes a vibe from these words once the page is ready, and writes it to the log |
| `-vibeServerURL <url>` | Reads vibes on the server at this address, e.g. `http://localhost:3000` |
| `-url <url>` | Loads this URL instead of the player page (`about:blank` measures the floor) |
| `-snapshot <folder>` | Renders every page and state as PNG into the folder and quits |
| `-snapshotOnly <words>` | With `-snapshot`: only the pages whose file name has the words in it |
| `-ApplePersistenceIgnoreState YES` | macOS: skips the "restore windows?" prompt after a killed run |

The full list, with the stored settings, is in
[Settings.swift](../Sources/BSide/App/Settings.swift).

## Files the app writes

| Path | Content |
|---|---|
| `~/Library/Application Support/B-Side/events.log` | Track changes, play and pause, ads, errors, crashes, and a heartbeat per minute |
| `~/Library/Application Support/B-Side/processes.tsv` | The processes that belong to the app, refreshed every 5 s while it runs |
| Preferences, `dev.bside.spike` | Settings, the Vibe tiles, the last session |
| WebKit's data store | The Google session: cookies and site data, as in a browser |

The event log is the first place to look when something fails. Each line is a
time, a kind and details, separated by tabs. A `STALLED` line means the
player claimed to be playing but its position did not move for a minute.

The bundle identifier still ends in `.spike`. WebKit keys the cookie store on
it, so changing it signs every user out; it stays until a release decides
otherwise.

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

`measure.sh` writes one row per process every 10 seconds:
`timestamp,variant,process,MB,total_MB,pid`.

- **MB** is `phys_footprint`, the number in Activity Monitor's Memory
  column. If `footprint` fails, the script falls back to RSS and warns,
  because RSS is not comparable.
- **Which processes count.** WebKit's helpers are started by launchd, so
  they are not children of the app. The app asks the kernel which processes
  it is responsible for and writes the list to `processes.tsv`; the script
  reads it.
- The `variant` column is always `D`: the approach that was kept. See
  [research/playback-approach.md](research/playback-approach.md).

Settings, Diagnostics shows the same numbers live. Do not attach Web
Inspector during a run.

## The server

The optional vibe server is a separate small project in
[server/](../server/), with its own [README](../server/README.md): how to run
it locally, deploy your own, and compare models. To point the app at a local
one:

```bash
build/Build/Products/Release/B-Side.app/Contents/MacOS/B-Side -muted YES -vibeServerURL http://localhost:3000 -makeVibe "rainy Sunday, slow jazz"
```
