// Compares models for reading vibe words: how many of the artists each one
// names does YouTube Music search confirm, how fast, and at what cost.
// Run: npm run compare (needs AI_GATEWAY_API_KEY in .env.local).
import { writeFile } from "node:fs/promises";
import { read, type ReadResult } from "../lib/reading.js";
import { credits, searchSongs } from "./youtube.js";

const models = (process.env.MODELS ??
  "anthropic/claude-haiku-4.5,google/gemini-3.8-flash,openai/gpt-6-luna,deepseek/deepseek-v4-flash,anthropic/claude-sonnet-5.5")
  .split(",");

const prompts = [
  "Rainy Sunday morning, slow jazz, no vocals",
  "Driving at night through a neon city",
  "Focus for coding, no lyrics, not boring",
  "Dota playing",
  "Leg day at the gym",
  "Falling asleep after a long day",
  "Summer road trip with friends, 2000s indie",
  "Готовлю ужин с друзьями, что-то весёлое и русское",
  "Грустный вечер, русский рок 90-х",
  "Утро понедельника, нужен заряд бодрости",
  "Как в старом советском кино",
  "Ночная прогулка по Питеру",
  "Fiesta en la playa al atardecer",
  "Domingo tranquilo con café",
  "Entrenando para un maratón",
];

interface Price { input: number; output: number }

async function prices(): Promise<Map<string, Price>> {
  const response = await fetch("https://ai-gateway.vercel.sh/v1/models");
  const { data } = (await response.json()) as { data: { id: string; pricing?: { input?: string; output?: string } }[] };
  return new Map(data.map((m) => [m.id, { input: Number(m.pricing?.input ?? 0), output: Number(m.pricing?.output ?? 0) }]));
}

const confirmedCache = new Map<string, Promise<boolean>>();
function confirmed(artist: string): Promise<boolean> {
  const key = artist.toLowerCase();
  if (!confirmedCache.has(key)) {
    confirmedCache.set(key, searchSongs(artist).then((songs) => songs.some((song) => credits(song, artist))).catch(() => false));
  }
  return confirmedCache.get(key)!;
}

interface Row { model: string; prompt: string; result?: ReadResult; error?: string; found: boolean[] }

const price = await prices();
const rows: Row[] = [];
for (const prompt of prompts) {
  const results = await Promise.all(models.map(async (model): Promise<Row> => {
    try {
      const result = await read(prompt, "both", model);
      const found = await Promise.all(result.reading.artists.map(confirmed));
      return { model, prompt, result, found };
    } catch (error) {
      return { model, prompt, error: String(error).slice(0, 160), found: [] };
    }
  }));
  rows.push(...results);
  process.stdout.write(".");
}
console.log();

const lines: string[] = [`# Vibe reading: model comparison`, ``, `Run ${new Date().toISOString()}, ${prompts.length} prompts, mix "both".`, ``,
  `| Model | Artists confirmed | Failed answers | Median time | Cost per vibe |`, `|---|---|---|---|---|`];
for (const model of models) {
  const mine = rows.filter((row) => row.model === model);
  const ok = mine.filter((row) => row.result);
  const named = ok.reduce((sum, row) => sum + row.found.length, 0);
  const found = ok.reduce((sum, row) => sum + row.found.filter(Boolean).length, 0);
  const times = ok.map((row) => row.result!.milliseconds).sort((a, b) => a - b);
  const p = price.get(model) ?? { input: 0, output: 0 };
  const cost = ok.reduce((sum, row) => sum + row.result!.inputTokens * p.input + row.result!.outputTokens * p.output, 0) / Math.max(ok.length, 1);
  lines.push(`| ${model} | ${found}/${named} (${Math.round((100 * found) / Math.max(named, 1))}%) | ${mine.length - ok.length} | ${((times[Math.floor(times.length / 2)] ?? 0) / 1000).toFixed(1)} s | $${cost.toFixed(5)} |`);
}
lines.push(``, `Artists marked ✗ were not credited on any song search returned for them.`, ``);
for (const prompt of prompts) {
  lines.push(`## ${prompt}`, ``);
  for (const row of rows.filter((r) => r.prompt === prompt)) {
    if (!row.result) { lines.push(`- **${row.model}**: failed: ${row.error}`); continue; }
    const r = row.result.reading;
    const artists = r.artists.map((artist, i) => (row.found[i] ? artist : `${artist} ✗`)).join(", ");
    lines.push(`- **${row.model}** — ${r.name} · energy ${r.energy} · ${r.vocals} · ${r.tags.join(", ")} · ${artists}`);
  }
  lines.push(``);
}
const file = `results/compare-${new Date().toISOString().slice(0, 10)}.md`;
await writeFile(file, lines.join("\n"));
console.log(lines.slice(0, 6 + models.length).join("\n"));
console.log(`\nAll answers: server/${file}`);
