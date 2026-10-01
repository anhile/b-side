import { maxWords, read, type Mix } from "../../lib/reading.js";

export const config = { maxDuration: 15 };

const mixes: Mix[] = ["familiar", "both", "new"];

/// POST {words, mix, install} → the reading of the words. Nothing is
/// stored. Limits come in step 2 of docs/plans/vibe-server.md; until then
/// production refuses, so only previews answer.
export async function POST(request: Request): Promise<Response> {
  if (process.env.VERCEL_ENV === "production" && !process.env.VIBE_LIMITS_READY) {
    return json({ error: "Vibes are not open yet." }, 503);
  }
  let body: { words?: unknown; mix?: unknown };
  try {
    body = await request.json();
  } catch {
    return json({ error: "The body must be JSON." }, 400);
  }
  const words = typeof body.words === "string" ? body.words.trim() : "";
  const mix = mixes.includes(body.mix as Mix) ? (body.mix as Mix) : "both";
  if (!words || words.length > maxWords) {
    return json({ error: `Words must be 1 to ${maxWords} characters.` }, 400);
  }
  try {
    const { reading } = await read(words, mix, model(), request.signal, fallbacks());
    return json(reading, 200);
  } catch (error) {
    console.error("vibe: reading failed", error instanceof Error ? error.message : error);
    return json({ error: "The words could not be read. Try again later." }, 502);
  }
}

// Chosen by the comparison in docs/plans/vibe-server.md, section 5a.
function model(): string {
  return process.env.VIBE_MODEL || "openai/gpt-6-luna";
}

function fallbacks(): string[] {
  return (process.env.VIBE_FALLBACK_MODELS ?? "anthropic/claude-haiku-4.5").split(",").filter(Boolean);
}

function json(value: unknown, status: number): Response {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
}
