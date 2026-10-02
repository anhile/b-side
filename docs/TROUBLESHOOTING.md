# Troubleshooting

The first thing to look at is the event log. Every failure is written there
with the step that failed.

```bash
tail -40 "$HOME/Library/Application Support/B-Side/events.log"
```

## The record is not in the menu bar

**With Hidden Bar, Bartender, Ice or a similar menu bar manager.** A new
app's icon appears at the left end of the icons, which is inside the
manager's hidden section.

1. Click the manager's arrow to show the hidden icons.
2. Hold Command and drag B-Side's record to the right of the arrow (or of
   the manager's divider).
3. Collapse it again.

**Hidden Bar 1.11 on macOS 27** needs one more thing known. It no longer
pushes icons off the screen: it gives macOS a list of the apps whose icons
may show, and it makes that list at the moment it collapses, from the apps
running then. An app that was not running at that moment stays hidden when it
starts later, wherever its icon is. So if the record is missing after a
login or after B-Side was started again, click Hidden Bar's arrow twice:
expand, then collapse. (This is from reading Hidden Bar's source; B-Side
cannot add itself to another app's list.)

**Without a manager.** macOS 26 and later can hide an app's icon: System
Settings, Menu Bar, and allow B-Side there.

The log says what B-Side sees. `allowed in the menu bar` is the system's own
switch; `x 0` while a manager is collapsed means the icon is hidden:

```bash
grep "	status	" "$HOME/Library/Application Support/B-Side/events.log" | tail -3
```

## "The player did not start", or the welcome screen stays

- Check the connection, then **Try Again**.
- If it never starts and the log has a line that begins `error	boot:`,
  YouTube Music has probably changed its page. Look for an update of B-Side;
  for a fix, see the last section.

## Nothing plays, or it stops after a track

Look for `error	load:`, `error	queue refill:` or `STALLED` in the log.

- A track or playlist may be unavailable in your country or private.
- `STALLED` means the player said it was playing but the position did not
  move for a minute. Pause and play, or pick the track again.

## Playlists or Liked Music are empty

You are signed out, or signed in to a different Google account than you
think: Settings, Account shows which. Liked Music and your playlists need an
account; search, albums and radios work without one.

## Sign-in fails

Google sometimes refuses to sign in inside an app's window ("This browser or
app may not be secure"). Try again after a minute. B-Side presents itself as
Safari for this reason; if Google still refuses, open an issue with the
message it showed.

## The Play key or AirPods start Apple Music

macOS sends Play to the app that played last, and opens Music when none is
running. Turn on **Open at login** in Settings, General: B-Side then waits in
the menu bar and takes the key. Details:
[research/default-player.md](research/default-player.md).

## Ads

B-Side plays through Google's player and does not remove ads. Without
YouTube Premium you hear them; B-Side shows "Advertisement" and when the
music comes back.

## Lyrics are missing or out of step

Timings come from YouTube Music, or from LRCLIB when it has none; when
neither has them, the plain text is shown, and some tracks have no lyrics at
all. Timings from LRCLIB are made by volunteers and can be off.

## Vibes from words give odd music

- On the Mac, the words are read by Apple's on-device model, which knows
  well-known genres and little else. Name a genre, an artist or a place.
- For more, turn on **Read vibes on the B-Side server** in Settings, Vibes.
  It is limited to 10 vibes a month for each Mac; when they are used, the Mac
  reads the words again.
- In the preview, take out what does not fit (the x on a chip) and B-Side
  finds the songs again.

## After a YouTube Music change

B-Side depends on names inside YouTube Music's web player. When one changes,
a part of B-Side stops. The names are in one place: the block marked
`ADJUST HERE` at the top of
[player.js](../Sources/BSide/Resources/player.js). The log line that failed
(`boot:`, `load:`, `playlists:`, `search:`) says which part to look at, and
[ARCHITECTURE.md](ARCHITECTURE.md) says how the parts fit.
