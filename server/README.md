# B-Side server

Reads the words of a vibe ("Dota playing", "Грустный вечер, русский рок
90-х") with a language model, for the app's New Vibe sheet. The app turns
the answer into music itself: it checks every artist against YouTube Music
search with the user's own session, so this server never sees their
account. The words are not stored.

Optional: B-Side works without it, with Apple's on-device model. The plan,
limits and costs are in [docs/plans/vibe-server.md](../docs/plans/vibe-server.md).

## Endpoints

- `POST /v1/vibe` with `{"words": "...", "mix": "familiar" | "both" | "new"}`
  returns `{moment, energy, name, tags, artists, vocals}`.
- `GET /v1/health` returns `{"vibes": true}` when vibes can be made.

## Run your own

1. A Vercel project with this folder as its root, and AI Gateway on.
2. `VIBE_MODEL` set to a Gateway model slug (see `.env.example`).
3. In B-Side: Settings → Vibes → server address.

## Comparing models

`npm run compare` reads 15 prompts in three languages with several models
and checks every artist they name against YouTube Music search. Put
`AI_GATEWAY_API_KEY` in `.env.local` first. Results go to `results/`.
