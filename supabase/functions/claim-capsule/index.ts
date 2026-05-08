import { preflight, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") return jsonResponse({ error: "method" }, 405);

  let user, client;
  try {
    ({ client, user } = await requireUser(req));
  } catch (r) {
    return r as Response;
  }

  const { capsule_id } = await req.json().catch(() => ({}));
  if (!capsule_id) return jsonResponse({ error: "capsule_id required" }, 400);

  const { data, error } = await client.rpc("claim_capsule", {
    p_capsule: capsule_id,
  });

  if (error) {
    if (error.code === "23505") return jsonResponse({ error: "already_claimed" }, 409);
    if (error.code === "28000") return jsonResponse({ error: "unauthorized" }, 401);
    return jsonResponse({ error: error.message }, 400);
  }

  return jsonResponse({ capsule: data, owner: user.id });
});
