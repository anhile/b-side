# Plan: the B-Side vibe server

Draft 2026-10-01; the owner's decisions are in section 8. Step 1 is in
progress.
Background: [docs/research/vibe-from-prompt.md](../research/vibe-from-prompt.md).

## 1. Goal

Vibes made from words are better when a large model reads the words.
Claude knows Russian rock, deep cuts and scenes that Apple's on-device
model does not.

The plan:
- The owner runs a small free server that asks Claude through the owner's
  Vercel AI Gateway.
- B-Side can use it as an option.
- Without it, everything works as today.

Limits:
- Usage stays under control: a hard monthly budget, and fair limits for
  each install.
- No accounts and no keys in the app.

## 2. The one rule that shapes everything

B-Side is open source, so anything in the app can be read: a key, a
secret, the request format. The server cannot trust the app. It stays
safe in three ways:

1. **It is useless for anything else.** The server takes only the words
   (up to 200 characters) and returns only a reading: name, genres,
   artists, vocals, energy.
   - The prompt is written on the server.
   - The answer is checked against a schema; anything else is dropped.
   - It cannot be used as a free general chatbot, so there is nothing to
     steal.
2. **Limits that hold without trust.** Per IP, per install, and one
   global daily and monthly budget.
3. **A hard stop.** The AI Gateway's monthly budget makes Vercel refuse
   requests (HTTP 402) once it is spent. The app then quietly falls back
   to Apple's model.

## 3. Shape

```
B-Side ──POST /v1/vibe──▶ Vercel Function ──▶ AI Gateway ──▶ Claude
   │   {words, mix}            │  limits, cache                (Sonnet 5.5)
   │                           ▼
   │                     Upstash Redis (counters, cache)
   ◀── {name, tags, artists, vocals, energy, moment} ──┘
```

After that, nothing changes in the app. It checks every artist against
YouTube Music search, picks the seeds, and plays radios, exactly as it
does with Apple's model today. So the server only replaces
`VibeMaker.read`.

### The server

- **Code.** A `server/` folder in this repo, open like the app. One
  Vercel project with its root there.
- **Runtime.** TypeScript, AI SDK `generateObject` with a zod schema, and
  the model as a gateway slug. Check the slug against
  `gateway.getAvailableModels()` before pinning it.
- **Endpoints:**
  - `POST /v1/vibe` with `{ words, mix, install }`. It returns the reading,
    or 429 with `Retry-After`, or 503 when the budget is spent.
  - `GET /v1/health` returns whether vibes are on, so the app can hide
    the option when the owner turns it off.
- **The prompt.** The one tuned on Apple's model (the moment and energy
  first, no example artists), plus "you may name artists from any
  country". On Sonnet 5.5 thinking goes off (`between_tools`), and output
  is capped at about 400 tokens.
- **Cache.** The same words with the same mix give the same reading for 7
  days. The key is the normalised words plus the mix, and Redis holds it.
  The example chips then cost nothing after the first time.
- **Logs.** Counts and costs only, tagged in the Gateway. The words are
  not stored, except as the cache key, which is a hash.

### Limits (numbers for the owner to decide, section 8)

| Limit | Where | Starting value |
|---|---|---|
| Per IP | Vercel Firewall rate limit rule, or Upstash ratelimit | 10 per 10 minutes |
| Per install | Upstash, keyed by a random install ID the app makes once | 10 per month |
| Global per day | Upstash counter of spent cents | $1, so one bad day cannot spend the month |
| Global per month | AI Gateway budget, hard limit | $20 |

The install ID is not a secret and can be faked. It keeps honest users
fair, and the IP and budget limits catch the rest. Stronger checks for a
later step:
- Apple App Attest, which proves the request comes from a real copy of
  B-Side. Whether it works for an app signed with Developer ID, outside
  the App Store, is unverified.
- Signing in with YouTube is not usable: the server cannot check that
  cheaply.

### Cost

Measured at about 500 tokens in and 200 out per reading. Prices are
Anthropic's list prices, 2026-09-25; the Gateway adds no markup
(Vercel's docs).

| Model | Per vibe | 1,000 vibes |
|---|---|---|
| Haiku 4.5 | ~$0.0015 | ~$1.5 |
| Sonnet 5.5, thinking off | ~$0.003 | ~$3 |

The $30 monthly budget buys about 10,000 vibes on Sonnet 5.5, more with
the cache. Upstash and Vercel Functions fit their free tiers at this
size; check the current limits before launch.

## 4. The app

- **Settings → Vibes**, a new section:
  - "Make vibes with the B-Side server" (on or off, section 8), with one
    line: "Your words go to the B-Side server and to Anthropic to be
    read. They are not stored."
  - Server address, default `https://<owner's domain>`. A self-hosted
    copy or `http://localhost:3000` works too: anyone can run `server/`
    with their own Gateway key.
- **`VibeMaker.read` tries in order:**
  1. The server, when it is on and answers within about 8 s.
  2. Apple's model.
  3. YouTube Music's moods.
  It logs which one answered.
- **The sheet:**
  - The footer line names the source ("Read by Claude" or "Read on this
    Mac").
  - On 429 or 503 it falls back without an error. The preview's note
    says: "The B-Side server is busy, so this Mac read the words."
- **The install ID.** A random UUID in UserDefaults, made once, sent only
  to the server.
- **Debug.** `-makeVibe` and `-vibeServer <url>` test all of it without
  the screen.

## 5. Steps

1. **The server.** `server/` with `/v1/vibe` and `/v1/health`, schema
   checks, and the prompt. Deploy to a Vercel preview. Test with curl on
   the same prompts as the research: three English, two Russian, Dota.
2. **Limits and cache.** Upstash from the Vercel Marketplace, the four
   limits, the Gateway budget and the cache. Test that 429 and 503 come
   back as they should.
3. **The app.** The Settings section, the client, the fallbacks, and the
   source line in the sheet. Test with `-makeVibe` against the preview
   server.
4. **Comparison.** 30 prompts in three languages, server against Apple's
   model. Measure the share of artists that search confirms, and how
   many of the first songs fit (by ear, by the owner, for 10 of them).
5. **Launch.**
   - The production domain and the README sections: the privacy line,
     and how to run your own server.
   - Turn it on in the app.

Steps 1 and 2 need the owner's Vercel account (`vercel link`, the
Gateway key as an environment variable, and Upstash). Claude cannot
create accounts or enter keys; the owner does those, and Claude writes
the code and the commands.

## 5a. Step 1 result: the model (2026-10-02)

15 prompts in English, Russian and Spanish, one run each. Every answer is
in [server/results/compare-2026-10-01.md](../../server/results/compare-2026-10-01.md).

| Model | Artists confirmed by search | Median time | Cost per vibe |
|---|---|---|---|
| Claude Haiku 4.5 | 95% | 2.7 s | $0.0012 |
| Gemini 3.8 Flash | 99% | 5.6 s | $0.0020 |
| GPT-6 Luna | 94% | 4.0 s | $0.00017 |
| DeepSeek V4 Flash | 99%, one failed answer | 11.6 s | $0.00032 |
| Claude Sonnet 5.5 (reference) | 97% | 3.1 s | $0.0034 |

Every model knows far more than Apple's on-device model. Russian rock 90s
gets Кино, ДДТ, Сплин, Наутилус from all of them. The difference is taste:
- **Gemini and Luna** are the most specific: Молчат Дома and
  Электрофорез for a night walk in Petersburg, phonk for leg day.
- **Luna** reads a Russian request as a wish for Russian music more often
  (a Monday morning gets Звери and Little Big).
- **Haiku** sometimes answers a Russian request with Western names.
- Gemini costs more than its list price suggests: it thinks before
  answering.

Decision: **`openai/gpt-6-luna`**, with `anthropic/claude-haiku-4.5` as the
Gateway fallback model when it fails.
- $20 a month buys about 100,000 vibes on Luna.
- The 6% of artists search cannot confirm are dropped by the app, as
  today.
- DeepSeek is out: slow, and it failed once.

## 6. What stays out

- Accounts, payments, keys in the app.
- The server choosing songs. YouTube Music search stays in the app, with
  the user's own session, so the server never sees their account.
- Storing the words or anything about the user beyond the counters.

## 7. Risks

| Risk | Answer |
|---|---|
| Someone floods the server | IP limits, then the daily and monthly budgets; the app falls back to Apple's model |
| The budget runs out early in a month | 503 from `/v1/health`; the option shows "Off this month", the app keeps working |
| Vercel or Anthropic is slow or down | 8 s timeout, then Apple's model |
| Words with personal data | Not stored; said in Settings; the cache key is a hash |
| The model names artists that do not exist | The app checks every artist against YouTube Music search, as today |

## 8. Decisions (owner, 2026-10-01)

1. **Off by default.** The user turns it on in Settings, which says the
   words leave the Mac.
2. **Model: the cheapest that knows music well,** chosen by a comparison
   on the same prompts (step 1). It is an environment variable, so it can
   change without an app release.
3. **Limits:**
   - $20 a month for everyone: the Gateway budget, as a hard limit.
   - 10 vibes a month per install.
   - Only model calls count: cache hits are free, and a change of the
     artists' mix is a new call.
   - The IP limit stays as in section 3.
4. **Domain:** `b-side.anhile.com`.
5. **The server is open source,** in `server/` in this repo, under the
   app's licence.
   - Its safety rests on limits and the budget, not on hidden code.
   - Settings promises the words are not stored, and open code lets
     anyone check that.
   - Self-hosting needs the code.
   - Secrets and the limits' numbers live in environment variables.
