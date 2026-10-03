# Privacy

B-Side has no accounts of its own, no analytics and no crash reporting. This
page lists everything that leaves your Mac and everything that is kept on it.

## What leaves your Mac

| To | What | When |
|---|---|---|
| **Google** (`music.youtube.com`, `googlevideo.com`, `ytimg.com`, `accounts.google.com`) | What a browser with YouTube Music open would send: your Google session, what you play, search, like and add to playlists | Always; this is the player |
| **LRCLIB** (`lrclib.net`) | The title, artist and length of the current track | Only when you open Lyrics and YouTube Music has no timed lyrics for the track |
| **The B-Side server** (`api.b-side.anhile.com`, or the address you set) | The words of a new vibe, the artists' mix you chose, and a random ID made once on this Mac | Only if you turn on "Read vibes on the B-Side server" in Settings, Vibes. Off by default |
| **Apple** | Nothing from B-Side. With the server off, vibes are read by Apple's on-device model, on this Mac | |

Plays reach your YouTube Music history, as in a browser: B-Side does not
block the player's own playback reports. It does block analytics and
advertising-measurement requests that the page would otherwise make (the
list is in
[ContentRules.swift](Sources/BSide/Player/ContentRules.swift)).

### The B-Side server

- The words are not stored. The same words are answered from a cache for
  7 days; the cache key is a hash of the words, and the value is what they
  were read as (a name, genres, artists).
- The random ID only counts this Mac's vibes for the month. It is not tied
  to your Google account, which the server never sees.
- Your address is used for a rate limit and kept only as a hash, for ten
  minutes.
- The server passes the words to a language model through Vercel AI Gateway.
  Its code is in [server/](server/); you can run your own and point B-Side
  at it.

## What is kept on your Mac

| Where | What |
|---|---|
| WebKit's data store for B-Side | Your Google session (cookies, site data), as a browser keeps it. Sign Out in Settings, Account removes it |
| Preferences (`com.anhile.bside`) | Settings, your Vibe tiles with the words they were made from, the last track and where it stopped, the random server ID |
| `~/Library/Application Support/B-Side/events.log` | A diagnostic log: track changes, play and pause, errors, what a new vibe was read as, memory once a minute. No account name, no search queries. It is never sent anywhere |

To remove everything: sign out in Settings, quit B-Side, then delete the
app, `~/Library/Application Support/B-Side` and
`~/Library/Preferences/com.anhile.bside.plist`.

## Permissions

- **Notifications**, only if you turn on "Notify when a track starts".
- **Login item**, only if you turn on "Open at login".
- **Bluetooth**, only if you choose "Connect a Bluetooth Device…" under
  Sound Output. B-Side then reads the names of your paired speakers and
  headphones, to list them and to connect the one you pick. Nothing about
  them leaves your Mac.

B-Side asks for nothing else: no microphone, no files, no contacts, no
Accessibility.
