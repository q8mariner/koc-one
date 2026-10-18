// ORT-only: create / delete employee accounts with the service role.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: { user } } = await admin.auth.getUser(token);
    if (!user) return json({ error: "unauthorized" }, 401);
    const { data: me } = await admin.from("profiles").select("role").eq("id", user.id).single();
    if (me?.role !== "ort") return json({ error: "ORT only" }, 403);

    const body = await req.json();
    if (body.action === "create") {
      const { email, password, full_name, employee_no, phone, blood_type, role } = body;
      const { data, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { full_name, employee_no, phone, blood_type },
      });
      if (error) return json({ error: error.message }, 400);
      if (role === "ort") await admin.from("profiles").update({ role: "ort" }).eq("id", data.user.id);
      return json({ id: data.user.id });
    }
    if (body.action === "delete") {
      const { error } = await admin.auth.admin.deleteUser(body.id);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }
    return json({ error: "unknown action" }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
