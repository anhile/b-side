# B-Side design

The single source of truth for how B-Side looks and behaves. Read all of it
before building or changing any screen. A new colour, size or component is
added here first, then to the theme, then used.

Status: approved on 2026-09-30, with three decisions by the owner: two pages
with dots, a 320 by 440 window, a cream background.

Decided on 2026-09-30: three pages, Vibe, Playlists and Now Playing. Vibe
becomes a customisable set of mood tiles in two columns, each tile a playlist,
Liked Music shuffled, or a track's radio; the player has its own Now Playing
page, the third dot; Vibe and Playlists carry a one-line strip with the
current track while music plays; starting music does not switch the page.
No iPod wheel.

Mockups are made in SwiftUI, not Figma: `-snapshot` renders every page in its
states, light and dark, into `design/audit/`. Figma keeps the moodboard and
Foundations only. Screen specs live in [design/SCREENS.md](design/SCREENS.md).

Done: the palette, the theme file, `scripts/check-design.sh`, the Now Playing
page with the `Record` graphic, the strip, the Playlists page with `Skeleton`.
Not yet: the Vibe tiles, glass, the Reduce Motion cross-fade.

Moodboard and Foundations: Figma file "B-Side — Design",
https://www.figma.com/design/jfKJfjHaDpDJle4Dj64MzM

## Positioning

B-Side is a native macOS music player, not a web page in a frame. It is small,
starts fast, stays out of the way, and uses about a third of the memory of
other YouTube Music clients. The web view that plays the music is never seen.

Everything visible is SwiftUI and AppKit: system controls, system text, system
materials. If a control exists in macOS, B-Side uses it and does not redraw it.

## Product character

Warm, quiet, tactile, confident, light.

It should feel like a record sleeve on a desk: one object, flat colour, a clear
shape, nothing blinking. It must never feel like a streaming storefront, a
dashboard, or a browser tab.

References: the app icon and the owner's moodboard (vinyl and CD player
concepts, an iPod-like control wheel). They set a direction, not a layout:

- A record shows through somewhere, quietly. It is decoration for the content,
  never a control.
- Controls may echo an old iPod: round, few, flat.
- Disc graphics (vinyl, CD) are the only custom drawing in the app.

What is not taken from the moodboard: soft shadows under cards, oversized
corner radii, phone layouts. Those read as web or iOS, not as a Mac app.

## Principles

1. **One thing per screen.** Each page has one job and one primary action.
2. **Content is the hero, chrome recedes.** Artwork and track names carry the
   screen. Controls are small and sit on the glass layer.
3. **The accent is scarce.** Orange marks the playing track, the active
   element and progress. It is never a button fill or a background.
4. **Native first.** System behaviour wins over a custom idea: menus, keyboard
   shortcuts, Settings, light and dark, accessibility settings.
5. **Light in every sense.** No feature may add a permanent cost in memory.
   Images are loaded at the size shown and released when off screen.
6. **Remove before adding.** Hierarchy is fixed by muting or deleting, not by
   making something louder.

## Colour

Taken from the app icon: the orange field, the cream sleeve, the black vinyl.
Two themes, named after them. The theme follows the system appearance.

| Token | Sleeve (light) | Vinyl (dark) | Use |
|---|---|---|---|
| `bg` | `#FBF4E6` | `#151514` | Window background |
| `surface` | `#F8EBD3` | `#2E2E2D` | Row hover, artwork placeholder, grouped areas |
| `text` | `#151514` | `#F8EBD3` | Primary text and icons |
| `text-muted` | `#66635E` | `#A9A090` | Secondary text: artist, counts, time |
| `border` | `#D6D0C4` | `#393733` | Hairline separators, decorative only |
| `control-border` | `#88847D` | `#868074` | Outline of an interactive control |
| `accent` | `#FD6512` | `#FD6512` | Small shapes: indicator, current dot, progress |
| `accent-text` | `#B23A08` | `#FD6512` | Accent-coloured text and small icons |
| `accent-on` | `#151514` | `#151514` | Text on an accent shape, such as a record label |
| `record` | `#151514` | `#2E2E2D` | The vinyl disc of the `Record` graphic |
| `record-groove` | `#F8EBD3` at 18% | `#F8EBD3` at 18% | Grooves on the disc |
| `shadow` | black at 25% | black at 25% | The one shadow, under large artwork |
| `danger` | system red | system red | Errors |
| `success` | system green | system green | Confirmations |

Measured contrast:

| Pair | Sleeve | Vinyl | Needed |
|---|---|---|---|
| `text` on `bg` | 16.7:1 | 15.5:1 | 4.5:1 |
| `text-muted` on `bg` | 5.5:1 | 7.1:1 | 4.5:1 |
| `accent-text` on `bg` | 5.5:1 | 6.1:1 | 4.5:1 |
| `accent-on` on `accent` | 6.1:1 | 6.1:1 | 4.5:1 |
| `control-border` on `bg` | 3.4:1 | 4.7:1 | 3:1 |

Rules:

- `accent` on `bg` is only 2.7:1 in Sleeve. It is for shapes. Orange text in
  the light theme uses `accent-text`.
- White or cream on `accent` fails (3.0:1 and 2.5:1). What sits on orange is
  always `accent-on`, as on the icon.
- Where the accent is allowed: the playing track's indicator, the current
  page dot, the progress bar's filled part, the label of the record graphic.
- The accent is never a button fill, a row background or a window area.
- No gradients. No second accent colour.

## Typography

SF Pro through system text styles only, so Dynamic Type and the user's
settings work. No custom fonts, no fixed point sizes.

| Role | Text style | Size on macOS | Weight | Use |
|---|---|---|---|---|
| display | `.largeTitle` | 26 | bold | The Vibe page headline, nothing else |
| title | `.title3` | 15 | semibold | Track title, page title |
| body | `.body` | 13 | regular | List rows, settings |
| label | `.callout` | 12 | medium | Buttons, field labels |
| caption | `.subheadline` | 11 | regular | Artist, counts, time, status |

- Three weights: regular, medium or semibold, bold.
- Time and numbers that change use monospaced digits.
- Titles are one line and truncate at the tail. The full text is in a tooltip.

## Spacing

Scale: 4, 8, 12, 16, 24, 32. No other values.

- Window padding: 16.
- Inside a group: 4 or 8. Between groups: 16 or 24. Space inside a group is
  always smaller than the space around it.
- List row height: 44, with 8 between artwork and text.

## Shape and depth

| Token | Value | Use |
|---|---|---|
| `radius-s` | 6 | Row hover, small artwork |
| `radius-m` | 12 | Large artwork, grouped areas |
| `radius-full` | capsule or circle | Buttons, page dots |

Three levels of depth:

1. **Content**: `bg`. Flat.
2. **Surface**: `surface` fill. Flat, no shadow, no border.
3. **Glass**: floating controls only. See Liquid Glass below.

The only shadow in the app is under large artwork. Borders separate; they
never box things in.

## Liquid Glass

Available from macOS 26. B-Side supports macOS 14 and later, so every glass
element has a fallback.

| | macOS 26 and later | macOS 14 and 15 |
|---|---|---|
| Floating controls | `glassEffect`, `.buttonStyle(.glass)` | `.regularMaterial` in the same shape |
| Primary button | `.glassProminent` tinted `text` | `text` fill, glyph in `bg` |
| System controls | Adopt glass on their own | System look |

- Glass is for the control layer: page dots, transport controls, the settings
  button. Content is never glass.
- No glass on glass. Controls that sit together share one container.
- With Reduce Transparency on, glass becomes `surface` with `control-border`.

## Motion

- Feedback (press, hover): 150 ms.
- Page change: 300 ms, and the page follows the finger during a swipe.
- One easing: the system spring, no bounce.
- One deliberate moment: pressing Play on Vibe. Everything else is plain.
- With Reduce Motion on, pages cross-fade and nothing slides.

## Icons

SF Symbols only. No custom glyphs, no emoji. The record graphic is artwork,
not an icon.

- Filled variants for transport controls: `play.fill`, `pause.fill`,
  `forward.fill`, `backward.fill`.
- `gearshape` for settings, `shuffle`, `heart.fill`, `music.note.list`.
- Symbol weight matches the text next to it. Hierarchical rendering.
- Every icon-only button has an accessibility label and a tooltip.

## Window behaviour

**Main window: a compact player, not a document window.**

- Size 320 by 440 points. Not resizable in the first version.
- Hidden title bar. The traffic lights stay. The window drags by its
  background.
- Three pages, Vibe, Playlists and Now Playing, side by side. No sidebar, no
  `NavigationSplitView`, no toolbar: the window is too small for them, and
  three destinations do not need a sidebar.
- Closing the window does not stop the music. The Dock icon reopens it.
- The window remembers its position.

**Page navigation**

| Input | Action |
|---|---|
| Two-finger swipe left or right | Next or previous page |
| Click a page dot | That page |
| Command-1, Command-2, Command-3 | Vibe, Playlists, Now Playing |
| View menu | The same two commands |

Page dots are not a standard macOS control, so they are built as real buttons:
a 24 by 24 click area each, a label for VoiceOver, keyboard focus.

**Settings window: standard macOS.**

- The SwiftUI `Settings` scene, opened by Command-comma and the app menu. The
  gear button in the main window's bottom right corner opens the same window.
- Tabs: Account (sign in, sign out), Playback (audio only, Now Playing),
  Diagnostics (memory by process, event log, unload when paused).
- Standard `Form` with grouped style. No custom controls.

If B-Side ever gets a full library window, `NavigationSplitView` with a sidebar
and toolbar belongs there. It is out of scope now.

## macOS rules

- Every action is in the menu bar with a shortcut: Space for play and pause,
  Command-Right and Command-Left for next and previous.
- Media keys and the system Now Playing widget always work.
- Light and dark follow the system. There is no in-app theme switch.
- Respect Reduce Motion, Reduce Transparency and Increase Contrast.
- System controls in Settings keep the user's system accent colour. B-Side's
  orange is used only in the main window.
- Full keyboard access: every control is reachable with Tab and has a visible
  focus ring.
- Hover shows what is clickable. Nothing depends on hover alone.
- Errors say what happened and what to do, in the place where it happened.

## Screens

Short descriptions for scope. Each gets a full spec before it is built.

| Screen | Job | Primary action |
|---|---|---|
| Vibe | Start music for a mood with one click | Play the chosen mood tile. Liked Music, shuffled, is one of the tiles |
| Playlists | Pick one of my playlists | Play the chosen playlist |
| Now Playing | See and control what plays | Play or pause |
| Settings | Account, playback options, diagnostics | None |

Vibe is a grid of tiles in two columns, and the set of tiles is the user's
to change. Now Playing carries the large artwork, title, artist, progress,
volume and the transport controls.

## Components

The closed set. A screen is composed from these and nothing else.

| Component | Variants | Use |
|---|---|---|
| `PlayButton` | hero | The Vibe page. One per screen. Filled with `text`, never orange |
| `Record` | vinyl, disc | Decoration behind or beside artwork. Custom drawing |
| `TransportButton` | previous, play or pause, next | Now Playing area |
| `IconButton` | glass | Settings gear, shuffle |
| `PageDots` | | Top of the main window |
| `PlaylistRow` | default, playing | Playlists page |
| `Artwork` | small 36, large 160 | Rows, Now Playing |
| `MoodTile` | default, playing | Vibe grid |
| `NowPlaying` | page | The Now Playing page |
| `ProgressBar` | | Now Playing area |
| `EmptyState` | signed out, no playlists, error | Any page |
| `Skeleton` | row | Playlists while loading |

## Do and don't

| Do | Don't |
|---|---|
| Use tokens from the theme file | Write a colour, font size or spacing number in a screen |
| Put `accent-on` on orange | Put white or cream text on orange |
| Use `accent-text` for orange text in the light theme | Use `accent` for text on `bg` |
| Build every state: loading, empty, error, long title | Build only the ideal state |
| Use a system control when one exists | Redraw a toggle, slider or menu |
| Give every icon button a label and a tooltip | Rely on the icon alone |
| Keep one primary button per screen | Add a second filled button |
| Use orange for the playing track, the active element, progress | Fill a button or an area with orange |
| Mark custom drawing in the mockup with a note | Draw a system control by hand |
| Load artwork at the size shown | Keep full-size images in memory |

## Mockups

- Screens are 320 by 440, each in Sleeve and Vinyl.
- Every key screen has four states: empty, loading, playing, error.
- System controls come from Apple's macOS 26 UI kit. Nothing that exists in
  the kit is drawn by hand.
- Whatever needs custom SwiftUI layout carries a note in the mockup. So far:
  `PageDots`, `Record`.
- The Figma plan allows three pages and one variable mode. Flows share a page
  with States, and the dark theme is a second variable collection.

## Enforcement

- Colours live in the asset catalog (`Assets.xcassets/Colors`) as colour sets
  with light and dark values. Everything else, and the colour names, lives in
  `Sources/BSide/Design/Theme.swift`.
- Screens import tokens and components only. Settings keeps the system look
  and is exempt.
- `scripts/check-design.sh` fails on raw colours, text styles, spacing and
  sizes in `Sources/BSide/Views`. It runs before every design review. A line
  that must break a rule carries `// tokens-ok` and a reason.
- Review: `open B-Side.app --args -snapshot <folder> -ApplePersistenceIgnoreState YES`
  writes every page and state as PNG, light and dark; the critique is written
  from those files before any fix.
