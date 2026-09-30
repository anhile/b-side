# B-Side as the default player instead of Apple Music

Research only, no code changes. Written 2026-09-30 on macOS 27.0.1 (build
26A434). I have no macOS 26 machine; where 26 differs from what is seen here,
it is said so, or marked unconfirmed.

## 1. Short answer

Yes, mostly, without disabling SIP. There are two layers:

1. **Be the Now Playing app** (public API, already half done). While B-Side
   is running and was the last app to play, the Play key, AirPods and Control
   Center already go to it. Adding a login item, a menu-bar-only start and
   registering at launch makes that the normal state. This does not stop Apple
   Music from launching when some other app was the last player.
2. **Stop Apple Music from starting by itself** (optional, off by default). Either
   watch for `com.apple.Music` launching, terminate it and play in B-Side
   (the noTunes approach, public API, needs no sandbox), or run a decoy process
   with Music's bundle ID (the Music Decoy approach, impersonation, fragile).

Neither layer is possible in the Mac App Store. B-Side already does not qualify
for the Store (private API, no sandbox), so the real constraint is Developer
ID signing and notarization, and both layers are compatible with those.

## 2. How it works in macOS

### Who gets the media keys

- **Hardware keys** (F7 to F9, Touch Bar, keyboards with media keys) are HID
  consumer-page events. The window server hands them to `rcd`, the Remote
  Control Daemon (`/System/Library/LaunchAgents/com.apple.rcd.plist`, Mach
  service `com.apple.rcd.media.key.events`).
- **AirPods and other Bluetooth headsets** send AVRCP commands, handled by the
  Bluetooth stack. **Control Center, the lock screen and Siri** talk to
  MediaRemote directly. None of these pass through the keyboard event stream.
  *This follows from the architecture and from the fact that event-tap tools only
  ever claim keyboard support. No Apple document states it.*
- Everything ends up in **MediaRemote** (`mediaremoted`, a private framework).
  It keeps a *Now Playing application*: the app that most recently published
  Now Playing info and a playback state. Commands go to that app's
  `MPRemoteCommandCenter` handlers.
- Apps become eligible through public API: `MPRemoteCommandCenter` (macOS
  10.12.2+) and `MPNowPlayingInfoCenter`. On macOS the app must also set
  `playbackState`: "You must set this property every time the app begins or
  halts playback, otherwise remote control functionality may not work as
  expected" ([playbackState](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter/playbackstate)).

### Why Play starts Apple Music

- When no app is Now Playing, the Play command goes to the *system media
  application*, which is Music. If Music is not running, it gets launched.
- Music Decoy's author traced this in `rcd` on macOS 14. `rcd` forwards Play
  to the app that is playing. If there is none, it checks whether any running
  process has bundle ID `com.apple.Music`: if so, it sends the command there,
  otherwise it launches Music ([Music Decoy README](https://github.com/FuzzyIdeas/MusicDecoy)).
  In June 2026 the decoy gained handlers for the Apple Events `hook/PlPs` and
  `hook/Play`, Music's scripting play/pause. That is how the command reaches
  a running "Music" ([commit list](https://github.com/FuzzyIdeas/MusicDecoy/commits/main)).
- **On macOS 27, `rcd` is only a forwarder.** Its binary has 54 strings, links
  MediaRemote and logs "MediaRemote command success". The launch logic lives
  in `mediaremoted`, which has classes `MRDNowPlayingLauncher`,
  `MRDLaunchApplicationWithReason`, a `systemMediaApplication` property and a
  *now-playing app stack* ("Failed to launch app, forwarding
  nowPlayingAppStackPopEligible command"). MediaRemote exports
  `MRMediaRemoteSetOverriddenNowPlayingApplication`,
  `MRMediaRemoteSetCanBeNowPlayingApplication`,
  `MRMediaRemoteSystemMediaApplicationWake` and
  `_MRShouldUseLegacyMusicApplicationAsSystemMediaApp`.
  *Read from local binaries with `strings` and `dyld_info`. What they do is
  inferred from their names, not confirmed.*
- **No public setting** picks the system media app on macOS. iOS has
  Settings → Apps → Default Apps, but I found no source saying that it
  covers music playback or that macOS has an equivalent. *Unconfirmed.*

### AirPods, Control Center, lock screen, Siri

- **AirPods:** with Automatic Ear Detection, taking them out pauses and
  putting them back in resumes; pressing the stem sends play/pause. With
  nothing playing, these start Music. Apple offers no setting for this
  ([Intego, July 2026](https://www.intego.com/mac-security-blog/stop-apple-music-automatically-playing/);
  [Apple Community](https://discussions.apple.com/thread/252821077)). Whether
  simply *connecting* sends Play depends on the headset. *Unconfirmed for AirPods
  on 27.*
- **Control Center and the lock screen** show the Now Playing app. With none,
  they offer Music, and its Play button launches Music. *Observed behaviour; no
  Apple document found.*
- **Siri:** "play music" goes to Music. The SiriKit media intent
  `INPlayMediaIntent` exists on iOS, watchOS, tvOS and Mac Catalyst, but not on
  native macOS ([INPlayMediaIntent](https://developer.apple.com/documentation/intents/inplaymediaintent)),
  so a Mac app cannot become Siri's music app. App Intents give a phrase
  of its own ("Play Vibe in B-Side") through `AudioPlaybackIntent`, macOS
  14+ ([AudioPlaybackIntent](https://developer.apple.com/documentation/appintents/audioplaybackintent)).

### Differences from macOS 14 and 15

- **macOS 15.4:** MediaRemote stopped working when loaded by a third-party
  app. Only processes whose bundle ID starts with `com.apple.` may use it
  ([mediaremote-adapter](https://github.com/ungive/mediaremote-adapter);
  [Keyboard Maestro forum](https://forum.keyboardmaestro.com/t/beware-upgrading-to-macos-15-4-if-you-need-now-playing-data/40285)).
  This breaks tools that *watch* who is playing, such as AntiMusic. B-Side's
  own check got pid 0 back.
- **macOS 14 and earlier:** `rcd` held the "launch Music" decision itself.
  On 27 it is in `mediaremoted` (see above). The Apple Event path that Music
  Decoy answers still works on current systems: its maintainer updated it for
  Xcode 27 in June 2026, and a user issue from June 2026 reports other players
  working alongside it.
- **macOS 26:** I found no release note changing any of this. *Unconfirmed.*

## 3. What B-Side already does

From `NowPlaying.swift`, `PlayerController.swift`, `JSBridge.swift`, `BSideApp.swift`:

- **Registration.** At launch, if the setting "Media keys and Now Playing" is
  on (the default), `NowPlaying.register()` adds handlers for play, pause,
  toggle, next, previous and seek to `MPRemoteCommandCenter`. It publishes title,
  artist, duration, position, rate and artwork, and sets `playbackState` on
  every state change.
- **Commands.** Play with nothing loaded starts Vibe (`togglePlayPause`).
- **WebKit also registers.** The hidden page's media element is also
  registered with the system by WebKit. Since commit `97b1a34`, Media Session
  handlers in the page hand WebKit's commands to the app, and duplicate presses
  are dropped. The event log records the path of each command (`remote system
  …` or `remote page …`).
- **After pause,** B-Side stays registered with `playbackState = .paused`, so it
  remains the Now Playing app and Play resumes it. With "Unload when paused" on,
  the page is dropped after N minutes, but the registration stays and Play reloads
  the page at the same position.
- **Closing the window** does not quit the app
  (`applicationShouldTerminateAfterLastWindowClosed` returns false). The menu
  bar item keeps it reachable, and keys keep working.
- **Quitting** ends the registration. The next Play then goes to whoever is on
  MediaRemote's app stack, or to Music.
- **Missing pieces:**
  - no login item;
  - the app always opens its window at launch (no menu-bar-only start);
  - it is not sandboxed and has no hardened runtime (`project.yml`:
    `ENABLE_APP_SANDBOX: NO`, `ENABLE_HARDENED_RUNTIME: NO`, ad-hoc signed);
  - nothing reacts to Music being launched.
- **At launch B-Side is not eligible** (experiment 1, below). It registers with
  `playbackState = .paused` and no track, and that is not enough: until B-Side
  has played something, Play after a fresh launch still opens Music. A moment
  of `.playing` at launch fixes this.

## 4. Existing tools and their internals

| Tool | How it works | State |
|---|---|---|
| [noTunes](https://github.com/tombonez/noTunes) | Observes `NSWorkspace.willLaunchApplicationNotification`. For `com.apple.Music` or `com.apple.iTunes` it calls `forceTerminate()`, then runs `/usr/bin/open <replacement>` if `defaults write digital.twisted.noTunes replacement …` is set. It also kills Music if it is already running at start. Menu bar icon toggles it | v3.5, July 2024; open issue about the menu bar icon on Sequoia |
| [Music Decoy](https://github.com/FuzzyIdeas/MusicDecoy) | A background-only app (`LSBackgroundOnly`) whose bundle ID *is* `com.apple.Music`. The system sees Music as running and sends Play to it instead of launching the real one. Handles the Apple Events `hook/PlPs` and `hook/Play` and an AppleScript `playpause`. It can open another app (`mediaAppPath`). It adds itself as a login item | Updated June 2026 (Xcode 27); blocks manual launches of Music; VLC crashed talking to it until a scripting fix |
| [AntiMusic](https://github.com/nift4/AntiMusic) | Keeps a *fake* Now Playing entry (title = chosen player) with play and toggle handlers, so the system never falls back to Music. Uses private MediaRemote (`MRMediaRemoteGetNowPlayingClient`, `kMRMediaRemoteNowPlayingApplicationDidChangeNotification`) to step aside when another app plays and reclaim afterwards | Two commits, December 2023, tested on 14.1 only; the private calls stopped working for third-party apps in 15.4 |
| [Mac Media Key Forwarder](https://github.com/quentinlesceller/macmediakeyforwarder), [MediaKeyTap](https://github.com/the0neyouseek/MediaKeyTap) | A `CGEventTap` on system-defined events (`NX_KEYTYPE_PLAY` and so on) that consumes the key and forwards it to a chosen player. Needs Accessibility | Keyboard only; last push to the forwarder September 2026 |
| `launchctl unload -w /System/Library/LaunchAgents/com.apple.rcd.plist` | Stops `rcd` | Kills all media keys, B-Side's too, because `rcd` is the forwarder. Not useful here |

Permissions background:
- A listen-only `CGEventTap` needs **Input Monitoring**, which even sandboxed App
  Store apps can get (`CGPreflightListenEventAccess`,
  `CGRequestListenEventAccess`). An active tap, one that can swallow the key,
  needs **Accessibility**, and "it's not possible for a sandboxed app to use the
  Accessibility privilege" (Apple DTS,
  [thread 707680](https://developer.apple.com/forums/thread/707680),
  [thread 780626](https://developer.apple.com/forums/thread/780626)).
- `NSRunningApplication.forceTerminate()`: "Sandboxed applications can't use
  this method to terminate other applications"
  ([docs](https://developer.apple.com/documentation/appkit/nsrunningapplication/forceterminate())).
- Mac App Store rules:
  - guideline 2.5.1: "Apps may only use public APIs";
  - guideline 2.4.5(iii): no auto-launch at login "without consent"
  ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
- Launch at login is `SMAppService.mainApp` (macOS 13+). The user sees it in
  Login Items and can turn it off
  ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)).

## 5. Options for B-Side

| # | Approach | What the user sees | Code (blocks) | Permissions, entitlements | Mac App Store | Risks | Size |
|---|---|---|---|---|---|---|---|
| A | **Reliable Now Playing app**: login item, start in the menu bar without a window, register at launch, claim eligibility, resume the last track on Play | After login B-Side sits in the menu bar. Play, AirPods and Control Center start B-Side's last track or Vibe. Music opens only if another player took over and then quit | `SMAppService.mainApp` toggle in Settings; a "start hidden" path; the playing→paused eligibility trick at launch; publish the last track as paused Now Playing info; remember the last track across launches | None. User approves the login item | Compatible (public API only). B-Side as a whole is not, for other reasons | Another app that plays (Spotify, a Safari tab) becomes Now Playing and keeps it until it quits or stops publishing. Whether the stack returns to B-Side then is unverified | S |
| B | **Watch and replace** (noTunes-style), on top of A | Music never stays open. If something launches it, it is killed at once and B-Side plays instead. Music's Dock icon may flash | Observer for `willLaunchApplicationNotification` and `didLaunchApplicationNotification`; `forceTerminate` of `com.apple.Music`; then `player.play()`; a "let Apple Music open" escape (see UX) | None beyond A; must not be sandboxed | Not allowed: `forceTerminate` returns false in the sandbox | Kills Music also when the user opens it on purpose; the Play press that launched Music is lost, so B-Side must play on its own; Music may flash a window; Apple could launch Music by a path that skips the notification (unverified) | S |
| C | **Decoy helper** (Music Decoy-style): a tiny background app with bundle ID `com.apple.Music` inside B-Side, as a login item. It answers `hook/PlPs` and `hook/Play` by starting or waking B-Side | Music never launches. Play with nothing Now Playing starts B-Side even when it is not running | Second target with `LSBackgroundOnly`; Apple Event handlers; wake B-Side through a URL scheme or `NSWorkspace.open`; its own login item | None, but it impersonates Apple's bundle ID | Impossible (an App ID cannot use Apple's prefix; *assumed, not tested*) | Real Music cannot start while the decoy runs; apps that script Music (VLC, Raycast, Last.fm scrobblers) may misbehave; notarization of a `com.apple.*` bundle ID is untested; Apple can change the lookup at any time | M |
| D | **Active event tap** for the Play, Next and Previous keys | Keyboard media keys always go to B-Side, even while Spotify plays | `CGEventTap` on system-defined events, swallow and forward; an Accessibility prompt and status | Accessibility (active tap). A listen-only tap (Input Monitoring) cannot stop Music | Not allowed (Accessibility unavailable in the sandbox) | Keyboard only: AirPods and Control Center still start Music; steals keys from every other player; whether swallowing stops `rcd` on 27 is unverified | M |
| E | **Private MediaRemote**: override the Now Playing or system media app (`MRMediaRemoteSetOverriddenNowPlayingApplication` and so on) | Would be the "real" default-player switch | Calls through a `com.apple.*` binary such as `/usr/bin/perl`, as mediaremote-adapter does; reverse-engineered signatures | None formally; relies on a loophole | Not allowed | Private, undocumented, blocked for third parties since 15.4; the perl route can be closed in any update; semantics unknown | L |
| F | **Disable `rcd`** | Media keys stop working entirely | — | Admin shell | — | Breaks B-Side's keys too | — |

## 6. Recommendation

1. **Do A now.** It is public API, small, and fixes the everyday case: "I pause
   B-Side, later press Play or tap an AirPod, and Music opens." It also improves
   what already exists (keys after reboot, a menu-bar-only start). All of it goes
   behind one setting, "Open at login", **off by default**. Macs have no
   first-run consent other than the Login Items approval, and App Review 2.4.5
   treats unasked auto-launch as wrong even outside the Store.
2. **Then B, as an opt-in** ("Don't let Apple Music start by itself", off by
   default, shown only with A on). It uses only public calls, needs nothing
   B-Side does not already have (no sandbox), and can be turned off from the
   menu bar. Its failure mode is mild: Music opens as it does today.
3. **Not C** unless experiments show B is unusable. Impersonating Apple's
   bundle ID is the kind of thing that breaks notarization or other apps. It also
   blocks Apple Music outright, which is a bigger promise than "default player".
4. **Not D, E, F.** D covers only keyboards and needs Accessibility. E is private
   API that Apple already closed once. F breaks the feature itself.

### UX answers

- **Optional?** Yes, both A's login item and B's guard, both off by default.
  Offer them where the user meets the problem: a line in Settings → Playback,
  "Use B-Side for the Play key and AirPods", which turns on A and then offers B.
- **Menu bar and login?** For A, yes. Keys reach B-Side only while it runs.
  The status item already exists. What is needed is start at login without the
  window, and a Dock icon only while the window is open (switching the activation
  policy between `.accessory` and `.regular`). B works only while B-Side runs,
  so it needs A.
- **The user wants Apple Music:**
  - opening Music from the Dock or Spotlight while B is on would be killed too,
    since B cannot tell a user's launch from a system one (*unverified; worth
    checking whether `NSWorkspace` gives any launch reason*);
  - so give a menu item, "Open Apple Music", that suspends the guard until Music
    quits;
  - also stand aside automatically while Music is frontmost or playing.
  - With A alone there is no conflict: Music opened by hand plays normally and
    becomes Now Playing.

## 7. Open questions and proposed experiments

All experiments go into `spikes/default-player/`, not into `Sources/`. I have
not run any of them; each needs your go-ahead, and some need your hands
(keys, AirPods).

1. **Eligibility at launch. Done 2026-09-30** on macOS 27.0.1, one F8 press
   per round, B-Side, Music and Spotify quit
   ([spike](../../spikes/default-player/README.md)):

   | Round | Command received | Music launched |
   |---|---|---|
   | baseline (no spike) | — | yes |
   | `none`: handlers only | none | yes |
   | `paused`: handlers, info, `.paused` | none | yes |
   | `playpaused`: info, `.playing`, `.paused` after 0.5 s | toggle | no |
   | `playstopped`: `.playing`, `.stopped` at once, then info | toggle | no |

   An app becomes the target of Play only after it has reported `.playing` at
   least once; `.paused` alone does not count, and neither does Now Playing
   info. The `.playing` moment can be instantaneous, and no audio is needed.
   For B-Side (option A): report `.playing` then `.paused` once at launch.
   Not tested: whether this survives a long idle period, sleep, or another app
   playing in between (that is experiment 2).
2. **App stack.** B-Side paused → Spotify or a Safari tab plays → that app quits
   or pauses → press Play. Does the command return to B-Side or start Music?
   B-Side's log shows `remote system …` if it arrives. *Needs you.*
3. **AirPods.** Connect, take out, put in, press the stem, all with B-Side paused
   and with B-Side not running. Which commands arrive (`play`, `toggle`,
   nothing), and when does Music start? *Needs you and AirPods.*
4. **Watch and replace.** A spike with noTunes' observer. Does
   `willLaunchApplicationNotification` fire for every way Music gets launched on
   27 (key, AirPods, Control Center, Siri)? How visible is the flash? Is there a
   way to tell a Dock launch from a system one? *I can run the observer; the
   triggers need you.*
5. **Decoy notarization.** Sign a `com.apple.Music` stub with a Developer ID
   and submit to notarization. Only if B turns out unusable. *Needs your Apple
   Developer account.*
6. **Event tap on 27.** Do media keys still arrive as system-defined events, and
   does swallowing them keep Music closed? Only if D is ever reconsidered.
   *Needs Accessibility approval.*
7. **Hidden system media app setting.** Look for a user default behind
   `systemMediaApplication` or `_MRShouldUseLegacyMusicApplicationAsSystemMediaApp`
   (read-only `strings` and `defaults read` of MediaRemote domains). Cheap, read
   only, and I can do it alone. Still listed because it touches system
   preferences.
8. **macOS 26 specifically:** everything above was seen on 27.0.1. If 26 support
   matters, experiments 1 to 4 should be repeated on a 26 machine.

## Sources

- Apple: [MPNowPlayingInfoCenter.playbackState](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter/playbackstate), [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter), [NSRunningApplication.forceTerminate()](https://developer.apple.com/documentation/appkit/nsrunningapplication/forceterminate()), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [CGRequestListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()), [INPlayMediaIntent](https://developer.apple.com/documentation/intents/inplaymediaintent), [AudioPlaybackIntent](https://developer.apple.com/documentation/appintents/audioplaybackintent), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Apple Developer Forums (DTS): [707680](https://developer.apple.com/forums/thread/707680), [780626](https://developer.apple.com/forums/thread/780626)
- Code: [noTunes](https://github.com/tombonez/noTunes), [Music Decoy](https://github.com/FuzzyIdeas/MusicDecoy), [AntiMusic](https://github.com/nift4/AntiMusic), [Mac Media Key Forwarder](https://github.com/quentinlesceller/macmediakeyforwarder), [MediaKeyTap](https://github.com/the0neyouseek/MediaKeyTap), [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), [WebKit MediaElementSession.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/html/MediaElementSession.cpp)
- Discussions: [Music Decoy page](https://lowtechguys.com/musicdecoy), [Keyboard Maestro forum on 15.4](https://forum.keyboardmaestro.com/t/beware-upgrading-to-macos-15-4-if-you-need-now-playing-data/40285), [Intego, July 2026](https://www.intego.com/mac-security-blog/stop-apple-music-automatically-playing/), [Apple Community 252821077](https://discussions.apple.com/thread/252821077)
- Local, read-only: `strings` of `/System/Library/CoreServices/rcd.app/Contents/MacOS/rcd` and `/System/Library/PrivateFrameworks/MediaRemote.framework/Support/mediaremoted`, `dyld_info -exports` of MediaRemote, on macOS 27.0.1 (26A434).
