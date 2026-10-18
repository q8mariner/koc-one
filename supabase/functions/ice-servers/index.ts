// ICE servers for ORT ↔ employee voice calls.
// STUN alone fails on many mobile/corporate networks (carrier NAT), so a TURN relay is needed for reliable calls.
// Configure ONE of these as Edge Function secrets:
//   CF_TURN_KEY_ID + CF_TURN_API_TOKEN   → Cloudflare Realtime TURN (first 1,000 GB/month free)
//   TURN_URLS + TURN_USERNAME + TURN_CREDENTIAL → any TURN server with fixed credentials
//   TURN_URLS + TURN_SECRET              → any TURN server with static-auth (time-limited) credentials
// Without them only STUN is returned (works on simple networks).
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
const STUN = { urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] };

async function hmacSha1B64(secret: string, msg: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(msg)));
  return btoa(String.fromCharCode(...sig));
}

async function turn(): Promise<{ source: string; servers: unknown[] }> {
  const cfKey = Deno.env.get("CF_TURN_KEY_ID"), cfToken = Deno.env.get("CF_TURN_API_TOKEN");
  if (cfKey && cfToken) {
    const r = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${cfKey}/credentials/generate-ice-servers`, {
      method: "POST",
      headers: { Authorization: `Bearer ${cfToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ ttl: 86400 }),
    });
    if (r.ok) {
      const j = await r.json();
      const list = Array.isArray(j.iceServers) ? j.iceServers : [j.iceServers];
      return { source: "cloudflare", servers: list };
    }
  }
  const urls = (Deno.env.get("TURN_URLS") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (urls.length) {
    let username = Deno.env.get("TURN_USERNAME") ?? "";
    let credential = Deno.env.get("TURN_CREDENTIAL") ?? "";
    const secret = Deno.env.get("TURN_SECRET");
    if (!username && secret) {
      username = `${Math.floor(Date.now() / 1000) + 24 * 3600}:one`;
      credential = await hmacSha1B64(secret, username);
    }
    if (username) return { source: "custom", servers: [{ urls, username, credential }] };
  }
  return { source: "stun-only", servers: [] };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let t = { source: "stun-only", servers: [] as unknown[] };
  try { t = await turn(); } catch (_) { /* fall back to STUN */ }
  return new Response(JSON.stringify({ iceServers: [STUN, ...t.servers], relay: t.source }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
