import { budgetLeft, installMonthly } from "../../lib/limits.js";
import { open } from "./vibe.js";

/// Whether vibes can be made now, and how many a Mac gets a month, so the
/// app can say so in Settings.
export async function GET(): Promise<Response> {
  const vibes = open() && (await budgetLeft().catch(() => false));
  return Response.json({ vibes, perMonth: installMonthly }, { headers: { "Cache-Control": "no-store" } });
}
