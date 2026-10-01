// Serves the API on http://localhost:3000 without Vercel, for testing the
// app against it: `npm run dev`. Needs AI_GATEWAY_API_KEY and the Upstash
// KV_REST_API_* variables in .env.local.
import { createServer } from "node:http";
import { GET as health } from "../api/v1/health.js";
import { POST as vibe } from "../api/v1/vibe.js";

const port = Number(process.env.PORT ?? 3000);

createServer(async (incoming, outgoing) => {
  const chunks: Buffer[] = [];
  for await (const chunk of incoming) chunks.push(chunk as Buffer);
  const url = new URL(incoming.url ?? "/", `http://localhost:${port}`);
  const request = new Request(url, {
    method: incoming.method,
    headers: { ...(incoming.headers as Record<string, string>), "x-real-ip": incoming.socket.remoteAddress ?? "local" },
    body: incoming.method === "POST" ? Buffer.concat(chunks) : undefined,
  });
  const response = url.pathname === "/v1/vibe" && incoming.method === "POST" ? await vibe(request)
    : url.pathname === "/v1/health" ? await health()
    : new Response("Not found", { status: 404 });
  outgoing.writeHead(response.status, Object.fromEntries(response.headers));
  outgoing.end(Buffer.from(await response.arrayBuffer()));
  console.log(incoming.method, url.pathname, response.status);
}).listen(port, () => console.log(`B-Side server on http://localhost:${port}`));
