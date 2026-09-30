# Screen specs

Confirmed by the owner on 2026-09-30. One spec per screen, written before the
screen is built; the critique in each design pass is checked against it.

Shared: three pages side by side, page icons in a capsule at the bottom, the
strip with the current track above them. No gear: Settings are in the menu
bar and under Command-comma. Starting music never switches the page.

## Screen: Now Playing

- User's job here: "see what plays and control it"
- Primary action: Play or Pause
- Secondary actions: Next, Previous, seek, volume (speaker opens a popover)
- Attention order: 1) artwork 160 with the record showing from behind on the
  right 2) title and artist 3) progress 4) transport
- What we removed or deferred: queue, like, shuffle toggle, lyrics
- States: nothing playing (record alone, "Nothing playing", Play Vibe) /
  loading ("Loading…") / ad ("Advertisement", seek disabled) / long title (one
  line, tail truncation, tooltip) / no artwork (surface placeholder with a
  note) / signed out / player failed
- Entry and exit: third dot, Command-3, the strip on the other pages; leaves
  by swipe or dots

Status: passed the rubric on 2026-09-30, iteration 2 (design/audit).

## Screen: Vibe

- User's job here: "start music for how I feel right now, in one click"
- Primary action: click a tile
- Secondary actions: add a tile (the "+" tile at the end); edit and remove in
  a tile's context menu
- Attention order: 1) the grid of tiles 2) the playing tile, marked with the
  accent 3) the strip
- What we removed or deferred: the big Play button, the "Vibe" headline;
  YouTube Music's own moods as a tile source
- Tiles: two columns, 138 by 96, `surface`, radius 12; name in the title
  role, source in the caption role. Sources: a playlist (in order or
  shuffled), Liked Music shuffled, a track's radio. Default: one tile,
  "Liked, shuffled"
- States: signed out / playlists loading (skeleton tiles) / all tiles removed
  (one "Add a mood" tile) / error / long name (two lines, then truncation)
- Entry and exit: first dot, Command-1, the page the app opens on

Status: passed the rubric on 2026-09-30, iteration 2. Tiles are saved in
UserDefaults as JSON (`moods`); the editor is a sheet with system controls.
The playing tile shows an orange speaker in place of its source icon.

## Screen: Playlists

- User's job here: "find my playlist and play it"
- Primary action: click a row
- Secondary actions: refresh
- Attention order: 1) rows with artwork 36 and the name 2) the playing row
  with the accent indicator 3) the strip
- States: signed out / loading (skeleton rows) / error with Try Again / no
  playlists (Liked Music only) / 200 playlists (scrolls) / long name (one
  line, truncation)
- Entry and exit: second dot, Command-2

Status: passed the rubric on 2026-09-30, iteration 1. Liked Music uses the
`Record` graphic at 36 in place of artwork; rows are custom buttons with a
`surface` hover shape, no separators; a `Skeleton` list while loading.

## Strip (Vibe and Playlists, while music plays)

Artwork 24, "Title — Artist" in the caption role, Pause or Play, Next. The
line opens Now Playing. When something failed, the panel shows the message
instead.

A glass panel of its own (radius m), 8 inside the window edges, floating over
the bottom of the page: the lists run under it and keep its height as scroll
margin, so the last row can scroll clear. Changed 2026-09-30: it used to sit
flat on the background and read as part of the page. Vibe and Playlists also
gained air under the title bar (16 and 12).

## Welcome (while the player page loads)

- User's job here: none; wait a moment
- Primary action: none, nothing to press
- Attention order: 1) the turning record 2) "Welcome back" ("Hello" before
  the first sign-in) 3) "Getting the player ready"
- States: shown while nothing plays and the page is asleep (after a start in
  the menu bar) or starting; replaced by the pages with a cross-fade
- Entry and exit: covers all three pages; the page icons are hidden. It ends
  when the page reports ready or fails

Status: built 2026-09-30. Laid out like "Nothing playing", with the buttons'
height kept empty, so the record and the title stay put when it hands over.
