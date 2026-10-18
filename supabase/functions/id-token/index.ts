// Dynamic digital-ID code: a signed token valid for 30 seconds (a screenshot can't be reused).
//   POST {}              → issue a token for the signed-in employee  {token, expires_in}
//   POST {verify: token} → ORT only: check a scanned token            {valid, profile?}
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const TTL = 30;
const enc = new TextEncoder();
const b64url = (buf: ArrayBuffer) =>
  btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

async function sign(payload: string) {
  const secret = Deno.env.get("ID_SIGNING_SECRET") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64url((await crypto.subtle.sign("HMAC", key, enc.encode(payload))).slice(0, 18));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return json({ error: "unauthorized" }, 401);
    const body = await req.json().catch(() => ({}));

    if (body.verify) {
      const { data: me } = await admin.from("profiles").select("role").eq("id", user.id).single();
      if (me?.role !== "ort") return json({ error: "ORT only" }, 403);
      const [v, uid, exp, sig] = String(body.verify).split(".");
      const now = Math.floor(Date.now() / 1000);
      const ok = v === "ONE1" && sig === (await sign(`${uid}.${exp}`)) && Number(exp) + 10 >= now;
      if (!ok) return json({ valid: false });
      const { data: p } = await admin.from("profiles")
        .select("full_name, employee_no, job_title, department, blood_type, active").eq("id", uid).single();
      return json({ valid: !!p?.active, profile: p });
    }

    const exp = Math.floor(Date.now() / 1000) + TTL;
    const token = `ONE1.${user.id}.${exp}.${await sign(`${user.id}.${exp}`)}`;
    return json({ token, expires_in: TTL });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
