import { createHash } from "node:crypto";
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";
import type { Mix, Reading } from "./reading.js";

// Every number comes from the environment, so the owner can change it
// without a release; the defaults are the ones decided in
// docs/plans/vibe-server.md, section 8.
const number = (name: string, fallback: number) => Number(process.env[name] ?? "") || fallback;
export const installMonthly = number("VIBE_INSTALL_MONTHLY", 10);
const ipPerTenMinutes = number("VIBE_IP_PER_10_MINUTES", 10);
const dailyBudgetUSD = number("VIBE_DAILY_BUDGET_USD", 1);
const cacheDays = 7;

let client: Redis | undefined;
function redis(): Redis {
  // The Upstash integration on Vercel names its variables KV_REST_API_*.
  client ??= new Redis({ url: process.env.KV_REST_API_URL!, token: process.env.KV_REST_API_TOKEN! });
  return client;
}

export const hasStore = () => Boolean(process.env.KV_REST_API_URL && process.env.KV_REST_API_TOKEN);

let ipLimiter: Ratelimit | undefined;

/// Ten requests per ten minutes from one address, cached answers included:
/// the cheapest line against a script.
export async function allowAddress(ip: string): Promise<{ ok: boolean; retryAfter: number }> {
  ipLimiter ??= new Ratelimit({ redis: redis(), limiter: Ratelimit.slidingWindow(ipPerTenMinutes, "10 m"), prefix: "vibe:ip" });
  // A hash, not the address: nothing about the user is kept.
  const result = await ipLimiter.limit(createHash("sha256").update(`b-side:${ip}`).digest("hex").slice(0, 32));
  return { ok: result.success, retryAfter: Math.max(1, Math.ceil((result.reset - Date.now()) / 1000)) };
}

const month = () => new Date().toISOString().slice(0, 7);
const day = () => new Date().toISOString().slice(0, 10);

/// Takes one of the install's vibes for this month; false when they are
/// used up. Given back by `returnVibe` when the model fails.
export async function takeVibe(install: string): Promise<boolean> {
  const key = `vibe:install:${install}:${month()}`;
  const used = await redis().incr(key);
  if (used === 1) await redis().expire(key, 40 * 24 * 3600);
  if (used > installMonthly) {
    await redis().decr(key);
    return false;
  }
  return true;
}

export async function returnVibe(install: string): Promise<void> {
  await redis().decr(`vibe:install:${install}:${month()}`);
}

/// Seconds until the first day of next month, for Retry-After.
export function untilNextMonth(): number {
  const now = new Date();
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1);
  return Math.ceil((next - now.getTime()) / 1000);
}

// Spend is kept in millionths of a dollar, so it stays an integer.
export async function budgetLeft(): Promise<boolean> {
  const spent = Number((await redis().get<number>(`vibe:spend:${day()}`)) ?? 0);
  return spent < dailyBudgetUSD * 1e6;
}

export async function addSpend(dollars: number): Promise<void> {
  const key = `vibe:spend:${day()}`;
  await redis().incrby(key, Math.ceil(dollars * 1e6));
  await redis().expire(key, 3 * 24 * 3600);
}

/// The reading for the same words and mix, kept 7 days. The key is a hash:
/// the words themselves are not stored.
const cacheKey = (words: string, mix: Mix) =>
  "vibe:cache:" + createHash("sha256").update(`${mix}\n${words.normalize("NFC").toLowerCase().replace(/\s+/g, " ").trim()}`).digest("hex");

export async function cached(words: string, mix: Mix): Promise<Reading | null> {
  return redis().get<Reading>(cacheKey(words, mix));
}

export async function remember(words: string, mix: Mix, reading: Reading): Promise<void> {
  await redis().set(cacheKey(words, mix), reading, { ex: cacheDays * 24 * 3600 });
}
