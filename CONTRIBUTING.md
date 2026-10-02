# Contributing

Thank you for looking. B-Side is small on purpose: a simple, good-looking
player in a 320 by 440 window. Changes that keep it that way are welcome.

## Before you start

- **A bug**: open an issue with what you did, what happened, and the lines of
  `~/Library/Application Support/B-Side/events.log` around that time. The log
  holds track names and what your vibes were read as, and no account data;
  read it before posting.
- **Playback, the library or search stopped working for everyone**: YouTube
  Music probably changed. The fix is usually a name in the `ADJUST HERE`
  block of [player.js](Sources/BSide/Resources/player.js); see
  [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
- **A feature or a change of look**: open an issue first. Design is decided
  before code here: [DESIGN.md](DESIGN.md) is the source of truth, and each
  screen has a spec in [design/SCREENS.md](design/SCREENS.md) that is written
  before the screen is built.

## What will not be accepted

- Downloading, stream extraction, signature deciphering, or anything else
  that goes around Google's player.
- Removing or skipping ads.
- Analytics, accounts, or sending the user's data anywhere new.
- New dependencies in the app. It has none.

## Making a change

1. Build and run: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
2. Find your way: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
3. Keep to the code around you:
   - Views take colours, type, spacing and sizes from `Theme`; raw values
     fail `scripts/check-design.sh`. A line that must break the rule carries
     `// tokens-ok` and the reason.
   - System controls where they exist. A part drawn by hand says `CUSTOM:` in
     its comment, and why.
   - Views read `PlayerController` and call its methods; they do not write
     its state.
   - Names YouTube Music may change go to the `ADJUST HERE` block of
     player.js, and numbers to `Tuning.swift` or `Theme.swift`, each with a
     comment that says what it is for.
   - Comments say why, in plain words. English in the repository.
4. Check it, all three ways in
   [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#checks-before-a-change-is-done):
   the design check, snapshots before and after, a muted run with the event
   log.
5. A change to a screen updates its spec in `design/SCREENS.md` and its
   pictures in `design/audit/`.

## Pull requests

- One change per pull request, with a message that says what changes for the
  user and why.
- Say how you checked it, and what you could not check.
- Screens: attach the snapshots, before and after.

## The server

[server/](server/) has its own README. Its safety rests on limits and a
budget, not on hidden code, so changes to limits, the prompt or what is
stored get extra care: nothing about the user may be stored.

## Licence

By contributing you agree that your work is under the project's
[MIT licence](LICENSE).
