// Dollars per token for Gateway models, from its public model list,
// kept for an hour per function instance.
let prices: Map<string, { input: number; output: number }> | undefined;
let fetchedAt = 0;

export async function cost(model: string, inputTokens: number, outputTokens: number): Promise<number> {
  if (!prices || Date.now() - fetchedAt > 3600_000) {
    try {
      const response = await fetch("https://ai-gateway.vercel.sh/v1/models");
      const { data } = (await response.json()) as { data: { id: string; pricing?: { input?: string; output?: string } }[] };
      prices = new Map(data.map((m) => [m.id, { input: Number(m.pricing?.input ?? 0), output: Number(m.pricing?.output ?? 0) }]));
      fetchedAt = Date.now();
    } catch {
      prices ??= new Map();
    }
  }
  // An unknown price counts as Claude Haiku 4.5's, the dearest fallback,
  // so the daily budget errs on the safe side.
  const price = prices.get(model) ?? { input: 1e-6, output: 5e-6 };
  return inputTokens * price.input + outputTokens * price.output;
}
