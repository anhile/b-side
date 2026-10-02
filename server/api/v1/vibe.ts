import { ipAddress, waitUntil } from "@vercel/functions";
import * as limits from "../../lib/limits.js";
import { cost } from "../../lib/prices.js";
import { maxWords, read, type Mix, type Reading } from "../../lib/reading.js";

export const config = { maxDuration: 15 };

const mixes: Mix[] = ["familiar", "both", "new"];
export const installPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// POST {words, mix, install} → {name, energy, tags, artists, vocals}.
/// The words are not stored. Limits: per address, per install a month,
/// and a daily budget for everyone; the monthly hard limit is the AI
/// Gateway budget. Production answers only once VIBE_OPEN is set.
export async function POST(request: Request): Promise<Response> {
  if (!open()) return json({ error: "Vibes are not open.", reason: "closed" }, 503);

  let body: { words?: unknown; mix?: unknown; install?: unknown };
  try {
    body = await request.json();
  } catch {
    return json({ error: "The body must be JSON." }, 400);
  }
  const words = typeof body.words === "string" ? body.words.trim() : "";
  const mix = mixes.includes(body.mix as Mix) ? (body.mix as Mix) : "both";
  const install = typeof body.install === "string" && installPattern.test(body.install) ? body.install.toLowerCase() : "";
  if (!words || words.length > maxWords) return json({ error: `Words must be 1 to ${maxWords} characters.` }, 400);
  if (!install) return json({ error: "An install ID (a UUID) is needed." }, 400);

  const address = await limits.allowAddress(ipAddress(request) ?? "unknown");
  if (!address.ok) return json({ error: "Too many requests. Try again in a few minutes.", reason: "address" }, 429, address.retryAfter);

  const hit = await limits.cached(words, mix);
  if (hit) return json(hit, 200);

  if (!(await limits.budgetLeft())) return json({ error: "Vibes are resting until tomorrow.", reason: "budget" }, 503, 3600);
  if (!(await limits.takeVibe(install))) {
    return json({ error: `This Mac has made its ${limits.installMonthly} vibes this month.`, reason: "install" }, 429, limits.untilNextMonth());
  }

  try {
    const result = await read(words, mix, model(), request.signal, fallbacks());
    // Not the moment: it retells the words, which are not kept.
    const { moment: _, ...reading } = result.reading;
    waitUntil(Promise.all([
      (result.dollars !== undefined ? Promise.resolve(result.dollars)
        : cost(result.model, result.inputTokens, result.outputTokens)).then(limits.addSpend),
      limits.remember(words, mix, reading as Reading),
    ]).catch((error) => console.error("vibe: bookkeeping failed", error)));
    return json(reading, 200);
  } catch (error) {
    waitUntil(limits.returnVibe(install).catch(() => {}));
    console.error("vibe: reading failed", error instanceof Error ? error.message : error);
    return json({ error: "The words could not be read. Try again later.", reason: "model" }, 502);
  }
}

/// Previews answer whenever the store is there; production also needs
/// VIBE_OPEN, the owner's switch.
export function open(): boolean {
  if (!limits.hasStore()) return false;
  return process.env.VERCEL_ENV !== "production" || process.env.VIBE_OPEN === "1";
}

// Chosen by the comparison in docs/plans/vibe-server.md, section 5a.
function model(): string {
  return process.env.VIBE_MODEL || "openai/gpt-6-luna";
}

function fallbacks(): string[] {
  return (process.env.VIBE_FALLBACK_MODELS ?? "anthropic/claude-haiku-4.5").split(",").filter(Boolean);
}

function json(value: unknown, status: number, retryAfter?: number): Response {
  const headers: Record<string, string> = { "Cache-Control": "no-store" };
  if (retryAfter) headers["Retry-After"] = String(retryAfter);
  return Response.json(value, { status, headers });
}
