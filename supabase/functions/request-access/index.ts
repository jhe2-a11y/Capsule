import { preflight, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") return jsonResponse({ error: "method" }, 405);

  let client, user;
  try { ({ client, user } = await requireUser(req)); }
  catch (r) { return r as Response; }

  const { capsule_id, message } = await req.json().catch(() => ({}));
  if (!capsule_id) return jsonResponse({ error: "capsule_id required" }, 400);

  const { error } = await client
    .from("access_requests")
    .upsert(
      { capsule_id, requester_id: user.id, message: message ?? null },
      { onConflict: "capsule_id,requester_id" },
    );

  if (error) return jsonResponse({ error: error.message }, 400);
  return jsonResponse({ ok: true });
});
