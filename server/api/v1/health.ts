/// Whether vibes can be made now, so the app can say so in Settings.
export function GET(): Response {
  const open = process.env.VERCEL_ENV !== "production" || Boolean(process.env.VIBE_LIMITS_READY);
  return Response.json({ vibes: open }, { headers: { "Cache-Control": "no-store" } });
}
