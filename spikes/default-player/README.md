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
