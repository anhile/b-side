import { budgetLeft, installMonthly, vibesLeft } from "../../lib/limits.js";
import { installPattern, open } from "./vibe.js";

/// Whether vibes can be made now, and how many a Mac gets a month, so the
/// app can say so in Settings. With the Mac's install ID in the
/// X-BSide-Install header, also how many it has left this month.
export async function GET(request: Request): Promise<Response> {
  const vibes = open() && (await budgetLeft().catch(() => false));
  const install = request.headers.get("x-bside-install") ?? "";
  const left = vibes && installPattern.test(install)
    ? await vibesLeft(install.toLowerCase()).catch(() => undefined)
    : undefined;
  return Response.json({ vibes, perMonth: installMonthly, left }, { headers: { "Cache-Control": "no-store" } });
}
