# Default-player experiments

Spikes for the open questions in
[docs/research/default-player.md](../../docs/research/default-player.md).
Nothing here is part of B-Side.

## Experiment 1: eligibility at launch

Question: does a freshly launched app that has played nothing receive the
Play key, and which registration does it take?

`eligibility/main.swift` is a menu-bar app ("Spike: <variant>" in the menu
bar) that plays no audio and logs every remote command it receives, and any
launch of Apple Music. It is built four times with different bundle IDs, so
no variant inherits system state from another:

| Variant | What it does at launch |
|---|---|
| `none` | Command handlers only |
| `paused` | Handlers, Now Playing info, `playbackState = .paused` |
| `playpaused` | Handlers, info, `.playing`, then `.paused` after 0.5 s |
| `playstopped` | Handlers, `.playing` then `.stopped` at once, then info (AntiMusic's trick) |

Run it (needs your hands: you press F8 in each round):

```bash
spikes/default-player/run-eligibility.sh
```

The script asks you to quit B-Side, Music and Spotify, then runs a baseline
round with no spike and one round per variant. Results go to
`results/eligibility-summary.tsv`, details to `results/eligibility.log`.

Result (2026-09-30, macOS 27.0.1): only a moment of `.playing` makes an app
the target of Play; see the report.

## Experiment 2: does the Play key come back after another player

Question: B-Side has the Play key; another player takes it and then goes
away. Does Play return to B-Side, stay with the other app, or open Music?

`stack/main.swift` has two roles. `home` stands in for B-Side and claims the
key the way B-Side does. `intruder` stands in for another player: it reports
playing, and two seconds later pauses, keeps playing, or clears its Now
Playing entry. Each round has its own pair of bundle IDs, fresh on every build.

| Round | What the other player does before you press Play |
|---|---|
| `paused` | Plays, pauses, stays open |
| `quit-paused` | Plays, pauses, quits |
| `quit-playing` | Plays, quits while playing |
| `cleared` | Plays, removes its Now Playing entry, stays open |
| `browser` | A real browser tab you play and close (the browser stays open) |

```bash
spikes/default-player/run-stack.sh
```

Results go to `results/stack-summary.tsv`, details to `results/stack.log`.

Result (2026-09-30, macOS 27.0.1): the last app that played keeps the key
while it runs, even after clearing its entry; when it quits, the key goes back
to the previous app, not to Music. See the report.

## Experiment 3: AirPods

Question: what do AirPods send (connecting, the stem, taking one out and
putting it back), who receives it, and when does Apple Music start?

Same executable as experiment 2, with an `observer` role that registers
nothing and only watches. Every role logs the default audio output device
(AirPods names are shortened to "AirPods": results are committed) and any
launch of Apple Music.

| Round | Setup | What you do |
|---|---|---|
| `none-connect` | nothing registered | AirPods into the case, then back into your ears |
| `none-press` | nothing registered | Press the stem once |
| `home-connect` | a home app has claimed the key | AirPods into the case, then back into your ears |
| `home-press` | same | Press the stem once |
| `home-ear` | same, nothing playing | One AirPod out for 3 s, then back |
| `bside-ear` | B-Side playing through the AirPods | One AirPod out for 3 s, then back |
| `bside-press` | same | Press the stem, wait, press again |

```bash
spikes/default-player/run-airpods.sh
```

For B-Side rounds only command and play-state lines are copied from B-Side's
event log, no track titles. Results go to `results/airpods-summary.tsv`,
details to `results/airpods.log`.

Result (2026-09-30, macOS 27.0.1): connecting AirPods sends nothing; the stem
starts Music only when no app holds the Play key; with the key claimed, all
AirPods commands reach the app. See the report.
