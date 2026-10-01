# Vibes from a prompt

Research only, no code changes. Written 2026-10-01.

The question: can the user type a mood or a motto ("rainy Sunday, slow jazz,
no vocals", "driving at night through a neon city") and get an endless
stream of fitting songs from YouTube Music, as a Vibe tile?

## 1. Short answer

Yes, and B-Side already has every YouTube Music call it needs: `search`,
`browse` and `next` (radio). What is missing is the step that turns free
text into something YouTube Music understands. The plan:

1. **A language model turns the prompt into a small spec**: moods, genres,
   seed artists, search queries, terms to exclude, vocals yes or no, energy.
   It does not have to name exact songs.
2. **B-Side checks the spec against YouTube Music.** It searches the
   queries and the artists with the `songs` filter, keeps only real
   matches, and picks two to four anchor songs.
3. **It plays those anchors' radios one after another** (`next` with
   `RDAMVM<videoId>`, the same kind of radio a Radio Vibe tile plays now),
   and loads more of each radio as it goes, so the stream never ends.
   Exclusions, an artist cap and "not played recently" are applied in code.
   The model is not trusted with them.

The default model is **Apple's on-device model** (Foundation Models). It is
free, works offline, needs no key, and answers in about 2 s on this Mac.
Where it does not know enough, there are two fallbacks: no model at all
(section 5), or the user's own Claude API key.

There is nothing to borrow from YouTube itself. Its own AI features (AI
Playlist, Ask Music) are Premium-only and mobile-only, and they have no
known API.

## 2. What YouTube Music has

| Feature | Who and where | Usable from B-Side |
|---|---|---|
| **AI Playlist** (2026-02-10) | Premium; iOS and Android only | No. Mobile only; no known endpoint. |
| **Ask Music** (conversational; upgraded 2026-09-23) | Premium; mobile; English or Spanish; US, UK, CA, AU, IE, NZ and Latin America except Brazil | No. Mobile only; no known endpoint. "Worldwide soon", no date. |
| **Radio builder / tuner** (2023) | Everyone; web and apps | Maybe. Up to 30 seed artists, familiar ↔ discover, mood filters. The endpoint is undocumented; it could be read off the web player's traffic. |
| **Moods & genres** | Everyone | Yes. Checked: `browse` with `FEmusic_moods_and_genres` returns 36 categories with `params` even without cookies (Chill, Focus, Sleep, Workout, Jazz, Metal, …). `FEmusic_moods_and_genres_category` with those `params` gives curated playlists (`RDCLAK5uy_…`). |
| **Song radio** | Everyone | Yes, already used: `next`, `playlistId: RDAMVM<videoId>`, `params: wAEB`, continuations for more. |

Reports say Ask Music ignores negative wishes ("no vocals") often. That is
another reason to apply exclusions in code.

## 3. Other services

| Service | State | For B-Side |
|---|---|---|
| ListenBrainz LB Radio | A prompt language made for this (`tag:(jazz,instrumental)`, `artist:(…)`, `#punk`, weights). Free, open data. Since recently it needs a user token (401 without). About 1 request/s. | Optional, for users who add their own ListenBrainz token. |
| Last.fm | `tag.getTopTracks`, `tag.getSimilar`, `artist.getSimilar`. Needs an API key; open-source apps usually ship one. Non-commercial use only; attribution required. | The best source of mood tags ("rainy", "night drive"). Optional enrichment. |
| Spotify recommendations | Closed to new apps since 2024-11-27. | No. |
| AcousticBrainz | Stopped collecting in 2022. | No. |
| Cyanite, Musixmatch | B2B or paid, made for one's own catalogue or lyrics. | No. |

## 4. Language models

### Apple's on-device model (tried on this Mac, macOS 27.0.1)

- It is available here.
- Guided generation (`@Generable`) returns a filled Swift struct.
- Size: about 3B parameters, with a 4096-token context.

Two runs:

**Exact songs: often wrong.** For "rainy Sunday, slow jazz, no vocals" it
gave "Miles Davis – Kind of Blue", which is an album, and "Paul Desmond –
Take the 'A' Train". For the neon-city prompt it gave "Chvrches – Take Me
Out", which is a Franz Ferdinand song.

**A spec: good for well-known genres, poor elsewhere.** Times are 1.6–2.5 s
per prompt.

| Prompt | Artists | Queries | Vocals, energy |
|---|---|---|---|
| Rainy Sunday morning, slow jazz, no vocals | Miles Davis, John Coltrane, Bill Evans, Kenny Dorham, Paul Desmond, Chet Baker | "slow jazz music", "jazz without vocals", "jazz for a rainy day" | no, 2 |
| Driving at night through a neon city | Kendrick Lamar, Sade, The Weeknd, Daft Punk, Björk | "night driving music", "neon city vibe" | yes, 4 |
| Focus for coding, no lyrics, not boring | Aphex Twin, Boards of Canada, Portishead, Squarepusher, The Caretaker, Yello | "electronic music for coding", "minimal electronic" | no, 3 |
| Готовлю ужин с друзьями, что-то весёлое и русское | "Blink-199er", The Rolling Stones, "Sasha Gavril", "Maks" three times | "cheerful Russian music", "Russian party music" | yes, 4 |

So:
- Ask it for a spec, never for a track list.
- Check every artist with a search before using it.
- When few artists survive the check, lean on its queries, which are
  sensible even when its artists are not.
- Russian and other less covered scenes are where it is weakest.

Two newer options from WWDC26, both unverified for B-Side:
- **Private Cloud Compute**: a larger model with a 32K context. It is
  unclear whether an app shipped outside the App Store (Developer ID) can
  use it.
- **A Claude or Gemini model behind the same Swift API.** This would let
  one code path serve both backends.

### A cloud model (Claude) with the user's own key

It knows the long tail far better: Russian scenes, deep cuts, "music that
influenced X". In an open-source app it costs nothing to ship, but each
user needs their own key. Make it an option under Settings, not the
default. Published studies put invented tracks at a few percent, so the
YouTube Music check stays either way.

### Known pitfalls, and the cure

| Pitfall | Cure |
|---|---|
| Invented artists or songs | Search with the `songs` filter, keep only matches on artist and title. |
| Always the most famous songs | Ask for artists and scenes, not hits; seed radios from several anchors. |
| The same stream every time | Shuffle the anchors; pass the recently played artists back in. |
| "No vocals" ignored | Filter in code: drop titles with "vocal", "feat.", "remix" as asked; prefer queries with "instrumental". |
| Knowledge cutoff | Radio continuations bring in new releases; the model only seeds. |

## 5. Without a model

This version works on every Mac and covers the simple prompts.
- Match the prompt's words against the 36 Moods & genres categories
  ("chill", "focus", "sleep", "jazz"), and seed the radio from the top
  curated playlist (`RDAMPL<playlistId>`).
- Otherwise run the prompt itself as a song search and seed from the first
  results.

It is also the fallback when Apple Intelligence is off.

## 6. What it could look like (for design)

From Spotify Prompted Playlists, Apple Music Playlist Playground, Deezer,
Amazon Maestro and the YouTube Music tuner:

- **The prompt field.** "New Vibe" gets a text field with example chips
  ("Rainy Sunday", "Night drive", "Deep focus"), next to today's
  playlist / radio choice.
- **Show what was understood.** After a short wait the tile shows the
  spec it built: tags and seed artists, with an × on each. The user fixes
  the spec, not the prompt.
- **Steering while it plays.** "Calmer", "More energy", "Less familiar",
  "No vocals", "More like this song". Each one changes the spec slightly
  and picks fresh anchors. It should not restart the stream from scratch.
- **Familiar ↔ discover.** One switch, as in the YouTube Music tuner. It
  maps to "seed from the user's Liked Music artists" versus "only new
  artists".
- **Save as a Vibe.** The tile keeps the prompt and the spec. The tile's
  colour can come from the spec's energy and mood.

## 7. Proposed experiments (none run)

1. **Spec quality.** Run 30 prompts in three languages through the
   on-device model and through Claude, check each artist by search, and
   compare the share that survives.
2. **Stream quality.** For 10 prompts, build streams from the anchors'
   radios and listen to the first 20 songs of each. How many fit? How fast
   does it drift?
3. **The tuner endpoint.** Capture the web player's radio builder
   requests, and find out whether multi-artist stations with familiarity
   and mood filters can be started by B-Side. If they can, the tuner
   replaces step 3 of section 1.
4. **No-model fallback.** Measure how many of the 30 prompts match a
   Moods & genres category at all.

## 8. Open questions

- Is Private Cloud Compute available to an app outside the App Store?
- Is Ask Music on the web anywhere? One weak source says so; Google's help
  page does not.
- Last.fm's rate limit has no published number.

## 9. What was built (2026-10-01)

`VibeMaker.swift` and the New Vibe sheet:
- Apple's on-device model reads the words into a name, two to four genres a
  search understands, four to eight artists, and vocals yes or no. One
  example in the instructions; asked never to name songs. Without it, the
  words are matched to YouTube Music's moods.
- Each artist is searched (songs filter) and kept only when a result
  credits exactly that name; empty answers are asked once more. Their songs,
  then the genres' songs, become up to eight seeds, different artists first.
- The user's own words are searched too when fewer than two artists are
  confirmed, and first when the words are not in Latin letters.
- A tile plays the radio of one of its seeds, a different one each time.
- `-makeVibe "<words>"` runs all of it at launch and writes it to the event
  log.

Results on this Mac, about 5 to 7 s from words to seeds:

| Words | Confirmed artists | Verdict |
|---|---|---|
| Rainy Sunday morning, slow jazz, no vocals | Kenny Garrett, Charles Mingus, John Abercrombie, Evan Parker | Fits |
| Driving at night through a neon city | Aphex Twin, Caribou, Boards of Canada, Jonny Greenwood | Fits |
| Focus for coding, no lyrics, not boring | Aphex Twin, Max Richter, A Winged Victory for the Sullen, Hammock | Fits |
| Готовлю ужин с друзьями, что-то весёлое и русское | Two namesakes of invented names | Weak: the Russian songs come from the words themselves |
| Грустный вечер, русский рок 90-х | None | Weak: the model does not know Russian rock |

Next for quality: a cloud model (the user's own Claude key) for languages
and scenes the on-device model does not know.

## Sources

- YouTube AI playlists: https://techcrunch.com/2026/02/10/youtube-rolls-out-an-ai-playlist-generator-for-premium-users
- Ask Music upgrade: https://techcrunch.com/2026/09/23/youtube-music-gets-more-conversational-with-new-ai-features/
- Ask Music availability: https://www.itechguides.com/youtube-musics-prompt-generated-ai-radio-became-ask-music-what-it-does-and-who-can-use-it/
- Radio builder: https://9to5google.com/2023/02/18/youtube-music-create-radio/
- ytmusicapi, moods and radio: https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/mixins/explore.py, `mixins/watch.py`
- LB Radio: https://troi.readthedocs.io/en/latest/lb_radio.html
- Last.fm terms: https://www.last.fm/api/tos
- Spotify API changes: https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api
- Hallucination rates in LLM music recommendation: https://arxiv.org/html/2511.16478v1
- Foundation Models, WWDC26: https://developer.apple.com/videos/play/wwdc2026/8121/
- Spotify Prompted Playlists: https://pulse2.com/spotify-expands-prompted-playlists-beta-to-premium-users-in-the-u-s-and-canada
- Apple Music Playlist Playground: https://www.musicbusinessworldwide.com/apple-musics-ios-26-4-beta-introduces-ai-powered-playlist-tool/
