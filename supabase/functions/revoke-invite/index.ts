import { preflight, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") return jsonResponse({ error: "method" }, 405);

  let client;
  try { ({ client } = await requireUser(req)); }
  catch (r) { return r as Response; }

  const { token } = await req.json().catch(() => ({}));
  if (!token || typeof token !== "string") {
    return jsonResponse({ error: "token required" }, 400);
  }

  const { error } = await client.rpc("revoke_invite", { p_token: token });

  if (error) {
    if (error.code === "42501") return jsonResponse({ error: "not_authorized" }, 403);
    if (error.code === "02000") return jsonResponse({ error: "not_found" }, 404);
    if (error.code === "28000") return jsonResponse({ error: "unauthorized" }, 401);
    return jsonResponse({ error: error.message }, 400);
  }

  return jsonResponse({ ok: true });
});
