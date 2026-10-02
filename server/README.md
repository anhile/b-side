# B-Side server

Reads the words of a vibe ("Dota playing", "Грустный вечер, русский рок
90-х") with a language model, for the app's New Vibe sheet. The app turns
the answer into music itself: it checks every artist against YouTube Music
search with the user's own session, so this server never sees their
account.

Nothing about the user is stored:
- The words are not stored.
- The same words and mix are answered from a cache for 7 days. The cache
  key is a hash of the words, and the value is the reading (name, genres,
  artists).
- Limits count by a hash of the address and by a random install ID the
  app makes.

Optional: B-Side works without it, with Apple's on-device model. The plan,
limits and costs are in [docs/plans/vibe-server.md](../docs/plans/vibe-server.md).

## Endpoints

- `POST /v1/vibe` with `{"words": "...", "mix": "familiar" | "both" | "new"}`
  returns `{moment, energy, name, tags, artists, vocals}`.
- `GET /v1/health` returns `{"vibes": true, "perMonth": 10}` when vibes
  can be made. With the install ID in the `X-BSide-Install` header, also
  `"left"`: how many of this month's vibes that Mac still has.

## Limits

All of them come from environment variables:
- `VIBE_IP_PER_10_MINUTES`, default 10.
- `VIBE_INSTALL_MONTHLY`, default 10.
- `VIBE_DAILY_BUDGET_USD`, default 1.
- The monthly hard limit is the AI Gateway budget, set in the Vercel
  dashboard.
- Production answers only with `VIBE_OPEN=1`; previews always answer.
- Storage is Upstash Redis from the Vercel Marketplace (`KV_REST_API_*`).

## Run your own

1. A Vercel project with this folder as its root, AI Gateway on, and
   Upstash Redis connected.
2. `VIBE_MODEL` set to a Gateway model slug (see `.env.example`).
3. In B-Side: Settings → Vibes → server address.

## Running it locally

`npm run dev` serves the API on http://localhost:3000. It needs
`AI_GATEWAY_API_KEY` in `.env.local`, and the Upstash variables
(`vercel env pull .env.development.local --environment preview`, then
delete the `VIBE_*` lines: sensitive values come down as placeholders).
Point B-Side at it in Settings → Vibes, or launch it with
`-vibeServerURL http://localhost:3000`.

## Comparing models

`npm run compare` reads 15 prompts in three languages with several models
and checks every artist they name against YouTube Music search. Put
`AI_GATEWAY_API_KEY` in `.env.local` first. Results go to `results/`.
