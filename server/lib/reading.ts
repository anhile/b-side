import { generateText, Output } from "ai";
import { z } from "zod";

/// What the words of a vibe mean: the same fields as VibeMaker.Reading in
/// the app, which checks every artist against YouTube Music search itself.
export const readingSchema = z.object({
  moment: z.string().describe("What the listener is doing or feeling, and the energy and tempo the music needs for it, in one short English sentence"),
  energy: z.number().int().describe("Energy the music needs, from 1 (still) to 5 (intense)"),
  name: z.string().describe("A short, warm name for this vibe, two or three words, in the language of the request"),
  tags: z.array(z.string()).describe("Two to four music genres or styles a music search understands, in English, such as 'cool jazz', 'synthwave', 'lo-fi hip hop'"),
  artists: z.array(z.string()).describe("Four to eight real artists whose music fits the moment and its energy, written exactly as streaming services credit them, in their own script"),
  vocals: z.enum(["any", "with", "without"]).describe("Whether the songs should have singing"),
});

export type Reading = z.infer<typeof readingSchema>;
export type Mix = "familiar" | "both" | "new";

const mixLine: Record<Mix, string> = {
  familiar: "Prefer well-known artists.",
  both: "Mix well-known artists with lesser-known ones.",
  new: "Prefer lesser-known artists; avoid the most famous names.",
};

// Written first, the moment and energy make the model work out the
// activity before it picks music ("Dota playing" got quiet folk without
// them). No example artists: small models copy them into any answer.
function instructions(mix: Mix): string {
  return [
    "You choose music for a listener who describes a mood, an activity, a moment or a place, in any language.",
    "First work out what they are doing and how much energy the music needs: an activity such as sport, gaming or cleaning needs driving, energetic music; rest and sleep need calm music.",
    "Choose artists from any country; when the words point to a country, a language or a scene, choose artists from there.",
    mixLine[mix],
    "Name only artists you are sure exist, as streaming services credit them. Never name songs.",
    "If the listener asks for no vocals or no lyrics, choose artists who make instrumental music.",
  ].join(" ");
}

export const maxWords = 200;

export interface ReadResult {
  reading: Reading;
  inputTokens: number;
  outputTokens: number;
  milliseconds: number;
}

/// Reads the words with the model given as a Gateway slug. Throws when the
/// model fails or its answer does not fit the schema.
/// `fallbacks`: Gateway model slugs tried in order when `model` fails.
export async function read(words: string, mix: Mix, model: string, signal?: AbortSignal,
                           fallbacks: string[] = []): Promise<ReadResult> {
  const start = Date.now();
  const result = await generateText({
    model,
    system: instructions(mix),
    prompt: words.slice(0, maxWords),
    output: Output.object({ schema: readingSchema }),
    maxOutputTokens: 1500, // room for models that think before answering
    abortSignal: signal,
    providerOptions: fallbacks.length ? { gateway: { models: fallbacks } } : undefined,
  });
  return {
    reading: tidy(result.output),
    inputTokens: result.usage.inputTokens ?? 0,
    outputTokens: result.usage.outputTokens ?? 0,
    milliseconds: Date.now() - start,
  };
}

/// The schema leaves counts and ranges to the description (not every
/// provider takes them in a schema); they are enforced here.
function tidy(reading: Reading): Reading {
  const seen = new Set<string>();
  const artists = reading.artists
    .map((name) => name.trim())
    .filter((name) => name && !seen.has(name.toLowerCase()) && seen.add(name.toLowerCase()));
  return {
    ...reading,
    energy: Math.min(5, Math.max(1, Math.round(reading.energy))),
    tags: reading.tags.map((tag) => tag.trim()).filter(Boolean).slice(0, 4),
    artists: artists.slice(0, 8),
  };
}
