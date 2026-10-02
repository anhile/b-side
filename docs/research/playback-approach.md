# Results

This is the record of the memory spike that chose B-Side's playback approach.
Four variants were compared. **Variant D was kept; the code for A, B and C was
removed afterwards.** [ARCHITECTURE.md](../ARCHITECTURE.md) describes D.

| Variant | What it was |
|---|---|
| A. Baseline | Hidden web view with the full music.youtube.com page |
| B. Stripped | The same page with images, fonts, stylesheets and telemetry blocked |
| C. Minimal page | A local page with the official YouTube IFrame Player API |
| D. Bare player | YouTube Music's own player on an empty page, without its UI |

Target: under 200 MB total during 30 minutes of logged-in playback, with stable
memory and working Now Playing controls.

Test machine: _fill in (model, RAM, macOS version)_

## Smoke test (not the real measurement)

Taken while building, to confirm each variant plays. One track, about two
minutes, **signed out**, muted, on macOS 27.0.1 (Apple silicon). These numbers
only show the rough scale; the 30-minute signed-in runs below replace them.

| Variant | Total MB | WebContent MB | GPU MB | App MB |
|---|---|---|---|---|
| A | 485-530 | 314-322 | 84 | 46 |
| B (default rules, audio-only) | 485-527 | 277-317 | 85 | 45 |
| C | 254-264 | 145-150 | 24 | 40 |

Later runs, **signed in** with Premium, muted, about two minutes each:

| Variant | Track | Total MB | WebContent MB | GPU MB | App MB |
|---|---|---|---|---|---|
| Floor: `about:blank` in the web view | none | 91 | 14 | 11 | 38 |
| C | song | 251 | 142 | 23 | 45 |
| D, remote page (UI blocked) | song | 243 | 124 + 18 | 21 | 40 |
| D, remote page (UI blocked) | music video | 306-366 | 188 + 18 | 76 | 40 |
| D, local page | song | 170-178 | 86-88 | 15-17 | 40 |
| D, local page | music video | 191-199 | 105 | 22 | 40 |
| D, local page, 92-track radio queue | song | 189-195 | 97 | 19 | 41 |

One longer check of D (local page), 9 minutes, a 20-track playlist, signed in,
muted: average 194 MB, peak 215 MB. Tracks advanced on their own.

| Minute | Track | Total MB | WebContent MB |
|---|---|---|---|
| 0-3 | song | 175-188 | 84-88 |
| 4-7 | music video | 200-215 | 100-110 |
| 7-9 | song | 192-202 | 100-102 |

Memory rose with the music video and did not fully come back on the next
song. Nine minutes cannot tell a plateau from slow growth.

After audio-only and the leaner queue parsing were added to D, the same
playlist for 12 minutes (four songs, signed in, muted):

| Measure | Before (9 min) | After (12 min) |
|---|---|---|
| Average total MB | 194 | 173 |
| Median total MB | | 175 |
| 95th percentile MB | | 181 |
| Peak total MB | 215 | 230 |
| Peak WebContent MB | 110 | 89 |
| Samples over 200 MB | | 1 of 72 |

The peak is a short spike in the GPU process (15 MB to 67 MB) at a track
change. The app's own log caught a second one, 233 MB, in the middle of a
track. Both were gone by the next 10-second sample. Their cause is not known.

The floor matters: an empty web view already costs 91 MB across the app and
WebKit's helpers, so a player has about 109 MB to stay under the target.

## Memory

Paste rows from `./scripts/summarize.sh measurements/*.csv`.

| Variant | Samples | Avg total MB | Peak total MB | Early avg MB | Late avg MB | Growth MB | Peak WebContent MB | File |
|---|---|---|---|---|---|---|---|---|
| A | | | | | | | | |
| B | | | | | | | | |
| C | | | | | | | | |
| D | | | | | | | | |

Growth is the average of the last 5 minutes minus the average of minutes 2 to 7.

## Checklist

Fill in yes, no, or a note.

| Check | A | B | C | D |
|---|---|---|---|---|
| Plays with the window minimized and the app in the background | | | | |
| Plays with every window closed | | | | |
| Signed in (account visible in the WebView) | | | | |
| Ads appeared | | | | |
| Premium respected (no ads, high audio quality available) | | | | |
| Media keys: play/pause | | | | |
| Media keys: next / previous | | | | |
| Now Playing widget shows title, artist, artwork, position | | | | |
| Now Playing with "Native Now Playing" off (WebKit only) | | | | |
| Seeking from the Now Playing widget | | | | |
| Track with embedding disabled | n/a | n/a | | n/a |
| No crash in 30 min (`crash` in events.log) | | | | |
| No silent stop in 30 min (`STALLED` in events.log) | | | | |

## What broke

_Per variant: what failed, and for variant B which rule category caused it._

## Conclusion

_Which variant meets the target, if any._
