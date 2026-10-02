# Security

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's
private report instead: the repository's **Security** tab, **Report a
vulnerability**. Say what you found, how to reproduce it, and what it lets
someone do.

You can expect an answer within a week. B-Side is a small project kept in
spare time; there is no bounty.

## What matters most

- **The Google session.** B-Side holds the user's YouTube Music session in
  WebKit's data store. Anything that lets another site, app or a network
  attacker read it or act with it is the most serious kind of report.
- **The page script.** [player.js](Sources/BSide/Resources/player.js) runs
  with YouTube Music's origin. It must never run text that came from a
  response, a title or a search result.
- **The server.** [server/](server/) must stay useless for anything but
  reading a vibe's words, must not store what users write, and must not be
  made to spend past its limits. Its design is in
  [docs/plans/vibe-server.md](docs/plans/vibe-server.md).

## What is not a vulnerability

- That the app's code, the server's code and the request format are public:
  they are meant to be. Nothing secret is in the app.
- That the random install ID can be faked. It keeps honest use fair; the
  address limit and the budget are what hold.
- That YouTube Music changed and something stopped working: that is a bug,
  for a normal issue.
