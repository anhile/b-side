# Screen specs

Confirmed by the owner on 2026-09-30. One spec per screen, written before the
screen is built; the critique in each design pass is checked against it.

Shared: three pages side by side, page icons in a capsule at the bottom, the
strip with the current track above them. The page's name stands after the
window buttons, in the text colour, where a window has its title; the icons
at the other end are the buttons (since 2026-10-02). No gear: Settings are in the menu
bar and under Command-comma. Starting music never switches the page.

## Screen: Now Playing

- User's job here: "see what plays and control it"
- Primary action: Play or Pause
- Secondary actions: Next, Previous, seek, volume (speaker opens a popover)
- Attention order: 1) artwork 160 with the record showing from behind on the
  right 2) title and artist 3) progress 4) transport
- Title and artist start at the left edge, in line with the progress bar; a
  long title scrolls. What can be done with the track comes after them:
  Like, then the track's menu ("…"). Both are muted and without glass, so
  they weigh the same (since 2026-10-02; before, Up Next and Like stood on
  the two sides of a centred title, which squeezed it and put an unrelated
  pair in balance).
- Like: a heart, always in view; orange and filled once liked. Not on the
  artwork's hover, which keeps Lyrics and Repeat. Hidden during an ad.
- Up Next: a list button in a glass circle at the end of the transport row,
  mirroring the speaker at its start; both open something. It
  puts what plays next in the artwork's place (as Lyrics do; one of the two
  at a time) and is orange while the list shows. A click on a track jumps to
  it; its menu is a track's menu plus Remove from Up Next. The next 30
  tracks; "Nothing after this track." when there are none.
- Ad: "Advertisement", and under it "Music back in 0:12", counted down
  each second; in a run of ads all but the last say "Ad 1 of 2 · 0:12".
  The same line is under "Advertisement" in the strip. Without a time from
  the player, the ad's own title, as before.
- What we removed or deferred: shuffle toggle, dragging tracks in Up Next
- At launch: the track that played last, paused where it stopped (as Music
  and Spotify do); Play goes on from there, in the same playlist or vibe.
  "Nothing playing" only before the first track ever, and after signing out
- States: nothing playing (record alone, "Nothing playing", Play Vibe) /
  loading ("Loading…") / ad ("Advertisement", seek disabled) / long title (one
  line, tail truncation, tooltip) / no artwork (surface placeholder with a
  note) / signed out / player failed
- Entry and exit: third dot, Command-3, the strip on the other pages; leaves
  by swipe or dots

Status: passed the rubric on 2026-09-30, iteration 2 (design/audit).

## Menu: a track

One menu wherever a track is listed or plays (a playlist's track, a search
result, an album's track, the strip, Now Playing's "…"), added 2026-10-02:

- Like or Remove Like
- Add to Playlist (a submenu, checked where the track already is)
- what only that place offers: Remove from Playlist in an own playlist;
  Lyrics and Repeat on Now Playing
- Play Next: right after the track that plays
- Start Radio: the track, then its radio
- Go to Artist, Go to Album (disabled when YouTube Music does not link them)
- Copy Link

A list knows a track's like as of when it was loaded; likes set in B-Side
since then win.

Every item of this menu, and of a tile's menu, has its symbol before the
title.

Rows of tracks (a playlist's, an album's, a search's, Up Next) end the same
way: the track's length, or the orange speaker on the one that plays.

## Screen: Vibe

- User's job here: "start music for how I feel right now, in one click"
- Primary action: click a tile
- Under a tile's name: what it plays. For a vibe made from words, what it
  was heard as ("slow jazz, rainy"), or "From words" for a tile made before
  that was kept; never the words themselves, and never the name again
- Secondary actions: add a tile (the "+" tile at the end); edit and remove in
  a tile's context menu; drag a tile to another's place, the others make
  room as it passes (also Move Earlier and Move Later in the menu)
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

## Sheet: New Vibe (from words)

Approved by the owner 2026-10-01 and built: the "+" tile opens it, Edit…
on a tile made from words opens it again with the words. Generation is
`VibeMaker.swift`; mockups are `newvibe-*` in design/audit.
Research: [docs/research/vibe-from-prompt.md](../docs/research/vibe-from-prompt.md).

- User's job here: "describe how I feel in my own words and get music that
  fits, without picking a playlist"
- Primary action: Make, then Add Vibe
- Secondary actions: an example chip fills the words; Try It plays the first
  songs; a chip's x leaves that part out; Back returns to the words; "A
  playlist, Liked Music or a track's radio…" opens the editor it replaced
- Attention order: 1) the words field 2) the example chips 3) Make. In the
  preview: 1) the tile as it will look 2) Vocals and Artists 3) "Heard as"
  4) the first songs in one line
- Steps, in one sheet:
  - Describe: a field of three to five lines, a line on what happens, four
    example chips, and "Or play what you have": a row with a chevron to the
    other kinds of tile (a row, not a link, since 2026-10-02). With the
    server on, a line under the words: "7 of 10 vibes left this month."
  - Preview's top (since 2026-10-02): the tile with Try It beside it, then
    Name as a row of its own above Vocals and Artists
  - Making: the words in quotes, three stages with a check, a spinner or an
    empty circle (reading the words, finding artists on YouTube Music,
    picking the first songs). Only Cancel
  - Preview: the real `MoodTile` with the name and colour chosen for it,
    the name field and Try It beside it; Vocals (vocals or not / with / no
    vocals) and Artists (artists I know / known and new / only new) as
    system menus; "Heard as" chips (tags, artists; YouTube Music moods when
    no model was used); "Starts with …, then more like them."
- What we removed or deferred: a full list of the first songs (one line is
  enough to judge, and the sheet must fit the window); steering while it
  plays ("calmer", "more like this") goes to Now Playing later
- States: empty words (Make disabled) / making / preview / preview without
  Apple Intelligence (a note, moods as chips) / nothing found (the words
  stay, a note under them) / no network (as nothing found, with the reason)
- Tile: symbol `text.bubble`; under the name what it was heard as, never the words
- Entry and exit: the "+" tile; Edit… on a tile made from words. Leaves by
  Cancel, Escape or Add Vibe

## Screen: Playlists

- User's job here: "find my playlist and play it"
- Primary action: click a row
- Secondary actions: a new playlist ("+"). No refresh button: the list is
  asked for again whenever the page comes into view, at most twice a minute
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
  the menu bar) or starting; replaced by the pages with a cross-fade. After
  6 s the line reads "Taking longer than usual…"; after 15 s "Still not
  ready. Check the connection." with Try Again where "Nothing
  playing" has its buttons. With Reduce Motion a small spinner stands there
  until then, since the record does not turn
- Entry and exit: covers all three pages; the page icons are hidden. It ends
  when the page reports ready or fails

Status: built 2026-09-30. Laid out like "Nothing playing", with the buttons'
height kept empty, so the record and the title stay put when it hands over.
