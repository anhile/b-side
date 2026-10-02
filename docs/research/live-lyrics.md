# Live (time-synced) lyrics in B-Side

Research only, no code changes. Written 2026-09-30. Experiments 1 and 3 were
run the same day; their results are in section 8. The spike's code was in
`spikes/live-lyrics/`, removed before the release; it is in the git history,
at commit `e72e39d`.

## 1. Short answer

Two sources are worth building on. Both are cheap enough to run on demand:

1. **YouTube Music's own timed lyrics.** The same lyrics page B-Side already
   opens (`MPLYt…` from the track's `/next`) carries per-line timestamps when
   it is asked for as the Android app (`ANDROID_MUSIC` client). The web client
   gets only plain text, which is why B-Side shows plain text today. It is the
   same catalogue and the same `videoId`, so no matching is needed. It has the
   same Musixmatch/LyricFind licence line the web page shows.
2. **LRCLIB** (lrclib.net) as a fallback. It is a free, open, crowd-sourced
   database of LRC files, with a public API, no key and no account. It is
   matched by title, artist, album and duration, so it can miss or pick a
   different edit of the song.

B-Side would show the timed lines when either source has them, and the plain
text it has today otherwise. The syncing itself costs next to nothing: the
app already knows the playback position without asking the page (section 4).

Not recommended: Musixmatch's unofficial API (it needs a token taken from their
app, and their terms forbid it), Apple Music, Spotify and QQ (the same kind of
problem, and the lyrics come from other catalogues), and the syllable-level
community sources Better Lyrics uses (they are small and tied to that project).

## 2. What exists today

| Where | Timed lyrics | How |
|---|---|---|
| YouTube Music on Android and iOS | Yes, line by line | `browse` on the `MPLYt…` page as the mobile client returns `timedLyricsModel` |
| YouTube Music on the web | No, plain text | The same page as `WEB_REMIX` returns `musicDescriptionShelfRenderer` |
| B-Side now | No, plain text | The web way, in `player.js` `lyrics()` |
| ytmusicapi (Python, MIT) | Yes, `get_lyrics(browseId, timestamps=True)` | Switches to `ANDROID_MUSIC` `7.21.50` for that one request |
| ytmdesktop, PR #1666 (still open) | Yes | The same Android endpoints, found by hooking the app's network stack |
| Better Lyrics (browser extension, GPLv3) | Yes, some syllable-level | Its own server and community sources, Musixmatch, LRCLIB, YouTube captions |
| YouLy+, syncedlyrics and similar | Yes | Musixmatch, LRCLIB, NetEase, Apple Music, QQ |

Every desktop YouTube Music client that has timed lyrics gets them from outside
the web client. Google does not offer them there.

## 3. The two sources in detail

### YouTube Music, as the Android client

- **Request.** First `next` with `{videoId}`: B-Side already does this and
  takes `"browseId":"MPLYt…"` from the reply. Then `browse` with `{browseId}`,
  with the request's `context.client` set to `clientName: ANDROID_MUSIC` and a
  client version (ytmusicapi uses `7.21.50`). ytmusicapi sends it without
  signing in.
- **Reply.** The timed lyrics are at
  `contents.elementRenderer.newElement.type.componentType.model.timedLyricsModel.lyricsData`.
  `timedLyricsData` is a list of `{lyricLine, cueRange: {startTimeMilliseconds,
  endTimeMilliseconds}, …}`, and `sourceMessage` is the licence line. When the
  track has only plain lyrics, `timedLyricsData` is missing, and the plain text
  is elsewhere in the same reply.
- **Strengths.** The timings belong to the exact recording that plays, so no
  matching or offset guessing is needed. It covers the same tracks the Android
  app shows lyrics for. It is one extra request, and B-Side already makes it.
- **Risks.**
  - It impersonates the Android app for one call. B-Side's principle so far is
    to use Google's own web player and the web client's own requests. This
    would be the first request that pretends to be something else.
  - Google can stop accepting an old client version, or start asking mobile
    clients for attestation, as it has for the video player endpoints. `browse`
    has not needed attestation so far (unconfirmed for 2026).
  - Whether it answers the same way from inside the page (with the web
    session's cookies and `X-Goog-AuthUser`) or has to be sent from Swift
    without cookies is not known. See experiment 1.

### LRCLIB

- **Request.** `GET https://lrclib.net/api/get?track_name=…&artist_name=…&album_name=…&duration=…`,
  with the duration in seconds. There is also `/api/get-cached`, which is served
  only from their database and never looks further, and a looser `/api/search?q=…`.
- **Reply.** JSON with `syncedLyrics` (LRC: `[mm:ss.xx] line`), `plainLyrics`
  and `instrumental`. Or 404.
- **Terms.** No key and no account. They ask for a `User-Agent` that names the
  app and its homepage. The database is community-submitted and published as a
  dump. The code is open source. The lyrics themselves have no clear licence,
  which is the same grey area as every LRC site.
- **Strengths.** Independent of Google. It is often timed for the album
  version. It is plain HTTP from Swift with nothing to spoof.
- **Risks.**
  - It is matched by metadata. YouTube Music titles carry "(feat. …)",
    "(Official Video)", "- Remastered 2011" and the like. The artist line can be
    "A & B" or "A, B". Music videos have intros that the album version does
    not, which shifts every line by a constant amount.
  - The duration match is strict (reportedly within about 2 seconds, to be
    confirmed). That is good against wrong edits, but it misses when the video
    is longer than the song.
  - Coverage outside English-language pop, for Russian among others, is unknown.
  - It is a volunteer service, so B-Side should ask for each track only once
    and keep the answer.

## 4. Syncing to playback, and what it costs

- **Position.** `PlayerController.position(at:)` already extrapolates the
  playback position from the last state report and its time, so the Now
  Playing progress bar moves without asking the page. The lyrics can use the
  same clock. Reports come on play, pause, seek and track change, so drift
  resets on each of them. How far it drifts over a whole track needs a
  measurement (experiment 2), but the progress bar shows no visible error today.
- **Current line.** Find it by binary search over the start times, which is
  O(log n) for a list of about 60 lines. It does not need to run every frame:
  schedule one wake-up for the next line's start time and reschedule on seek,
  pause and track change. While the lyrics are closed, nothing runs. That fits
  B-Side's "nothing runs while it is closed" rule.
- **Memory and network.** A lyrics reply is about 30 KB today; the timed data
  is a few KB. Nothing is fetched until the lyrics are opened, as now. A small
  per-track cache (by `videoId`, in memory, for the tracks of this session)
  makes reopening free.
- **Ads.** Lyrics stay hidden during an ad, as now. The position clock
  restarts with the track after the ad.

## 5. What it would look like (for design)

This is not decided, only the options the data allows:

- **In place of the artwork zone.** Apple Music and the YouTube Music mobile
  app replace the cover with scrolling lines. The current line is in `text`,
  the others in `text-muted`, and the view scrolls smoothly to keep the current
  line in the upper third. Clicking a line seeks to it. This needs the room the
  popover does not have.
- **In the popover, as now,** with the current line highlighted and followed.
  This is the smallest change.
- **In the strip or the menu-bar menu,** one line: the current lyric under the
  title. It is cheap, and useful when the window is on another page.
- Reduce Motion means a jump to the next line instead of a scroll. When the
  source has no timings, the plain text stays as it is, marked as not synced.

## 6. Proposed experiments (1 and 3 run, see section 8)

All of them went in `spikes/live-lyrics/`, with no change to `Sources/`.

1. **Coverage and agreement.** A script with about 40 public tracks: English
   pop and rock, Russian, K-pop, hip-hop, old catalogue, a few music videos and
   live versions. For each track it:
   - gets the `videoId`, title, artist and duration from YouTube Music search,
     without signing in;
   - asks YouTube Music for the lyrics page as `WEB_REMIX` and as
     `ANDROID_MUSIC`, with ytmusicapi's version and a current one, and records
     whether `timedLyricsData` is there;
   - asks LRCLIB `/api/get` with the YouTube Music metadata as is, and again
     with the title cleaned up;
   - where both sources have timings, compares the start times of matching
     lines, which shows the offset between them.

   Output: a hit-rate table per source and genre, reply sizes and times, and
   the offsets. About 200 requests in total, spaced out. Nothing from the
   user's account is used.
2. **Position drift.** A debug argument in a spike copy of the app that logs
   `position(at:)` next to the page's `currentTime` every 5 s over three full
   tracks, one of them with a seek and a pause. It shows whether the
   extrapolated clock is good enough for lyrics or needs a correction from the
   page now and then.
3. **From the page or from Swift.** One track: the `ANDROID_MUSIC` `browse`
   sent from inside the page (with the web session) and from `URLSession`
   (without cookies). Does either get refused?

## 7. Open questions

- Does Google still answer `ANDROID_MUSIC` `browse` for lyrics without
  attestation, and with which client versions? Experiments 1 and 3 answer this.
- How much of the user's own listening has timed lyrics in each source?
  Experiment 1 covers a public sample only. The user could run it on their
  history later, and nothing would be committed.
- Where the lyrics should live in the UI (section 5): a design decision.

## 8. Results

Experiment 1 took 40 public searches, of which 39 were found: 34 songs, and 5
official videos and live recordings. Experiment 3 took three songs.

- **YouTube Music's timed lyrics work, signed out, with no attestation.** It
  timed 31 of the 34 songs, with Android client versions 7.21.50 and 8.30.54
  alike. Every song that has lyrics on the web has them timed, except one
  (Кино, plain only). Russian songs were covered as well as English ones.
- **Videos have none on YouTube Music.** Official videos and live uploads have
  an empty lyrics page. YouTube Music times only the song version (`ATV`).
- **LRCLIB timed 36 of 39**, including 3 of the 5 videos, and both songs
  YouTube Music had no lyrics for. It matched 30 on the metadata as is, and 6
  more after cleaning up the title and searching. It missed a Russian song
  whose title and artist YouTube Music gives in Latin letters. It answered
  **HTTP 503** to several first requests at one request per 0.6 s.
- **Together: 37 of 39**, and all 34 songs.
- **The two agree.** Over the 29 tracks both timed, the median offset is 0 ms,
  and most are within ±0.2 s. Three are off by 1 to 1.75 s. Which side is
  right there is not known without listening.
- **Where to send it from does not matter.** URLSession without cookies, and
  `fetch()` in the page with or without its cookies, all got the full timed
  lines. So did the default User-Agent.
- **Size.** The Android reply is about 610 KB (129 KB gzipped), and 590 KB of
  it is the Android app's UI framework. The timed lines are in its first
  20 KB. A lookup takes about 0.5 s; LRCLIB about 0.14 s.

### Recommendation

1. **YouTube Music first, from Swift, without cookies.** The request is not
   tied to the account, it does not touch the page, and experiment 3 shows
   it answers the same. The lyrics page ID still comes from the page's `/next`,
   as today. Parse only the `timedLyricsModel` object, not the whole reply,
   the same way `player.js` cuts its responses. Keep the answer per `videoId`
   for the session.
2. **LRCLIB when YouTube Music has no timings:** for videos, and for songs it
   has only plain lyrics for. Use `/api/get` with the metadata as is, then
   with a cleaned-up title and the first artist, then `/api/search` within
   10 s of the length. Retry once on 503, send a `User-Agent` that names
   B-Side, and ask at most once per track.
3. **Otherwise the plain text, as now.**
4. Videos are the weak spot. LRCLIB times the album version, and a video's
   intro shifts every line. Either show LRCLIB's timings for videos only when
   the lengths match within 2 s, or show plain text for videos.

Still open: the drift of the position clock (experiment 2, with music
playing), which side is right in the 1 s disagreements, and the design.

## Sources

- ytmusicapi, `get_lyrics` and `as_mobile`:
  https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/mixins/browsing.py,
  https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/ytmusic.py,
  `TIMESTAMPED_LYRICS` in https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/navigation.py,
  models: https://ytmusicapi.readthedocs.io/en/stable/reference/api/ytmusicapi.models.html
- ytmdesktop synced lyrics PR: https://github.com/ytmdesktop/ytmdesktop/pull/1666
- Better Lyrics: https://github.com/better-lyrics/better-lyrics
- LRCLIB: https://lrclib.net, https://github.com/tranxuanthang/lrclib,
  a client library's API notes: https://lrclibapi.readthedocs.io/en/stable/lrclib.html
- syncedlyrics (provider list): https://pypi.org/project/syncedlyrics_aio/1.0.1
- YouLy+ (provider list): https://addons.mozilla.org/nl/firefox/addon/youly/
