import { preflight, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";

function randomToken(len = 16): string {
  const bytes = new Uint8Array(len);
  crypto.getRandomValues(bytes);
  const alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
  let out = "";
  for (const b of bytes) out += alphabet[b % alphabet.length];
  return out;
}

Deno.serve(async (req) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") return jsonResponse({ error: "method" }, 405);

  let client, user;
  try { ({ client, user } = await requireUser(req)); }
  catch (r) { return r as Response; }

  const { capsule_id, ttl_hours = 168 } = await req.json().catch(() => ({}));
  if (!capsule_id) return jsonResponse({ error: "capsule_id required" }, 400);

  const token = randomToken();
  const expires = new Date(Date.now() + ttl_hours * 3600 * 1000).toISOString();

  const { data, error } = await client
    .from("capsule_invites")
    .insert({ token, capsule_id, expires_at: expires, created_by: user.id })
    .select()
    .single();

  if (error) return jsonResponse({ error: error.message }, 400);
  return jsonResponse({ token: data.token, expires_at: data.expires_at });
});
