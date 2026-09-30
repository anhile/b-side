# Live lyrics experiments

Spikes for the open questions in
[docs/research/live-lyrics.md](../../docs/research/live-lyrics.md).
Nothing here is part of B-Side. No lyrics text is stored: the results hold
counts, sizes, times and public track metadata only.

## Experiment 1: coverage and agreement

`coverage.py` (Python 3, standard library only) takes 40 public searches:
pop, old rock, hip-hop, Russian, K-pop, Latin, official videos and live
recordings. For each one it:

- finds the track on YouTube Music, signed out, and reads its title, artist,
  album, length, video type and lyrics page from `/next`;
- asks for the lyrics page as the web client (`WEB_REMIX`) and as the Android
  client (`ANDROID_MUSIC` 7.21.50, ytmusicapi's version, and 8.30.54);
- asks LRCLIB `/api/get` with the metadata as is, then with the title and
  artist cleaned up, then `/api/search`, taking the closest length within 10 s;
- where both have timings, takes the median difference of the start times of
  lines with the same words.

```bash
python3 spikes/live-lyrics/coverage.py      # about 4 minutes
```

Results, 2026-09-30 (`results/coverage.tsv`, `coverage-summary.txt`):

| | YouTube Music, Android | LRCLIB | Either |
|---|---|---|---|
| Songs (34 found) | 31 timed | 33 timed | 34 |
| Official videos and live (5) | 0 | 3 | 3 |
| All (39 found) | 31 | 36 | 37 |

- **YouTube Music times songs only.** Every song (`ATV`) that has lyrics on the
  web has them timed for Android, except one: Кино, "Группа крови", which is
  plain only. Two songs had no lyrics at all (Eagles, "Hotel California", and
  Eminem, "Lose Yourself"), and LRCLIB had both. Videos (`OMV`, `UGC`) had
  none: the lyrics page exists, but it is empty.
- **Both Android versions answered the same**, signed out, with no attestation.
- **LRCLIB matched 30 of 39 on the metadata as is.** Cleaning up the title
  (dropping "(feat. …)", "(Official Video)") and searching found 6 more. ЛСП
  "Monetka" was missed: YouTube Music gives the title and artist in Latin
  letters. Several first requests got **HTTP 503** at one request per 0.6 s,
  so it needs a retry and gentle pacing.
- **Agreement.** On the 29 tracks where both had timings, the median offset
  (YouTube minus LRCLIB) is 0 ms, and most are within ±0.2 s. Outliers:
  Oasis, "Wonderwall" −1.75 s; Rich The Kid, "Plug Walk" −1.08 s; Баста,
  "Сансара" −1.06 s; Nirvana −0.44 s; the Beatles and Bad Bunny −0.38 s.
  Which side is right in those cases needs a listen.
- **Size.** The Android reply is about 610 KB (129 KB gzipped); 590 KB of that
  is the Android app's UI framework (`frameworkUpdates`). The timed lines sit
  in the first 20 KB. The web reply is 3 KB. A lookup takes a median 0.5 s for
  YouTube Music and 0.14 s for LRCLIB.

## Experiment 3: from Swift or from the page

`paths/main.swift` asks for the timed lyrics of three songs in two ways:

- **swift**: URLSession with no cookies, with and without the Android
  User-Agent;
- **page**: `fetch()` inside a WKWebView on music.youtube.com (a private,
  signed-out store), with the page's cookies and without them.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -O paths/main.swift -o spikes/live-lyrics/build/paths
spikes/live-lyrics/build/paths J7p4bzqLvCw i5ip7a-VSYs TjsfgUkT0eg
```

Results, 2026-09-30 (`results/paths.log`): **all 12 attempts got HTTP 200 and
the full timed lines** (39, 63 and 41). The User-Agent does not matter, and
the page's cookies do not matter. Times were 0.17 s to 0.5 s, and up to 1.5 s
for the first requests from the page. Not tested: from the page while signed
in, because a spike cannot share B-Side's cookie store without risking the
user's session. Sending without cookies works, so B-Side does not need to
test that.
